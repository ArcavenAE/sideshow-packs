#!/usr/bin/env bash
# read-registry.sh: copy bmad-modules.yaml out of a bare, blob-less clone.
#
# Usage: read-registry.sh <bare-repo-dir> <out-file>
#
# Writes the file at HEAD to <out-file>. When HEAD has no bmad-modules.yaml
# (a release before the installer had one) it writes an empty file and exits 0,
# which cap-pin.sh reads as "no cap". Any other failure, such as a blob that
# cannot be fetched from a --filter=blob:none clone, exits non-zero so the
# caller stops instead of building without the cap.
set -euo pipefail

repo="${1:?usage: read-registry.sh <bare-repo-dir> <out-file>}"
out="${2:?usage: read-registry.sh <bare-repo-dir> <out-file>}"

# ls-tree reads trees only, which a blob-less clone already holds, so it
# separates "path absent" from "blob not fetched".
listing="$(git -C "${repo}" ls-tree HEAD -- bmad-modules.yaml)"
if [[ -z "${listing}" ]]; then
    : > "${out}"
    exit 0
fi

git -C "${repo}" show "HEAD:bmad-modules.yaml" > "${out}"
[[ -s "${out}" ]] || { echo "read-registry: bmad-modules.yaml is empty at HEAD" >&2; exit 1; }
