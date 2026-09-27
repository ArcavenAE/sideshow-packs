#!/usr/bin/env bash
# Scenario tests for scripts/pin-lag.sh. Self-contained: tags come
# through the PIN_LAG_TAGS_DIR seam, no network. Run from anywhere:
#
#   bash scripts/test-pin-lag.sh
#
# CI runs this via .github/workflows/intake-tests.yml.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pin-lag.sh"
DIR="$(mktemp -d -t pin-lag-test-XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

pass=0
fail=0
check() { # name expected-substring output
    if grep -qF -- "$2" <<< "$3"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1: expected to find '$2' in:"
        printf '    %s\n' "$3"
    fi
}
check_eq() { # name expected actual
    if [[ "$2" == "$3" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1: expected '$2', got '$3'"
    fi
}
check_absent() { # name unexpected-substring output
    if grep -qF -- "$2" <<< "$3"; then
        fail=$((fail + 1))
        echo "FAIL: $1: did not expect '$2' in:"
        printf '    %s\n' "$3"
    else
        pass=$((pass + 1))
    fi
}

cat > "$DIR/meta.yaml" <<'EOF'
schema_version: 0.1.2
pack:
  name: bmad
  version: 6.12.0
composition:
  modules_from_manifest:
    - name: core
      version: 6.12.0
      source: built-in
      repoUrl: null
    - name: cis
      version: v0.3.2
      source: external
      repoUrl: https://example.invalid/cis
    - name: tea
      version: v1.24.0
      source: external
      repoUrl: https://example.invalid/tea
    - name: wds
      version: v0.4.3
      source: external
      repoUrl: https://example.invalid/wds
  pin_policy: as-of-release-date
  as_of_date: "2026-09-04T02:31:21.267Z"
EOF

mkdir -p "$DIR/tags"
# cis: pin is newest; an older tag and a non-semver tag must not count.
printf '%s\n' v0.3.1 v0.3.2 web-bundles-v9.0.0 > "$DIR/tags/cis.txt"
# tea: four newer tags; v1.9.0 sorts below v1.24.0 under -V, a prerelease
# is filtered, and v1.100.0 checks numeric (not lexical) ordering.
printf '%s\n' v1.9.0 v1.24.0 v1.25.0 v1.25.1 v1.26.0-rc.1 v1.26.0 v1.100.0 > "$DIR/tags/tea.txt"
# wds: no tags file at all, so the lag is unknown.

out="$(PIN_LAG_TAGS_DIR="$DIR/tags" bash "$SCRIPT" "$DIR/meta.yaml")"
rc=$?
check_eq "exit is 0 despite lag" "0" "$rc"
check "header names policy and date" "pin policy as-of-release-date, as of 2026-09-04T02:31:21.267Z" "$out"
check "current module" "cis v0.3.2: current" "$out"
check "lagging module counted and newest named" "tea v1.24.0: 4 newer upstream, newest v1.100.0 (v1.25.0 v1.25.1 v1.26.0 v1.100.0)" "$out"
check_absent "prerelease filtered" "rc.1" "$out"
check_absent "older tag not counted" "v1.9.0" "$out"
check_absent "built-in module skipped" "core" "$out"
check "missing tags reported, not fatal" "wds v0.4.3: could not list upstream tags" "$out"
check "summary counts externals" "1 of 3 external modules trail upstream" "$out"
check "lag plus unknown names both" "lag unknown for 1 of 3 external modules" "$out"

# All current: the all-clear summary.
printf '%s\n' v1.24.0 > "$DIR/tags/tea.txt"
printf '%s\n' v0.4.3 > "$DIR/tags/wds.txt"
out="$(PIN_LAG_TAGS_DIR="$DIR/tags" bash "$SCRIPT" "$DIR/meta.yaml")"
check "all current summary" "every external module is at its newest upstream tag" "$out"

# Unknown lag with nothing lagging: must say unknown, never current.
rm -f "$DIR/tags/wds.txt"
out="$(PIN_LAG_TAGS_DIR="$DIR/tags" bash "$SCRIPT" "$DIR/meta.yaml")"
check "unknown named in summary" "lag unknown for 1 of 3 external modules" "$out"
check_absent "unknown is not all-clear" "every external module is at its newest" "$out"
check_absent "unknown is not lagging" "trail upstream" "$out"

# Network unreachable: no seam, so the real git ls-remote path runs
# against a closed local port and fails. Every module is unknown.
sed 's#https://example.invalid/#https://127.0.0.1:9/#' "$DIR/meta.yaml" > "$DIR/meta-offline.yaml"
out="$(GIT_TERMINAL_PROMPT=0 bash "$SCRIPT" "$DIR/meta-offline.yaml")"
rc=$?
check_eq "offline still exits 0" "0" "$rc"
check "offline: every module unknown" "lag unknown for 3 of 3 external modules" "$out"
check_absent "offline is not all-clear" "every external module is at its newest" "$out"

# Usage errors are the only nonzero exits.
bash "$SCRIPT" "$DIR/nope.yaml" >/dev/null 2>&1
check_eq "missing file exits 1" "1" "$?"
echo 'foo: bar' > "$DIR/bad.yaml"
bash "$SCRIPT" "$DIR/bad.yaml" >/dev/null 2>&1
check_eq "meta without pack exits 1" "1" "$?"

echo "pin-lag: ${pass} passed, ${fail} failed"
((fail == 0))
