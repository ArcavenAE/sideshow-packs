#!/usr/bin/env bash
# build-vsdd-factory.sh — build a frozen direct-tree artifact for
# vsdd-factory (the Claude plugin surface at plugins/vsdd-factory).
#
# Unlike bmad there is no upstream installer: acquisition is a git
# clone at an explicit release tag and a straight tree capture. The
# releases carry no assets; the tag IS the artifact source. Upstream's
# release flow commits CI-built binaries (5 dispatcher platforms, 34
# wasm hook-plugins from crates/) and force-moves the release tag onto
# that binary commit, so capture must happen against the settled tag
# (see the release-retags-by-design wrinkle in the register).
#
# Activation contract (ratified 2026-07-31, aae-orc-d4cw): vsdd-factory
# is per-repo-operation software — it runs IN a repo, never from an
# orchestrator or across repos. Content may install to the user-scope
# store multi-version like bmad, but activation is per repo, and
# sideshow delivery is the repo-bindings channel (unshaping): the
# claude plugin is upstream source format, and machine-level
# coexistence with a claude-mp install is supported.
#
# Emits (mirroring build-bmad.sh):
#   artifacts/vsdd-factory-<version>-arcaven.tar.gz
#   artifacts/install.meta.yaml / install.meta.json
#   artifacts/file-manifest.csv
#   artifacts/exec-manifest.txt   (relpaths that must carry exec bits)
#
# Environment:
#   VSDD_VERSION   (default: 1.0.0-rc.23) — bare version; tag is v<version>
#   VSDD_SRC       (default: https://github.com/drbothen/vsdd-factory.git)
#                  May be a local clone path for offline/prototype runs;
#                  a non-default value is recorded as src_override in
#                  install.meta and the artifact must not publish.
#   EXPECTED_UPSTREAM_SHA (default: empty) — when set, the build fails
#                  unless the cloned tag's commit equals it (set by
#                  upstream-intake from its soak observation).
#   OUT_DIR        (default: ./artifacts)
#   COSIGN         (default: 0)

set -euo pipefail

VSDD_VERSION="${VSDD_VERSION:-1.0.0-rc.23}"
CANONICAL_SRC="https://github.com/drbothen/vsdd-factory.git"
VSDD_SRC="${VSDD_SRC:-${CANONICAL_SRC}}"
EXPECTED_UPSTREAM_SHA="${EXPECTED_UPSTREAM_SHA:-}"
OUT_DIR="${OUT_DIR:-$(pwd)/artifacts}"
COSIGN="${COSIGN:-0}"
TAG="v${VSDD_VERSION}"
SUBTREE="plugins/vsdd-factory"

command -v git >/dev/null || { echo "error: git required"; exit 1; }
command -v jq >/dev/null || { echo "error: jq required"; exit 1; }
command -v yq >/dev/null || { echo "error: yq required"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTER="${SCRIPT_DIR}/../registry/vsdd-factory-pack-support.yaml"

# Packaging-support pre-flight (same gate as bmad).
bash "${SCRIPT_DIR}/check-support.sh" vsdd-factory "${VSDD_VERSION}"

# Provenance pin default (aae-orc-d3nq.11): when no SHA arrives via env
# or workflow input, fall back to the register's validated bracket.
# upstream_commit is meaningful only on single-rung brackets (min==max);
# upstream force-moves release tags by design, so a signed build with
# no pin would notarize whatever the tag points at today.
if [[ -z "${EXPECTED_UPSTREAM_SHA}" ]]; then
    EXPECTED_UPSTREAM_SHA="$(yq ".validated[] | select(.min == \"${VSDD_VERSION}\" and .max == \"${VSDD_VERSION}\") | .upstream_commit // \"\"" "${REGISTER}" 2>/dev/null | head -1)"
    if [[ -n "${EXPECTED_UPSTREAM_SHA}" ]]; then
        echo "[build-vsdd] SHA pin from register: ${EXPECTED_UPSTREAM_SHA}"
    fi
fi
if [[ "${COSIGN}" == "1" && -z "${EXPECTED_UPSTREAM_SHA}" ]]; then
    echo "[build-vsdd] FATAL: signing build with no upstream SHA pin (env, workflow input, or register upstream_commit)"
    exit 1
fi

WORK="$(mktemp -d -t vsdd-pack-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[build-vsdd] version=${VSDD_VERSION} tag=${TAG}"
echo "[build-vsdd] src=${VSDD_SRC}"
echo "[build-vsdd] work=${WORK}"
mkdir -p "${OUT_DIR}"

# 1. Acquire: shallow clone at the release tag. Never a branch HEAD —
#    default branch develop is ahead of any release (register wrinkle
#    gitflow-develop-head).
git clone --quiet --depth 1 --branch "${TAG}" "${VSDD_SRC}" "${WORK}/src"
TAG_COMMIT="$(git -C "${WORK}/src" rev-parse HEAD)"
SUBTREE_SHA="$(git -C "${WORK}/src" rev-parse "HEAD:${SUBTREE}")"
echo "[build-vsdd] tag commit ${TAG_COMMIT}"
echo "[build-vsdd] subtree ${SUBTREE} tree ${SUBTREE_SHA}"

# Provenance pre-check: bind to the SHA observed during the intake
# soak window, before any content is staged.
if [[ -n "${EXPECTED_UPSTREAM_SHA}" ]]; then
    if [[ "${TAG_COMMIT}" != "${EXPECTED_UPSTREAM_SHA}" ]]; then
        echo "[build-vsdd] FATAL: upstream provenance mismatch: tag commit ${TAG_COMMIT} != expected ${EXPECTED_UPSTREAM_SHA}"
        exit 1
    fi
    echo "[build-vsdd] upstream provenance verified: tag commit matches observed SHA"
fi

SRC_OVERRIDE="null"
if [[ "${VSDD_SRC}" != "${CANONICAL_SRC}" ]]; then
    SRC_OVERRIDE="$(jq -n --arg s "${VSDD_SRC}" '$s')"
    echo "[build-vsdd] WARN: non-canonical src; artifact is prototype-grade and must not publish"
fi

[[ -d "${WORK}/src/${SUBTREE}" ]] || { echo "[build-vsdd] FATAL: ${SUBTREE} missing at ${TAG}"; exit 1; }
[[ -f "${WORK}/src/LICENSE" ]] || { echo "[build-vsdd] FATAL: upstream LICENSE missing"; exit 1; }

# 2. Stage the plugin tree (cp -R preserves the exec bits git applied
#    at checkout).
PACK_STAGE="${WORK}/pack"
mkdir -p "${PACK_STAGE}"
cp -R "${WORK}/src/${SUBTREE}/." "${PACK_STAGE}/"

# license-notice (aae-orc-d3nq.10): MIT requires the copyright and
# permission notice to accompany all copies, and the plugin subtree
# ships no LICENSE file. Stage the clone-root license into the pack so
# it lands in file-manifest.csv and the tarball.
cp "${WORK}/src/LICENSE" "${PACK_STAGE}/LICENSE"
echo "[build-vsdd] staged clone-root LICENSE into pack"

# 3. Verify pipeline assumptions mechanically (register:
#    pipeline_assumptions). Each failure is fatal.

# plugin-manifest-shape
PLUGIN_JSON="${PACK_STAGE}/.claude-plugin/plugin.json"
[[ -f "${PLUGIN_JSON}" ]] || { echo "[build-vsdd] FATAL: .claude-plugin/plugin.json missing"; exit 1; }
P_NAME="$(jq -r .name "${PLUGIN_JSON}")"
P_VERSION="$(jq -r .version "${PLUGIN_JSON}")"
P_LICENSE="$(jq -r '.license // empty' "${PLUGIN_JSON}")"
[[ "${P_NAME}" == "vsdd-factory" ]] || { echo "[build-vsdd] FATAL: plugin name '${P_NAME}' != vsdd-factory"; exit 1; }
[[ "${P_VERSION}" == "${VSDD_VERSION}" ]] || { echo "[build-vsdd] FATAL: plugin.json version '${P_VERSION}' != requested ${VSDD_VERSION}"; exit 1; }
echo "[build-vsdd] plugin manifest OK (name=${P_NAME} version=${P_VERSION} license=${P_LICENSE:-unspecified})"

# exec-bits-preserved: staged executable count must equal the tag's
# 100755 count for the subtree. Both sides are computed from the tag at
# build time, so this gate self-adjusts as upstream adds or removes
# executables; it asks "did capture preserve the bits", not "does the
# count match a stored number". Observed counts, for orientation only:
# 112 at rc.23, 117 at rc.24 (+3 wasm hook-plugins, +2 test fixtures).
# Drift means broken
# hooks/binaries at install time.
EXPECTED_EXEC="$(git -C "${WORK}/src" ls-tree -r HEAD "${SUBTREE}" | awk '$1=="100755"' | wc -l | tr -d ' ')"
ACTUAL_EXEC="$(find "${PACK_STAGE}" -type f -perm -0100 | wc -l | tr -d ' ')"
if [[ "${EXPECTED_EXEC}" != "${ACTUAL_EXEC}" ]]; then
    echo "[build-vsdd] FATAL: exec-bit drift: tag has ${EXPECTED_EXEC} executables, stage has ${ACTUAL_EXEC}"
    exit 1
fi
echo "[build-vsdd] exec bits OK (${ACTUAL_EXEC} executable files)"

# hooks-json-platform-bind: canonical hooks.json must be ABSENT
# (rendered per-machine by /vsdd-factory:activate); platform templates
# must be present.
if [[ -e "${PACK_STAGE}/hooks/hooks.json" ]]; then
    echo "[build-vsdd] FATAL: hooks/hooks.json present in tree; it is per-machine state, not content"
    exit 1
fi
TEMPLATES="$(find "${PACK_STAGE}/hooks" -maxdepth 1 -name 'hooks.json.*' | wc -l | tr -d ' ')"
if (( TEMPLATES < 5 )); then
    echo "[build-vsdd] FATAL: expected >=5 hooks.json.<platform> templates, found ${TEMPLATES}"
    exit 1
fi
if find "${PACK_STAGE}" -name '.in_use' | grep -q .; then
    echo "[build-vsdd] FATAL: .in_use bookkeeping present in tree"
    exit 1
fi
echo "[build-vsdd] per-machine bookkeeping absent, ${TEMPLATES} platform templates present"

# Content census for provenance metadata.
WASM_COUNT="$(find "${PACK_STAGE}/hook-plugins" -name '*.wasm' | wc -l | tr -d ' ')"
DISPATCHER_COUNT="$(find "${PACK_STAGE}/hooks/dispatcher/bin" -type f | wc -l | tr -d ' ')"

# 4. Emit pack.yaml (consumed by sideshow). No custom_bridge, no
#    runtime_links — those are bmad-shaped concerns. The load-bearing
#    declaration is the activation contract.
cat > "${PACK_STAGE}/pack.yaml" <<YAML
# pack.yaml — consumed by sideshow to apply the consumer contract.
name: vsdd-factory
version: ${VSDD_VERSION}
schema_version: 0.1.0

# Ratified 2026-07-31 (aae-orc-d4cw + finding-094): vsdd-factory is
# per-repo-operation software. It runs IN a repo; it is not designed
# to run from an orchestrator or across repos. Multi-version store
# install is fine; activation is per repo via the repo-bindings
# mechanism (unshaping): sideshow enable materializes the discovery
# surface into one named repo and store-references the engine; no
# harness plugin state is written. Bound artifacts carry the vsdd-
# prefix. The runbook below is the consumer contract (verified on
# Claude Code 2.1.220, finding-091).
activation:
  default_scope: per-repo
  per_repo_required: true
  mechanism: repo-bindings
  binding_prefix: vsdd
  runbook: https://github.com/ArcavenAE/sideshow/blob/main/docs/repo-bindings-enablement.md
  validated_harness_floor: "claude-code 2.1.220"
YAML

# 5. file-manifest.csv (sha256,size,relpath) + exec-manifest.txt.
echo "[build-vsdd] computing file manifest"
(
    cd "${PACK_STAGE}"
    find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do
        if command -v sha256sum >/dev/null; then
            sha=$(sha256sum "$f" | awk '{print $1}')
        else
            sha=$(shasum -a 256 "$f" | awk '{print $1}')
        fi
        if [[ "$(uname)" == "Darwin" ]]; then
            size=$(stat -f %z "$f")
        else
            size=$(stat -c %s "$f")
        fi
        printf '%s,%s,%s\n' "$sha" "$size" "${f#./}"
    done
) > "${OUT_DIR}/file-manifest.csv"
FILE_COUNT=$(wc -l < "${OUT_DIR}/file-manifest.csv" | tr -d ' ')

(
    cd "${PACK_STAGE}"
    find . -type f -perm -0100 | sed 's|^\./||' | LC_ALL=C sort
) > "${OUT_DIR}/exec-manifest.txt"

# 6. Tarball.
TARBALL="${OUT_DIR}/vsdd-factory-${VSDD_VERSION}-arcaven.tar.gz"
echo "[build-vsdd] packaging -> ${TARBALL}"
tar -C "${WORK}" -czf "${TARBALL}" -s '/pack/vsdd-factory-'"${VSDD_VERSION}"'/' pack 2>/dev/null \
    || tar -C "${WORK}" --transform "s|^pack|vsdd-factory-${VSDD_VERSION}|" -czf "${TARBALL}" pack
if command -v sha256sum >/dev/null; then
    TARBALL_SHA="$(sha256sum "${TARBALL}" | awk '{print $1}')"
else
    TARBALL_SHA="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
fi
if [[ "$(uname)" == "Darwin" ]]; then
    TARBALL_SIZE=$(stat -f %z "${TARBALL}")
else
    TARBALL_SIZE=$(stat -c %s "${TARBALL}")
fi

# Manifest hashes (aae-orc-d3nq.12): binding these into install.meta
# puts both manifests under the existing signature and attestation
# transitively, so the documented integrity check verifies against an
# authenticated record instead of a bare release asset.
if command -v sha256sum >/dev/null; then
    FILE_MANIFEST_SHA="$(sha256sum "${OUT_DIR}/file-manifest.csv" | awk '{print $1}')"
    EXEC_MANIFEST_SHA="$(sha256sum "${OUT_DIR}/exec-manifest.txt" | awk '{print $1}')"
else
    FILE_MANIFEST_SHA="$(shasum -a 256 "${OUT_DIR}/file-manifest.csv" | awk '{print $1}')"
    EXEC_MANIFEST_SHA="$(shasum -a 256 "${OUT_DIR}/exec-manifest.txt" | awk '{print $1}')"
fi

# 7. install.meta — git-tree provenance (no npm to cite). Field shape
#    is the aae-orc-bgbm v0.2 draft. schema_version names the shape;
#    schema_stability says whether we promise it (aae-orc-d3nq.13).
#    The two are separate so adding a field never forces a rename of
#    anything already published.
PRODUCED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
META="${OUT_DIR}/install.meta.yaml"
META_JSON="${OUT_DIR}/install.meta.json"
SIGNING_STATUS="$( [[ "${COSIGN}" == "1" ]] && echo 'signed' || echo 'unsigned-local-build' )"

jq -n \
  --arg version "${VSDD_VERSION}" \
  --arg produced_at "${PRODUCED_AT}" \
  --arg repo "${CANONICAL_SRC}" \
  --arg tag "${TAG}" \
  --arg commit "${TAG_COMMIT}" \
  --arg subtree "${SUBTREE}" \
  --arg subtree_sha "${SUBTREE_SHA}" \
  --arg license "${P_LICENSE:-MIT}" \
  --argjson src_override "${SRC_OVERRIDE}" \
  --argjson file_count "${FILE_COUNT}" \
  --argjson exec_count "${ACTUAL_EXEC}" \
  --argjson wasm_count "${WASM_COUNT}" \
  --argjson dispatcher_count "${DISPATCHER_COUNT}" \
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
      name: "vsdd-factory",
      version: $version,
      produced_at: $produced_at,
      produced_by: "sideshow-packs/scripts/build-vsdd-factory.sh"
    },
    upstream: {
      repo: $repo,
      tag: $tag,
      commit_sha: $commit,
      subtree_path: $subtree,
      subtree_sha: $subtree_sha,
      license: $license,
      license_file: "LICENSE",
      src_override: $src_override,
      binary_provenance: "wasm hook-plugins from crates/hook-plugins/*, dispatcher binaries from crates/factory-dispatcher, built and committed by upstream release CI at this tag"
    },
    acquisition: {
      method: "direct-tree",
      release_line: "prerelease"
    },
    content: {
      file_count: $file_count,
      executable_count: $exec_count,
      wasm_hook_plugins: $wasm_count,
      dispatcher_binaries: $dispatcher_count,
      in_plugin_tests: true
    },
    activation: {
      default_scope: "per-repo",
      per_repo_required: true,
      mechanism: "repo-bindings",
      binding_prefix: "vsdd"
    },
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
    cat <<HEADER
# Frozen direct-tree artifact provenance — vsdd-factory@${VSDD_VERSION}
# Produced by sideshow-packs build-vsdd-factory.sh.
# Intended for verification by sideshow install; not yet implemented
# (aae-orc-wk92); verify manually with cosign until then.

HEADER
    cat "${META}"
} > "${META}.tmp" && mv "${META}.tmp" "${META}"

echo "[build-vsdd] emitted ${META}"
echo "[build-vsdd] emitted ${META_JSON}"
echo "[build-vsdd] emitted ${OUT_DIR}/file-manifest.csv (${FILE_COUNT} files)"
echo "[build-vsdd] emitted ${OUT_DIR}/exec-manifest.txt (${ACTUAL_EXEC} executables)"
echo "[build-vsdd] tarball ${TARBALL} (${TARBALL_SIZE} bytes, sha256 ${TARBALL_SHA})"

# 8. Extraction round-trip verification: modes and bytes must survive
#    tar. This is the property consumers depend on.
RT="${WORK}/roundtrip"
mkdir -p "${RT}"
tar -C "${RT}" -xzf "${TARBALL}"
RT_ROOT="${RT}/vsdd-factory-${VSDD_VERSION}"
RT_EXEC="$(find "${RT_ROOT}" -type f -perm -0100 | wc -l | tr -d ' ')"
if [[ "${RT_EXEC}" != "${ACTUAL_EXEC}" ]]; then
    echo "[build-vsdd] FATAL: exec bits lost in tar round-trip (${RT_EXEC} != ${ACTUAL_EXEC})"
    exit 1
fi
if ! diff -r "${PACK_STAGE}" "${RT_ROOT}" >/dev/null; then
    echo "[build-vsdd] FATAL: tar round-trip content mismatch"
    exit 1
fi
echo "[build-vsdd] round-trip OK (bytes + exec bits survive extraction)"

# 9. Signing + attestation (keyless OIDC in CI; opt-in locally).
if [[ "${COSIGN}" == "1" ]]; then
    command -v cosign >/dev/null || { echo "[build-vsdd] COSIGN=1 but cosign not installed"; exit 1; }
    echo "[build-vsdd] cosign sign-blob (tarball)"
    cosign sign-blob --yes \
        --bundle "${TARBALL}.bundle" \
        --output-signature "${TARBALL}.sig" \
        "${TARBALL}"
    echo "[build-vsdd] cosign sign-blob (meta)"
    cosign sign-blob --yes \
        --bundle "${META}.bundle" \
        --output-signature "${META}.sig" \
        "${META}"
    # The predicate type identifies the KIND of document, not its shape,
    # so it carries no version (aae-orc-d3nq.13). Versioning it would put
    # a string that published artifacts freeze in lockstep with a schema
    # that is still growing fields; the version lives in-band instead,
    # read after verification. Departs from the SLSA convention
    # (slsa.dev/provenance/v1) deliberately: the signature and CI
    # identity are the trust anchor either way, and nothing routes on
    # --type before decoding the payload.
    echo "[build-vsdd] cosign attest-blob (sideshow install-meta predicate)"
    cosign attest-blob --yes \
        --predicate "${META_JSON}" \
        --type "https://arcaven.com/sideshow/install-meta" \
        --bundle "${TARBALL}.attest.bundle" \
        "${TARBALL}"
else
    echo "[build-vsdd] signing skipped (COSIGN=${COSIGN})"
fi

echo "[build-vsdd] done"
ls -la "${OUT_DIR}"
