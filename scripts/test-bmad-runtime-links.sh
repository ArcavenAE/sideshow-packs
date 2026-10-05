#!/usr/bin/env bash
# Scenario tests for scripts/bmad-runtime-links.py. Self-contained: a synthetic
# installer tree, no network. Run from anywhere:
#
#   bash scripts/test-bmad-runtime-links.sh
#
# CI runs this via .github/workflows/intake-tests.yml.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINKS="${SD}/bmad-runtime-links.py"
DIR="$(mktemp -d -t bmad-links-test-XXXXXX)"
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

B="$DIR/_bmad"
mkdir -p "$B"/{scripts,_config,core,bmm,cis,gds,tea,bmb,wds,custom,render,.hidden}
touch "$B/config.toml" "$B/config.user.toml" "$B/stray.txt"

out="$(python3 "$LINKS" --bmad-dir "$B" 2>&1)"; rc=$?
check_eq "exit" "0" "$rc"
names="$(grep -- '- link:' <<< "$out" | sed 's/.*link: //' | tr '\n' ' ')"
check_eq "derived list, dirs sorted then config files" \
    "_config bmb bmm cis core gds scripts tea wds config.toml config.user.toml " "$names"

# F-d: the wds module is linked, which is what makes _bmad/wds/config.yaml resolve.
check_eq "wds is linked" "1" "$(grep -c -- '- link: wds$' <<< "$out")"
check_eq "custom is not linked (bridged)" "0" "$(grep -c -- 'link: custom' <<< "$out")"
check_eq "render is not linked (writable)" "0" "$(grep -c -- 'link: render' <<< "$out")"
check_eq "hidden dir is not linked" "0" "$(grep -c -- 'link: .hidden' <<< "$out")"
check_eq "stray top-level file is not linked" "0" "$(grep -c -- 'stray' <<< "$out")"

# Every link names itself as target, at the indent pack.yaml uses.
check_eq "link and target pair up" "$(grep -c -- '- link:' <<< "$out")" "$(grep -c -- '^      target: ' <<< "$out")"
check_eq "entry indent" "0" "$(grep -- '- link:' <<< "$out" | grep -vc '^    - link: ')"

# A four-module tree without the optional config.user.toml still works.
B2="$DIR/b2"; mkdir -p "$B2"/{scripts,_config,core,bmm}; touch "$B2/config.toml"
names2="$(python3 "$LINKS" --bmad-dir "$B2" | grep -- '- link:' | sed 's/.*link: //' | tr '\n' ' ')"
check_eq "absent config.user.toml is skipped" "_config bmm core scripts config.toml " "$names2"

# Fail closed on a layout without scripts/ or _config/.
B3="$DIR/b3"; mkdir -p "$B3/bmm"
python3 "$LINKS" --bmad-dir "$B3" >/dev/null 2>&1; rc=$?
check_eq "missing scripts/_config is fatal (exit)" "2" "$rc"
# Either directory missing alone is also fatal (guards the `or` in the check).
B4="$DIR/b4"; mkdir -p "$B4"/{scripts,bmm}
python3 "$LINKS" --bmad-dir "$B4" >/dev/null 2>&1; rc=$?
check_eq "missing _config alone is fatal (exit)" "2" "$rc"
B5="$DIR/b5"; mkdir -p "$B5"/{_config,bmm}
python3 "$LINKS" --bmad-dir "$B5" >/dev/null 2>&1; rc=$?
check_eq "missing scripts alone is fatal (exit)" "2" "$rc"
python3 "$LINKS" --bmad-dir "$DIR/nope" >/dev/null 2>&1; rc=$?
check_eq "missing dir is fatal (exit)" "1" "$rc"

# The build derives the list instead of carrying a hand list.
has() { grep -qF -- "$1" "${SD}/build-bmad.sh" && echo yes || echo no; }
check_eq "build calls the helper" "yes" "$(has 'bmad-runtime-links.py')"
check_eq "build substitutes the derived list" "yes" "$(has '${RUNTIME_LINKS}')"
check_eq "no hand-written link entry remains" "0" "$(grep -c -- '^    - link: ' "${SD}/build-bmad.sh")"

echo "bmad-runtime-links tests: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
