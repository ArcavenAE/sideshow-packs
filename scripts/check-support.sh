#!/usr/bin/env bash
# check-support.sh — packaging-support pre-flight gate.
#
# Usage: check-support.sh <pack> <version>
#
# Consults registry/<pack>-pack-support.yaml:
#   - version inside a validated bracket  -> exit 0, print applicable wrinkles
#   - version outside every bracket       -> print guidance + LLM runbook
#                                            pointer; exit 2 unless
#                                            ALLOW_UNSUPPORTED=1
#   - no register for pack                -> warn, exit 0 (register coverage
#                                            is opt-in per pack)
#
# Machine/LLM consumers: the register itself (registry/<pack>-pack-support.yaml) is
# the parsable source of truth; this script is the human/CI rendering.

set -euo pipefail

PACK="${1:?usage: check-support.sh <pack> <version>}"
VERSION="${2:?usage: check-support.sh <pack> <version>}"
ALLOW_UNSUPPORTED="${ALLOW_UNSUPPORTED:-0}"

command -v yq >/dev/null || { echo "error: yq required"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG="${SCRIPT_DIR}/../registry/${PACK}-pack-support.yaml"

if [[ ! -f "${REG}" ]]; then
    echo "[check-support] WARN: no pack-support register for pack '${PACK}' (${REG})"
    echo "[check-support] proceeding without support guarantees; consider authoring one (see registry/bmad-pack-support.yaml as template)"
    exit 0
fi

# version_le A B: A <= B in semver-ish sort -V order
version_le() { [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }

in_bracket() { # version min max -> 0/1
    version_le "$2" "$1" && version_le "$1" "$3"
}

# Wrinkle applies if introduced_in <= VERSION < resolved_in
# (null introduced_in = always; null resolved_in = still open).
wrinkle_applies() { # introduced resolved
    local intro="$1" resolved="$2"
    if [[ "${intro}" != "null" && -n "${intro}" ]]; then
        version_le "${intro}" "${VERSION}" || return 1
    fi
    if [[ "${resolved}" != "null" && -n "${resolved}" ]]; then
        if version_le "${resolved}" "${VERSION}"; then return 1; fi
    fi
    return 0
}

print_applicable_wrinkles() {
    local n i intro resolved wid sev summary
    n="$(yq '.wrinkles | length' "${REG}")"
    for ((i = 0; i < n; i++)); do
        intro="$(yq ".wrinkles[$i].introduced_in" "${REG}")"
        resolved="$(yq ".wrinkles[$i].resolved_in" "${REG}")"
        if wrinkle_applies "${intro}" "${resolved}"; then
            wid="$(yq ".wrinkles[$i].id" "${REG}")"
            sev="$(yq ".wrinkles[$i].severity" "${REG}")"
            summary="$(yq ".wrinkles[$i].summary" "${REG}" | tr '\n' ' ')"
            echo "[check-support]   wrinkle: ${wid} (${sev}) — ${summary}"
        fi
    done
}

SUPPORTED=0
BRACKETS="$(yq '.validated | length' "${REG}")"
for ((b = 0; b < BRACKETS; b++)); do
    MIN="$(yq ".validated[$b].min" "${REG}")"
    MAX="$(yq ".validated[$b].max" "${REG}")"
    if in_bracket "${VERSION}" "${MIN}" "${MAX}"; then
        SUPPORTED=1
        break
    fi
done

if [[ "${SUPPORTED}" == "1" ]]; then
    echo "[check-support] ${PACK}@${VERSION}: SUPPORTED (validated bracket ${MIN}..${MAX})"
    echo "[check-support] applicable wrinkles at this version:"
    print_applicable_wrinkles
    exit 0
fi

RUNBOOK="$(yq '.llm_runbook' "${REG}")"
echo "[check-support] =============================================================="
echo "[check-support] ${PACK}@${VERSION}: UNSUPPORTED — outside every validated bracket"
echo "[check-support]"
echo "[check-support] Validated brackets:"
for ((b = 0; b < BRACKETS; b++)); do
    echo "[check-support]   $(yq ".validated[$b].min" "${REG}") .. $(yq ".validated[$b].max" "${REG}") (validated $(yq ".validated[$b].validated_at" "${REG}"))"
done
echo "[check-support]"
echo "[check-support] Known wrinkles that would apply at ${VERSION} (open brackets):"
print_applicable_wrinkles
echo "[check-support]"
echo "[check-support] What this means: the pipeline's assumptions (see"
echo "[check-support] pipeline_assumptions in ${REG#"${SCRIPT_DIR}"/../})"
echo "[check-support] have NOT been verified against ${PACK}@${VERSION}. Upstream"
echo "[check-support] has previously shifted installer argv, manifest formats,"
echo "[check-support] module resolution, and engine floors between versions."
echo "[check-support]"
echo "[check-support] Supported path: follow the LLM revalidation runbook —"
echo "[check-support]   ${RUNBOOK}"
echo "[check-support] — then extend the validated bracket with evidence."
echo "[check-support]"
if [[ "${ALLOW_UNSUPPORTED}" == "1" ]]; then
    echo "[check-support] ALLOW_UNSUPPORTED=1 set: proceeding BEST-EFFORT. This"
    echo "[check-support] artifact must not be published as validated (runbook step 5)."
    echo "[check-support] =============================================================="
    exit 0
fi
echo "[check-support] To proceed best-effort anyway: ALLOW_UNSUPPORTED=1 (workflow"
echo "[check-support] input allow_unsupported=true). Refusing by default."
echo "[check-support] =============================================================="
exit 2
