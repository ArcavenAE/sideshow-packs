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
# file-manifest.csv carries no header row: the build writes one
# `sha256,size,relpath` line per file and nothing else. The `- 1` that
# used to sit here undercounted every pack by exactly one, and the wrong
# number reached two release bodies and two register evidence lines
# before anyone compared it against install.meta's own file_count.
COUNT="$(wc -l < "${MANIFEST}" | tr -d ' ')"
ok "file-manifest lists ${COUNT} files"

if [[ -n "${PREV_MANIFEST}" && -f "${PREV_MANIFEST}" ]]; then
    PREV_COUNT="$(wc -l < "${PREV_MANIFEST}" | tr -d ' ')"
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

        # Composition disclosure (aae-orc-soh8q). When install.meta records a
        # pin policy, the pack itself must say so, so an installed pack can
        # tell its user it is pinned and as of when. The block must agree
        # with install.meta, not merely exist.
        META_POLICY="$(yq -r '.composition.pin_policy // ""' "${META}")"
        if [[ -n "${META_POLICY}" ]]; then
            PYC="$(tar -xzOf "${TARBALL}" "${PY}")"
            P_POLICY="$(yq -r '.composition.pin_policy // ""' <<< "${PYC}")"
            if [[ -z "${P_POLICY}" ]]; then
                bad "pack.yaml has no composition block; install.meta records pin_policy ${META_POLICY}"
            else
                [[ "${P_POLICY}" == "${META_POLICY}" ]] \
                    && ok "pack.yaml pin_policy matches (${P_POLICY})" \
                    || bad "pack.yaml pin_policy ${P_POLICY}, install.meta says ${META_POLICY}"
                M_ASOF="$(yq -r '.composition.as_of_date // ""' "${META}")"
                P_ASOF="$(yq -r '.composition.as_of_date // ""' <<< "${PYC}")"
                [[ "${P_ASOF}" == "${M_ASOF}" ]] \
                    && ok "pack.yaml as_of_date matches (${P_ASOF:-none})" \
                    || bad "pack.yaml as_of_date ${P_ASOF:-none}, install.meta says ${M_ASOF:-none}"
                M_EXT="$(yq -r '.composition.modules_from_manifest[] | select(.source == "external") | .name + "=" + .version' "${META}" | sort)"
                P_EXT="$(yq -r '.composition.external_modules[] | .name + "=" + .version' <<< "${PYC}" | sort)"
                [[ "${P_EXT}" == "${M_EXT}" ]] \
                    && ok "pack.yaml external modules match install.meta ($(wc -l <<< "${M_EXT}" | tr -d ' '))" \
                    || bad "pack.yaml external modules [$(tr '\n' ' ' <<< "${P_EXT}")] differ from install.meta [$(tr '\n' ' ' <<< "${M_EXT}")]"
                PSV="$(yq -r '.schema_version // ""' <<< "${PYC}")"
                [[ "${PSV}" == "0.2.0" ]] \
                    && ok "pack.yaml schema_version ${PSV}" \
                    || bad "pack.yaml carries a composition block under schema_version ${PSV:-none}; expected 0.2.0"
            fi
        fi
    else
        bad "no pack.yaml inside the tarball"
    fi
else
    note "info" "no tarball in ${DIR} (unsigned test build keeps it as a workflow artifact)"
fi

# ---- 5. file-manifest.csv travels inside the tarball ----------------------
# The sibling asset is gone from the machine once a pack is extracted, so
# nothing could re-verify an installed store version (aae-orc-xorml). The
# in-tarball copy is covered by the tarball's signature. It must be the
# same bytes as the sibling, must not list itself, and must list every
# other regular file the tarball carries.
if [[ -n "${TARBALL}" ]]; then
    IN_MANIFEST="$(tar -tzf "${TARBALL}" | grep -m1 -E '^[^/]+/file-manifest\.csv$' || true)"
    if [[ -z "${IN_MANIFEST}" ]]; then
        bad "tarball carries no file-manifest.csv; installed content cannot be re-verified"
    else
        # diff reads both inputs to the end; cmp -s stops at the first
        # difference and tar then reports a broken pipe.
        diff -q <(tar -xzOf "${TARBALL}" "${IN_MANIFEST}") "${MANIFEST}" >/dev/null \
            && ok "in-tarball file-manifest.csv matches the release asset" \
            || bad "in-tarball file-manifest.csv differs from the release asset"
        if grep -q -E ',file-manifest\.csv$' "${MANIFEST}"; then
            bad "file-manifest.csv lists itself; its own hash cannot be recorded inside it"
        fi
        TAR_FILES="$(tar -tvzf "${TARBALL}" | grep -c '^-' || true)"
        [[ "${TAR_FILES}" == "$(( COUNT + 1 ))" ]] \
            && ok "tarball carries ${TAR_FILES} files: the ${COUNT} listed plus the manifest" \
            || bad "tarball carries ${TAR_FILES} files; expected ${COUNT} listed plus the manifest"
    fi
fi

# ---- 6. exec-manifest.txt travels inside the tarball ----------------------
# Same reason as file-manifest.csv, and sideshow reads it at install time to
# check exec bits (aae-orc-6la0l). Without an in-pack copy that check finds
# nothing in an extracted pack and skips. The copy must be the same bytes as
# the sibling asset, must have a row in file-manifest.csv (it is written
# before the hash pass, unlike file-manifest.csv itself), and must list
# exactly the files that carry an exec bit in the tarball.
if [[ -n "${TARBALL}" ]]; then
    IN_EXEC="$(tar -tzf "${TARBALL}" | grep -m1 -E '^[^/]+/exec-manifest\.txt$' || true)"
    if [[ -z "${IN_EXEC}" ]]; then
        bad "tarball carries no exec-manifest.txt; install-time exec-bit verification would silently skip"
    else
        if [[ -f "${DIR}/exec-manifest.txt" ]]; then
            diff -q <(tar -xzOf "${TARBALL}" "${IN_EXEC}") "${DIR}/exec-manifest.txt" >/dev/null \
                && ok "in-tarball exec-manifest.txt matches the release asset" \
                || bad "in-tarball exec-manifest.txt differs from the release asset"
        else
            note "info" "no exec-manifest.txt release asset to compare against"
        fi
        if grep -q -E ',exec-manifest\.txt$' "${MANIFEST}"; then
            ok "exec-manifest.txt has a row in file-manifest.csv"
        else
            bad "file-manifest.csv has no row for exec-manifest.txt; it must be written before the hash pass"
        fi
        EXTRACT="$(mktemp -d)"
        tar -xzf "${TARBALL}" -C "${EXTRACT}"
        ROOT="${EXTRACT}/${IN_EXEC%%/*}"
        ACTUAL_EXEC="$(cd "${ROOT}" && find . -type f -perm -0100 | sed 's|^\./||' | LC_ALL=C sort)"
        LISTED_EXEC="$(grep -v '^[[:space:]]*$' "${ROOT}/exec-manifest.txt" | LC_ALL=C sort || true)"
        rm -rf "${EXTRACT}"
        if [[ "${ACTUAL_EXEC}" == "${LISTED_EXEC}" ]]; then
            ok "exec-manifest.txt lists exactly the executable files ($(grep -c . <<<"${ACTUAL_EXEC}" || true))"
        else
            bad "exec-manifest.txt does not match the executable files in the tarball"
            diff <(echo "${LISTED_EXEC}") <(echo "${ACTUAL_EXEC}") | head -6 | sed 's/^/             /' || true
        fi
    fi
fi

echo
if (( fail )); then
    echo "RESULT: FAILED — do not extend the bracket or publish"
    exit 1
fi
echo "RESULT: passed"
