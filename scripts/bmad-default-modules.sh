#!/usr/bin/env bash
# Print the bmad module composition the pack register declares, one
# comma-separated line (default_modules in registry/bmad-pack-support.yaml).
# build-bmad.sh uses it when BMAD_MODULES is unset or empty, so a local build
# ships the same composition as CI (build-pack.yml reads the same key) and the
# published pack. Fails if the register is missing or declares none.
#
#   scripts/bmad-default-modules.sh [register-file]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG="${1:-${SCRIPT_DIR}/../registry/bmad-pack-support.yaml}"

[[ -f "${REG}" ]] || { echo "error: pack register not found: ${REG}" >&2; exit 1; }
command -v yq >/dev/null || { echo "error: yq required (https://github.com/mikefarah/yq)" >&2; exit 1; }

mods="$(yq -r '.default_modules // ""' "${REG}")"
if [[ -z "${mods}" || "${mods}" == "null" ]]; then
    echo "error: ${REG} declares no default_modules" >&2
    exit 2
fi
echo "${mods}"
