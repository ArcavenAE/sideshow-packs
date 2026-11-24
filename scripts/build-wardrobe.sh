#!/usr/bin/env bash
# build-wardrobe.sh — build the wardrobe release artifact (SP1, design
# docs/design/2026-11-19-i626-vendor-packs-as-marvel-teams.md, section 4.6).
#
# wardrobe is ours: acquisition is a git clone at the tag wardrobe-v<version>,
# then wardrobe's own scripts/pack.sh lays out the release folder
# (company.toml with the version, roles/, contents/, scripts/, pack.yaml).
# This script adds the sideshow-packs parts, as build-vsdd-factory.sh does:
# exec-manifest.txt, file-manifest.csv, the tarball, install.meta.yaml and,
# when COSIGN=1, signatures and attestation.
#
# Emits:
#   artifacts/wardrobe-<version>-arcaven.tar.gz
#   artifacts/install.meta.yaml / install.meta.json
#   artifacts/file-manifest.csv
#   artifacts/exec-manifest.txt   (relpaths that must carry exec bits)
#
# Environment:
#   WARDROBE_VERSION  (required) bare version; the tag is wardrobe-v<version>
#   WARDROBE_SRC      (default: https://github.com/ArcavenAE/wardrobe.git)
#                     May be a local clone path for offline runs; a
#                     non-default value is recorded as src_override in
#                     install.meta and the artifact must not publish.
#   EXPECTED_UPSTREAM_SHA (default: empty) when set, the build fails unless
#                     the cloned tag's commit equals it.
#   OUT_DIR           (default: ./artifacts)
#   COSIGN            (default: 0)

set -euo pipefail

CANONICAL_SRC="https://github.com/ArcavenAE/wardrobe.git"
WARDROBE_VERSION="${WARDROBE_VERSION:?usage: WARDROBE_VERSION=<semver> build-wardrobe.sh (tag is wardrobe-v<version>)}"
WARDROBE_SRC="${WARDROBE_SRC:-${CANONICAL_SRC}}"
EXPECTED_UPSTREAM_SHA="${EXPECTED_UPSTREAM_SHA:-}"
OUT_DIR="${OUT_DIR:-$(pwd)/artifacts}"
COSIGN="${COSIGN:-0}"
TAG="wardrobe-v${WARDROBE_VERSION}"

for c in git jq yq; do
    command -v "$c" >/dev/null || { echo "error: $c required"; exit 1; }
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${COSIGN}" == "1" && "${WARDROBE_SRC}" != "${CANONICAL_SRC}" ]]; then
    echo "[build-wardrobe] FATAL: signing build from a non-canonical src"
    exit 1
fi

WORK="$(mktemp -d -t wardrobe-pack-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[build-wardrobe] version=${WARDROBE_VERSION} tag=${TAG}"
echo "[build-wardrobe] src=${WARDROBE_SRC}"
mkdir -p "${OUT_DIR}"

# 1. Acquire: shallow clone at the tag, never a branch head.
if ! git clone --quiet --depth 1 --branch "${TAG}" "${WARDROBE_SRC}" "${WORK}/src" 2>"${WORK}/clone.err"; then
    echo "[build-wardrobe] FATAL: cannot clone tag ${TAG} from ${WARDROBE_SRC}"
    sed 's/^/  /' "${WORK}/clone.err"
    exit 1
fi
TAG_COMMIT="$(git -C "${WORK}/src" rev-parse HEAD)"
echo "[build-wardrobe] tag commit ${TAG_COMMIT}"

if [[ -n "${EXPECTED_UPSTREAM_SHA}" && "${TAG_COMMIT}" != "${EXPECTED_UPSTREAM_SHA}" ]]; then
    echo "[build-wardrobe] FATAL: upstream provenance mismatch: tag commit ${TAG_COMMIT} != expected ${EXPECTED_UPSTREAM_SHA}"
    exit 1
fi

SRC_OVERRIDE="null"
if [[ "${WARDROBE_SRC}" != "${CANONICAL_SRC}" ]]; then
    SRC_OVERRIDE="$(jq -n --arg s "${WARDROBE_SRC}" '$s')"
    echo "[build-wardrobe] WARN: non-canonical src; artifact is prototype-grade and must not publish"
fi

# 2. The tag and the manifest must agree on the version.
PACK_YAML_VERSION="$(yq -r '.version // ""' "${WORK}/src/pack.yaml")"
if [[ "${PACK_YAML_VERSION}" != "${WARDROBE_VERSION}" ]]; then
    echo "[build-wardrobe] FATAL: version mismatch: pack.yaml at ${TAG} says '${PACK_YAML_VERSION}', requested ${WARDROBE_VERSION}"
    exit 1
fi

# 3. Lay out the release folder with wardrobe's own packer.
PACK_STAGE="${WORK}/pack"
bash "${WORK}/src/scripts/pack.sh" "${PACK_STAGE}"
for p in company.toml roles contents scripts pack.yaml; do
    [[ -e "${PACK_STAGE}/${p}" ]] || { echo "[build-wardrobe] FATAL: pack.sh output lacks ${p}"; exit 1; }
done
[[ "$(yq -p toml -o json '.version // ""' "${PACK_STAGE}/company.toml" | tr -d '"')" == "${WARDROBE_VERSION}" ]] \
    || { echo "[build-wardrobe] FATAL: company.toml version is not ${WARDROBE_VERSION}"; exit 1; }

# 4. exec-manifest.txt, after the last content or mode change and before the
#    hash pass, so the stage copy is listed in file-manifest.csv.
bash "${SCRIPT_DIR}/write-exec-manifest.sh" "${PACK_STAGE}" "${OUT_DIR}/exec-manifest.txt"
EXEC_COUNT="$(wc -l < "${OUT_DIR}/exec-manifest.txt" | tr -d ' ')"

hash_file() { if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
size_of() { if [[ "$(uname)" == "Darwin" ]]; then stat -f %z "$1"; else stat -c %s "$1"; fi; }

# 5. file-manifest.csv (sha256,size,relpath), carried inside the pack after
#    the hash pass so it never lists itself.
echo "[build-wardrobe] computing file manifest"
(
    cd "${PACK_STAGE}"
    find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do
        printf '%s,%s,%s\n' "$(hash_file "$f")" "$(size_of "$f")" "${f#./}"
    done
) > "${OUT_DIR}/file-manifest.csv"
FILE_COUNT="$(wc -l < "${OUT_DIR}/file-manifest.csv" | tr -d ' ')"
cp "${OUT_DIR}/file-manifest.csv" "${PACK_STAGE}/file-manifest.csv"

# 6. Tarball (BSD tar -s, GNU tar --transform).
TARBALL="${OUT_DIR}/wardrobe-${WARDROBE_VERSION}-arcaven.tar.gz"
echo "[build-wardrobe] packaging -> ${TARBALL}"
tar -C "${WORK}" -czf "${TARBALL}" -s '/pack/wardrobe-'"${WARDROBE_VERSION}"'/' pack 2>/dev/null \
    || tar -C "${WORK}" --transform "s|^pack|wardrobe-${WARDROBE_VERSION}|" -czf "${TARBALL}" pack
TARBALL_SHA="$(hash_file "${TARBALL}")"
TARBALL_SIZE="$(size_of "${TARBALL}")"
FILE_MANIFEST_SHA="$(hash_file "${OUT_DIR}/file-manifest.csv")"
EXEC_MANIFEST_SHA="$(hash_file "${OUT_DIR}/exec-manifest.txt")"

# 7. install.meta
PRODUCED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
META="${OUT_DIR}/install.meta.yaml"
META_JSON="${OUT_DIR}/install.meta.json"
SIGNING_STATUS="$( [[ "${COSIGN}" == "1" ]] && echo 'signed' || echo 'unsigned-local-build' )"

jq -n \
  --arg version "${WARDROBE_VERSION}" \
  --arg produced_at "${PRODUCED_AT}" \
  --arg repo "${CANONICAL_SRC}" \
  --arg tag "${TAG}" \
  --arg commit "${TAG_COMMIT}" \
  --argjson src_override "${SRC_OVERRIDE}" \
  --argjson file_count "${FILE_COUNT}" \
  --argjson exec_count "${EXEC_COUNT}" \
  --arg tarball "$(basename "${TARBALL}")" \
  --arg tarball_sha256 "${TARBALL_SHA}" \
  --argjson tarball_bytes "${TARBALL_SIZE}" \
  --arg file_manifest_sha256 "${FILE_MANIFEST_SHA}" \
  --arg exec_manifest_sha256 "${EXEC_MANIFEST_SHA}" \
  --arg signing_status "${SIGNING_STATUS}" \
  '{
    schema_version: "0.2.0",
    schema_stability: "draft",
    pack: {
      name: "wardrobe",
      version: $version,
      produced_at: $produced_at,
      produced_by: "sideshow-packs/scripts/build-wardrobe.sh"
    },
    upstream: {
      repo: $repo,
      tag: $tag,
      commit_sha: $commit,
      src_override: $src_override
    },
    acquisition: { method: "direct-tree", release_line: "own" },
    content: { file_count: $file_count, executable_count: $exec_count },
    artifact: {
      tarball: $tarball,
      tarball_sha256: $tarball_sha256,
      tarball_bytes: $tarball_bytes,
      file_count: $file_count,
      file_manifest_sha256: $file_manifest_sha256,
      exec_manifest_sha256: $exec_manifest_sha256
    },
    signing: { status: $signing_status }
  }' > "${META_JSON}"

yq -p json -o yaml "${META_JSON}" > "${META}"
{
    printf '# Frozen direct-tree artifact provenance, wardrobe@%s\n# Produced by sideshow-packs build-wardrobe.sh.\n\n' "${WARDROBE_VERSION}"
    cat "${META}"
} > "${META}.tmp" && mv "${META}.tmp" "${META}"

echo "[build-wardrobe] emitted ${META}"
echo "[build-wardrobe] tarball ${TARBALL} (${TARBALL_SIZE} bytes, sha256 ${TARBALL_SHA})"

# 8. Extraction round-trip: modes and bytes must survive tar.
RT="${WORK}/roundtrip"
mkdir -p "${RT}"
tar -C "${RT}" -xzf "${TARBALL}"
RT_ROOT="${RT}/wardrobe-${WARDROBE_VERSION}"
RT_EXEC="$(find "${RT_ROOT}" -type f -perm -0100 | wc -l | tr -d ' ')"
if [[ "${RT_EXEC}" != "${EXEC_COUNT}" ]]; then
    echo "[build-wardrobe] FATAL: exec bits lost in tar round-trip (${RT_EXEC} != ${EXEC_COUNT})"
    exit 1
fi
if ! diff -r "${PACK_STAGE}" "${RT_ROOT}" >/dev/null; then
    echo "[build-wardrobe] FATAL: tar round-trip content mismatch"
    exit 1
fi
echo "[build-wardrobe] round-trip OK (bytes + exec bits survive extraction)"

# 9. Signing + attestation (keyless OIDC in CI; opt-in locally).
if [[ "${COSIGN}" == "1" ]]; then
    command -v cosign >/dev/null || { echo "[build-wardrobe] COSIGN=1 but cosign not installed"; exit 1; }
    cosign sign-blob --yes --bundle "${TARBALL}.bundle" --output-signature "${TARBALL}.sig" "${TARBALL}"
    cosign sign-blob --yes --bundle "${META}.bundle" --output-signature "${META}.sig" "${META}"
    cosign attest-blob --yes \
        --predicate "${META_JSON}" \
        --type "https://arcaven.com/sideshow/install-meta" \
        --bundle "${TARBALL}.attest.bundle" \
        "${TARBALL}"
else
    echo "[build-wardrobe] signing skipped (COSIGN=${COSIGN})"
fi

echo "[build-wardrobe] done"
ls -la "${OUT_DIR}"
