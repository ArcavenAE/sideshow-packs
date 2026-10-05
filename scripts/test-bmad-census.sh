#!/usr/bin/env bash
# Scenario tests for scripts/bmad-census.py with the CI identity neutralizer.
# Self-contained: a synthetic staged tree, no network. Run from anywhere:
#
#   bash scripts/test-bmad-census.sh
#
# CI runs this via .github/workflows/intake-tests.yml.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENSUS="${SD}/bmad-census.py"
NEUTRAL="${SD}/neutralize-ci-identity.py"
DIR="$(mktemp -d -t bmad-census-test-XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

pass=0
fail=0
check_eq() { # name expected actual
    if [[ "$2" == "$3" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1: expected '$2', got '$3'"
    fi
}
check() { # name expected-substring output
    if grep -qF -- "$2" <<< "$3"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1: expected to find '$2' in:"
        printf '    %s\n' "$3"
    fi
}
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# A staged tree as the installer leaves it: two module configs that carry the
# identity answers, one untouched file, and a census that hashed all three
# before the neutralizer ran. One row names a path this layout lacks.
make_stage() { # dir
    local s="$1"
    mkdir -p "$s/_config" "$s/bmm" "$s/cis"
    printf 'user_name: arcaven-ci\nproject_name: work\nother: keep\n' > "$s/bmm/config.yaml"
    printf 'user_name: arcaven-ci\ntheme: dark\n' > "$s/cis/config.yaml"
    printf 'plain\n' > "$s/bmm/readme.md"
    {
        echo 'type,name,module,path,hash'
        printf 'yaml,config,bmm,bmm/config.yaml,%s\n' "$(sha "$s/bmm/config.yaml")"
        printf 'yaml,config,cis,cis/config.yaml,%s\n' "$(sha "$s/cis/config.yaml")"
        printf 'md,readme,bmm,bmm/readme.md,%s\n' "$(sha "$s/bmm/readme.md")"
        printf 'md,gone,bmm,bmm/not-in-this-layout.md,%s\n' "$(printf 'x' | shasum -a 256 | awk '{print $1}')"
    } > "$s/_config/files-manifest.csv"
}

S="$DIR/stage"
make_stage "$S"
python3 "$NEUTRAL" --pack-stage "$S" --sentinel-user arcaven-ci >/dev/null
cp "$S/_config/files-manifest.csv" "$DIR/census.before"

# RED: after the neutralizer and before the refresh, the census fails.
out="$(python3 "$CENSUS" verify --pack-stage "$S" 2>&1)"; rc=$?
check_eq "verify fails before refresh (exit)" "2" "$rc"
check "verify names the first edited file" "bmm/config.yaml" "$out"
check "verify counts both edited rows" "2 of 3 census entries differ" "$out"

# GREEN: refresh, then verify passes.
out="$(python3 "$CENSUS" refresh --pack-stage "$S" --record "$DIR/rec.yaml" --rule-version 1 2>&1)"; rc=$?
check_eq "refresh exit" "0" "$rc"
check "refresh reports two rows" "refreshed 2 census row(s)" "$out"
out="$(python3 "$CENSUS" verify --pack-stage "$S" 2>&1)"; rc=$?
check_eq "verify passes after refresh (exit)" "0" "$rc"
check "verify counts the unresolved row" "1 name paths not in this layout" "$out"

# Only the two edited hashes changed; every other byte of the CSV is intact.
diff_lines="$(diff "$DIR/census.before" "$S/_config/files-manifest.csv" | grep -c '^>')"
check_eq "exactly two census rows rewritten" "2" "$diff_lines"
check_eq "untouched row byte-identical" \
    "$(grep 'readme.md' "$DIR/census.before")" "$(grep 'readme.md' "$S/_config/files-manifest.csv")"

# The record carries each rewrite with the hash the installer recorded.
rec="$(cat "$DIR/rec.yaml")"
check "record has the rule version" "neutralizer_rule_version: 1" "$rec"
check "record names bmm config" "- path: bmm/config.yaml" "$rec"
check "record names cis config" "- path: cis/config.yaml" "$rec"
old_bmm="$(grep 'bmm/config.yaml' "$DIR/census.before" | awk -F, '{print $5}')"
check "record keeps the installer hash" "installer_sha256: ${old_bmm}" "$rec"
check_eq "record omits the untouched file (count)" "0" "$(grep -c 'readme' "$DIR/rec.yaml")"

# Idempotent: a second refresh changes nothing and records no rewrites.
python3 "$CENSUS" refresh --pack-stage "$S" --record "$DIR/rec2.yaml" --rule-version 1 >/dev/null
check "second refresh records none" "census_refreshed: []" "$(cat "$DIR/rec2.yaml")"

# NEGATIVE CONTROL: editing a rewritten file after the refresh must fail verify.
printf 'tampered: yes\n' >> "$S/bmm/config.yaml"
out="$(python3 "$CENSUS" verify --pack-stage "$S" 2>&1)"; rc=$?
check_eq "verify fails after a post-refresh edit (exit)" "2" "$rc"
check "post-refresh edit is named" "bmm/config.yaml" "$out"

# No census at all: nothing to do, not an error.
S2="$DIR/stage2"; mkdir -p "$S2/bmm"; printf 'a\n' > "$S2/bmm/x.md"
python3 "$CENSUS" refresh --pack-stage "$S2" --record "$DIR/rec3.yaml" --rule-version 1 >/dev/null; rc=$?
check_eq "refresh without a census (exit)" "0" "$rc"
python3 "$CENSUS" verify --pack-stage "$S2" >/dev/null; rc=$?
check_eq "verify without a census (exit)" "0" "$rc"

# The build wires both steps, refresh after the neutralizer and verify last.
has() { grep -qF -- "$1" "${SD}/build-bmad.sh" && echo yes || echo no; }
check_eq "build runs the refresh" "yes" "$(has 'bmad-census.py" refresh')"
check_eq "build runs the verify" "yes" "$(has 'bmad-census.py" verify')"
n_line="$(grep -n 'neutralize-ci-identity.py\" \\' "${SD}/build-bmad.sh" | head -1 | cut -d: -f1)"
r_line="$(grep -n 'bmad-census.py\" refresh' "${SD}/build-bmad.sh" | head -1 | cut -d: -f1)"
v_line="$(grep -n 'bmad-census.py\" verify' "${SD}/build-bmad.sh" | head -1 | cut -d: -f1)"
m_line="$(grep -n '^# 4\. Emit file-manifest.csv' "${SD}/build-bmad.sh" | head -1 | cut -d: -f1)"
[[ -n "$n_line" && -n "$r_line" && -n "$v_line" && -n "$m_line" && "$n_line" -lt "$r_line" && "$r_line" -lt "$v_line" && "$v_line" -lt "$m_line" ]] \
    && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: build order neutralize<refresh<verify<file-manifest (lines: '$n_line' '$r_line' '$v_line' '$m_line')"; }

echo "bmad-census tests: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
