#!/usr/bin/env bash
# cap-pin.sh: hold an as-of module tag to the installer's registry pin.
#
# Usage: cap-pin.sh <module-code> <as-of-tag> <bmad-modules.yaml>
#
# Prints the tag build-bmad.sh should pass as --pin. From bmad-method v6.12.2
# the installer's bmad-modules.yaml can carry `pin: <tag>` for a module whose
# newer releases target a later installer. `--pin` outranks that registry pin,
# so an as-of tag above it would select the release the registry held back.
# The result is the lower of the as-of tag and the registry pin. It is the
# as-of tag unchanged when the file is missing or empty, the module is not
# listed, or the module has no pin. A pin that is not a plain vX.Y.Z tag is an
# error.
set -euo pipefail

code="${1:?usage: cap-pin.sh <module-code> <as-of-tag> <bmad-modules.yaml>}"
asof="${2:?usage: cap-pin.sh <module-code> <as-of-tag> <bmad-modules.yaml>}"
reg="${3:?usage: cap-pin.sh <module-code> <as-of-tag> <bmad-modules.yaml>}"

if [[ ! -s "${reg}" ]]; then
    echo "${asof}"
    exit 0
fi

# A yq failure (malformed file) ends the script through set -e; it must not
# read as "no pin".
pin="$(CODE="${code}" yq -r '[.modules[] | select(.code == strenv(CODE)) | .pin // ""] | .[0] // ""' "${reg}")"
if [[ -z "${pin}" || "${pin}" == "null" ]]; then
    echo "${asof}"
    exit 0
fi

# sort -V cannot order a branch name or a pre-release tag against a release, and
# the as-of tag has already passed the same pure-semver filter in build-bmad.sh.
# Stop on any other registry pin rather than compare it wrongly.
if ! [[ "${pin}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "cap-pin: registry pin '${pin}' for ${code} is not a plain release tag (vX.Y.Z); refusing to compare it" >&2
    exit 1
fi

lower="$(printf '%s\n%s\n' "${asof#v}" "${pin#v}" | sort -V | head -1)"
if [[ "${lower}" == "${asof#v}" ]]; then
    echo "${asof}"
else
    echo "${pin}"
fi
