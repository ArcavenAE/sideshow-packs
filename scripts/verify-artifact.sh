#!/usr/bin/env bash
# verify-artifact.sh — runbook Step 3, as a command instead of a checklist.
#
# Usage: verify-artifact.sh <artifact-dir> [<previous-file-manifest.csv>]
#
# Checks a built pack artifact before its bracket is extended or it is
# published. Exits non-zero on any failed assertion.
#
# The composition assertion is the one that matters most. The 2026-08-01
# -r2 batch was published with two modules missing and every other signal
# reported healthy, because provenance declares what an artifact contains
# and never compares it against what it replaces (aae-orc finding-147).
# Passing the previous release's file-manifest.csv turns the census from a
# number nobody reads into a diff that fails.

set -euo pipefail

DIR="${1:?usage: verify-artifact.sh <artifact-dir> [<previous-file-manifest.csv>]}"
PREV_MANIFEST="${2:-}"

command -v yq >/dev/null || { echo "error: yq required"; exit 1; }

META="${DIR}/install.meta.yaml"
MANIFEST="${DIR}/file-manifest.csv"
fail=0

note() { printf '  %-9s %s\n' "$1" "$2"; }
bad()  { note "FAIL" "$1"; fail=1; }
ok()   { note "ok" "$1"; }

echo "== artifact: ${DIR}"

[[ -f "${META}" ]]     || { bad "install.meta.yaml missing"; exit 1; }
[[ -f "${MANIFEST}" ]] || { bad "file-manifest.csv missing"; exit 1; }

PACK="$(yq -r '.pack.name' "${META}")"
VERSION="$(yq -r '.pack.version' "${META}")"
REVISION="$(yq -r '.pack.packaging_revision // ""' "${META}")"
echo "== ${PACK} ${VERSION}${REVISION:+ ${REVISION}}"

# ---- 1. composition, against the register that declares it ----------------
REG="$(dirname "$0")/../registry/${PACK}-pack-support.yaml"
if [[ -f "${REG}" ]]; then
    DECLARED="$(yq -r '.default_modules // ""' "${REG}")"
    if [[ -n "${DECLARED}" ]]; then
        # core is always present and never listed in default_modules.
        EXPECTED="core,${DECLARED}"
        ACTUAL="$(yq -r '[.composition.modules_from_manifest[].name] | join(",")' "${META}")"
        exp_sorted="$(tr ',' '\n' <<<"${EXPECTED}" | sort | paste -sd, -)"
        act_sorted="$(tr ',' '\n' <<<"${ACTUAL}"   | sort | paste -sd, -)"
        if [[ "${exp_sorted}" == "${act_sorted}" ]]; then
            ok "composition matches register: ${ACTUAL}"
        else
            bad "composition drift"
            note "" "register declares: ${exp_sorted}"
            note "" "artifact contains: ${act_sorted}"
        fi
    else
        note "skip" "register declares no default_modules (direct-tree pack)"
    fi
else
    note "skip" "no register for ${PACK}"
fi

# ---- 2. pins resolved to versions AND shas -------------------------------
UNPINNED="$(yq -r '[.composition.modules_from_manifest[] | select(.source == "external") | select((.sha // "") == "")] | length' "${META}")"
if [[ "${UNPINNED}" == "0" ]]; then
    ok "every module carries a resolved sha"
else
    # Not fatal: pre-6.4.0 bmad has no pin mechanism at all (no-pin-mechanism
    # wrinkle), and the policy field records that honestly.
    POLICY="$(yq -r '.pack.pin_policy // "unset"' "${META}")"
    note "warn" "${UNPINNED} module(s) without a sha; pin_policy=${POLICY}"
fi

# ---- 3. file census, against the previous release ------------------------
COUNT="$(( $(wc -l < "${MANIFEST}") - 1 ))"   # minus header
ok "file-manifest lists ${COUNT} files"

if [[ -n "${PREV_MANIFEST}" && -f "${PREV_MANIFEST}" ]]; then
    PREV_COUNT="$(( $(wc -l < "${PREV_MANIFEST}") - 1 ))"
    DELTA=$(( COUNT - PREV_COUNT ))
    PCT=$(( PREV_COUNT > 0 ? (DELTA * 100 / PREV_COUNT) : 0 ))
    note "info" "previous: ${PREV_COUNT} files, delta: ${DELTA} (${PCT}%)"
    # A re-issue or point release that moves the census by more than a third
    # is either a structural change or a composition change. Both need a
    # human to say which before anything is published.
    if (( PCT > 33 || PCT < -33 )); then
        bad "census moved ${PCT}% — structural or composition change; explain before publishing"
    else
        ok "census delta within band"
    fi
else
    note "info" "no previous manifest supplied; census delta unchecked"
fi

# ---- 4. pack.yaml present and coherent inside the artifact ---------------
TARBALL="$(find "${DIR}" -maxdepth 1 -name '*.tar.gz' | head -1)"
if [[ -n "${TARBALL}" ]]; then
    PY="$(tar -tzf "${TARBALL}" | grep -m1 '/pack\.yaml$' || true)"
    if [[ -n "${PY}" ]]; then
        PV="$(tar -xzOf "${TARBALL}" "${PY}" | yq -r '.version')"
        [[ "${PV}" == "${VERSION}" ]] \
            && ok "pack.yaml version matches (${PV})" \
            || bad "pack.yaml says ${PV}, install.meta says ${VERSION}"
    else
        bad "no pack.yaml inside the tarball"
    fi
else
    note "info" "no tarball in ${DIR} (unsigned test build keeps it as a workflow artifact)"
fi

echo
if (( fail )); then
    echo "RESULT: FAILED — do not extend the bracket or publish"
    exit 1
fi
echo "RESULT: passed"
