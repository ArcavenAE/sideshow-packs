#!/usr/bin/env bash
# Scenario tests for scripts/bmad-default-modules.sh and its use in
# build-bmad.sh. Self-contained, no network. Run from anywhere:
#
#   bash scripts/test-bmad-default-modules.sh
#
# CI runs this via .github/workflows/intake-tests.yml.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SD}/bmad-default-modules.sh"
REAL="${SD}/../registry/bmad-pack-support.yaml"
DIR="$(mktemp -d -t bmad-defmods-test-XXXXXX)"
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

printf 'default_modules: bmm,cis,gds,tea,bmb,wds\n' > "$DIR/ok.yaml"
check_eq "reads default_modules" "bmm,cis,gds,tea,bmb,wds" "$(bash "$HELPER" "$DIR/ok.yaml")"

# The helper agrees with the real register, which is what CI reads too.
check_eq "matches the real register" "$(yq -r '.default_modules' "$REAL")" "$(bash "$HELPER")"

bash "$HELPER" "$DIR/missing.yaml" >/dev/null 2>&1; check_eq "missing register is fatal" "1" "$?"
printf 'other: x\n' > "$DIR/nokey.yaml"
bash "$HELPER" "$DIR/nokey.yaml" >/dev/null 2>&1; check_eq "absent key is fatal" "2" "$?"
printf 'default_modules: ""\n' > "$DIR/empty.yaml"
bash "$HELPER" "$DIR/empty.yaml" >/dev/null 2>&1; check_eq "empty key is fatal" "2" "$?"

# The build no longer carries its own module list, and uses the helper when
# BMAD_MODULES is unset or empty.
B="${SD}/build-bmad.sh"
check_eq "no literal four-module default" "0" "$(grep -c 'BMAD_MODULES:-bmm' "$B")"
check_eq "default is empty" "1" "$(grep -c '^BMAD_MODULES="${BMAD_MODULES:-}"$' "$B")"
check_eq "build calls the helper" "1" "$(grep -c 'bmad-default-modules.sh' "$B")"
check_eq "build tests for an empty value" "1" "$(grep -c 'if \[\[ -z "${BMAD_MODULES}" \]\]' "$B")"

echo "bmad-default-modules tests: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
