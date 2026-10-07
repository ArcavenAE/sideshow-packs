#!/usr/bin/env bash
# write-exec-manifest.sh <pack-stage> <out-file>
#
# Writes the executable census for a staged pack: one pack-root-relative
# path per line, sorted, for every regular file that carries an owner exec
# bit. The list goes to <out-file> (the release asset beside the tarball)
# and a byte-identical copy goes into the stage, so an extracted pack still
# has the census sideshow verifies at install time (aae-orc-6la0l).
#
# Call it after every step that changes content or modes (the neutralizer,
# the census refresh, any chmod) and before the file-manifest hash pass, so
# the list and the hashes describe the same tree and the copy is listed in
# file-manifest.csv like any other file. The copy is mode 0644, so it never
# lists itself.
set -euo pipefail

STAGE="${1:?usage: write-exec-manifest.sh <pack-stage> <out-file>}"
OUT="${2:?usage: write-exec-manifest.sh <pack-stage> <out-file>}"

[[ -d "${STAGE}" ]] || { echo "error: no pack stage at ${STAGE}" >&2; exit 1; }

(
    cd "${STAGE}"
    find . -type f -perm -0100 ! -path './exec-manifest.txt' | sed 's|^\./||' | LC_ALL=C sort
) > "${OUT}"

cp "${OUT}" "${STAGE}/exec-manifest.txt"
chmod 0644 "${STAGE}/exec-manifest.txt"
