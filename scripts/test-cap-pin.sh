#!/usr/bin/env bash
# Tests for scripts/cap-pin.sh and its wiring into build-bmad.sh. No network,
# no npm: the installer registry comes from a fixture, a copy of
# bmad-modules.yaml at bmad-method v6.12.4. Run from anywhere:
#
#   bash scripts/test-cap-pin.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP="${HERE}/cap-pin.sh"
FIX="${HERE}/fixtures/bmad-modules-6.12.4.yaml"
DIR="$(mktemp -d -t cap-pin-test-XXXXXX)"
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

run() { bash "${CAP}" "$@" 2>/dev/null; }

# The failing build: as-of resolution for 2026-10-14 chose tea v3.0.2.
check_eq "tea as-of v3.0.2 is held to the registry pin" "v1.27.2" "$(run tea v3.0.2 "${FIX}")"
check_eq "cis at the registry pin stays" "v0.3.2" "$(run cis v0.3.2 "${FIX}")"
check_eq "cis above the registry pin is held" "v0.3.2" "$(run cis v0.4.0 "${FIX}")"
check_eq "tea below the registry pin keeps the as-of tag" "v1.20.0" "$(run tea v1.20.0 "${FIX}")"
check_eq "tea without a v prefix is compared by version" "v1.27.2" "$(run tea 3.0.2 "${FIX}")"
check_eq "gds has no registry pin: as-of tag stays" "v0.7.2" "$(run gds v0.7.2 "${FIX}")"
check_eq "bmb has no registry pin: as-of tag stays" "v2.2.2" "$(run bmb v2.2.2 "${FIX}")"
check_eq "wds has no registry pin: as-of tag stays" "v0.4.3" "$(run wds v0.4.3 "${FIX}")"
check_eq "a code the registry does not list keeps the as-of tag" "v9.9.9" "$(run nosuch v9.9.9 "${FIX}")"
check_eq "a missing registry file keeps the as-of tag" "v3.0.2" "$(run tea v3.0.2 "${DIR}/absent.yaml")"
: > "${DIR}/empty.yaml"
check_eq "an empty registry file keeps the as-of tag" "v3.0.2" "$(run tea v3.0.2 "${DIR}/empty.yaml")"

# The build must call it for the as-of path.
if grep -qF 'cap-pin.sh' "${HERE}/build-bmad.sh"; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL: build-bmad.sh does not call cap-pin.sh"
fi

echo "cap-pin: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
