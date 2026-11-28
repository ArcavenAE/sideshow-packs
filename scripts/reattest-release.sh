#!/usr/bin/env bash
# Re-attest one published release: add a new-format attestation bundle
# (<tarball>.attest.v2.bundle, with a dsseEnvelope) next to the old one, so
# sideshow install can read the provenance from it (aae-orc-hti53).
#
#   TAG=bmad-v6.12.4-r3 GH_TOKEN=... bash scripts/reattest-release.sh
#
# Nothing is replaced, deleted or re-tagged. The new asset is uploaded without
# --clobber, so an asset of that name already on the release stops the run.
# Every check below runs before anything is signed, except the last two, which
# run before anything is uploaded. Any failure stops the run with a report in
# the step summary and a non-zero status; there is no retry and no fallback.
#
# Env: TAG (required), GITHUB_REPOSITORY (owner/repo), GH_TOKEN, and optionally
# COSIGN_OLD (cosign used to verify the old bundles, default cosign) and
# COSIGN_NEW (cosign used to sign and verify the new one, default cosign).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${TAG:?TAG is required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
COSIGN_OLD="${COSIGN_OLD:-cosign}"
COSIGN_NEW="${COSIGN_NEW:-cosign}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

ISSUER="https://token.actions.githubusercontent.com"
# The same pins sideshow install applies: the tarball and old attestation were
# signed by build-pack.yml at a pack-version tag or at main; the new one by this
# job's workflow at main.
OLD_ID='^https://github\.com/ArcavenAE/sideshow-packs/\.github/workflows/build-pack\.yml@refs/(heads/main|tags/[a-z0-9][a-z0-9-]*-v[0-9][^/]*)$'
NEW_ID='^https://github\.com/ArcavenAE/sideshow-packs/\.github/workflows/reattest-release\.yml@refs/heads/main$'
TYPES=("https://arcaven.com/sideshow/install-meta" "https://arcaven.com/sideshow/install-meta/v0.1.0")

stop() { # check-name detail
    {
        echo "### Re-attest of ${TAG} stopped"
        echo
        echo "- check that failed: $1"
        echo "- detail: $2"
        echo "- signed: nothing is signed before the checks pass; uploaded: nothing"
    } >> "${SUMMARY}"
    echo "STOP ${TAG}: $1: $2" >&2
    exit 1
}

if [[ ! "${TAG}" =~ ^[a-z0-9][a-z0-9-]*-v[0-9][A-Za-z0-9._-]*$ ]]; then
    stop "tag shape" "${TAG} is not a pack-version tag"
fi

WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/reattest.XXXXXX")"
cd "${WORK}"

draft="$(gh release view "${TAG}" --repo "${REPO}" --json isDraft -q .isDraft)" || stop "release lookup" "no release ${TAG}"
[[ "${draft}" == "false" ]] || stop "release state" "${TAG} is a draft"

gh release download "${TAG}" --repo "${REPO}" --dir . \
    --pattern '*.tar.gz' --pattern '*.tar.gz.bundle' --pattern '*.tar.gz.attest.bundle' \
    --pattern 'install.meta.json' || stop "download" "gh release download failed"

shopt -s nullglob
tarballs=(*.tar.gz)
[[ "${#tarballs[@]}" -eq 1 ]] || stop "download" "expected one tarball, found ${#tarballs[@]}"
TARBALL="${tarballs[0]}"
for f in "${TARBALL}.bundle" "${TARBALL}.attest.bundle" install.meta.json; do
    [[ -f "${f}" ]] || stop "download" "${f} is not on the release"
done
NEW="${TARBALL}.attest.v2.bundle"
if gh release view "${TAG}" --repo "${REPO}" --json assets -q '.assets[].name' | grep -Fxq "${NEW}"; then
    stop "existing asset" "${NEW} is already on the release; nothing is replaced"
fi

SHA="$(shasum -a 256 "${TARBALL}" | cut -d' ' -f1)"

# 1. The old signature and the old attestation verify against this tarball.
"${COSIGN_OLD}" verify-blob --bundle "${TARBALL}.bundle" \
    --certificate-identity-regexp "${OLD_ID}" --certificate-oidc-issuer "${ISSUER}" \
    "${TARBALL}" || stop "old signature" "cosign verify-blob refused ${TARBALL}.bundle"

verified_types=()
for t in "${TYPES[@]}"; do
    if "${COSIGN_OLD}" verify-blob-attestation --bundle "${TARBALL}.attest.bundle" --type "${t}" \
        --certificate-identity-regexp "${OLD_ID}" --certificate-oidc-issuer "${ISSUER}" \
        "${TARBALL}" > /dev/null 2>&1; then
        verified_types+=("${t}")
    fi
done
[[ "${#verified_types[@]}" -gt 0 ]] || stop "old attestation" "cosign verify-blob-attestation refused ${TARBALL}.attest.bundle under both predicate types"

# 2. The predicate to re-sign is the one that was signed: the rebuilt statement
#    hashes to the payload hash the old bundle's Rekor entry records, and the
#    tarball digest is the one install.meta.json names.
python3 -I - "${TARBALL}.attest.bundle" rekor-only.json <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))
json.dump({"rekorBundle": b["rekorBundle"]}, open(sys.argv[2], "w"))
PY
out="$(python3 -I "${HERE}/reattest-check.py" statement --meta install.meta.json \
    --bundle rekor-only.json --name "${TARBALL}" --sha256 "${SHA}")" || stop "payload hash" "${out}"
matched="$(sed -n 's/^OK predicate-type=\([^ ]*\) .*/\1/p' <<< "${out}")"
[[ -n "${matched}" ]] || stop "payload hash" "no predicate type in: ${out}"
ok=0
for t in "${verified_types[@]}"; do [[ "${t}" == "${matched}" ]] && ok=1; done
[[ "${ok}" -eq 1 ]] || stop "predicate type" "the rebuilt statement matches under ${matched}, which the old attestation did not verify under"

# 3. Sign, then check what was signed before it is uploaded.
"${COSIGN_NEW}" attest-blob --yes --predicate install.meta.json --type "${matched}" \
    --bundle "${NEW}" "${TARBALL}" || stop "attest-blob" "cosign attest-blob failed"
out="$(python3 -I "${HERE}/reattest-check.py" new --bundle "${NEW}" --meta install.meta.json --sha256 "${SHA}")" \
    || stop "new bundle content" "${out}"
"${COSIGN_NEW}" verify-blob-attestation --bundle "${NEW}" --type "${matched}" \
    --certificate-identity-regexp "${NEW_ID}" --certificate-oidc-issuer "${ISSUER}" \
    "${TARBALL}" || stop "new bundle signature" "cosign verify-blob-attestation refused ${NEW}"

# 4. Upload as a new asset. No --clobber: an existing name is an error.
gh release upload "${TAG}" "${NEW}" --repo "${REPO}" || stop "upload" "gh release upload failed for ${NEW}"

{
    echo "### Re-attested ${TAG}"
    echo
    echo "- asset added: \`${NEW}\`"
    echo "- tarball sha256: \`${SHA}\`"
    echo "- predicate type: \`${matched}\`"
    echo "- payload hash matched the Rekor entry of the old bundle"
} >> "${SUMMARY}"
echo "re-attested ${TAG}: ${NEW}"
