#!/usr/bin/env bash
# build-bmad.sh — build a frozen-composition artifact for bmad.
#
# Runs the upstream npx installer in an isolated working directory,
# captures the produced tree, pre-assembles the sideshow-compatible
# layout (strip `_bmad/` prefix, unify with `.claude/`), and emits:
#
#   artifacts/bmad-<version>-arcaven.tar.gz
#   artifacts/install.meta.yaml
#   artifacts/file-manifest.csv
#   artifacts/exec-manifest.txt
#
# If COSIGN=1 and cosign is installed, also emits signatures +
# attestations (keyless OIDC in CI; local runs need identity/keys).
#
# Environment:
#   BMAD_VERSION   (default: 6.3.0)
#   BMAD_MODULES   (default: bmm,cis,gds,tea)
#   BMAD_TOOLS     (default: claude-code)
#   BMAD_PINS      (default: auto) — external-module pinning policy:
#                    auto   = resolve each external module to its highest
#                             pure-semver git tag published on or before
#                             bmad-method@VERSION's npm publish date
#                             (as-of-release-date composition; 6.4.0+ only —
#                             6.3.x has no upstream pin mechanism)
#                    none   = float to upstream default (stable channel /
#                             default-branch HEAD on 6.3.x)
#                    "cis=v0.2.0,gds=v0.6.0" = explicit pin list
#   OUT_DIR        (default: ./artifacts)
#   COSIGN         (default: 0)
#   EXPECTED_UPSTREAM_SHA (default: empty) — when set, the build fails
#                  unless npm's recorded gitHead for
#                  bmad-method@VERSION equals it, verified BEFORE the
#                  installer runs. Binds the artifact to the git tag
#                  SHA observed during upstream-intake's soak window.

set -euo pipefail

BMAD_VERSION="${BMAD_VERSION:-6.3.0}"
BMAD_MODULES="${BMAD_MODULES:-bmm,cis,gds,tea}"
BMAD_TOOLS="${BMAD_TOOLS:-claude-code}"
BMAD_PINS="${BMAD_PINS:-auto}"
OUT_DIR="${OUT_DIR:-$(pwd)/artifacts}"
COSIGN="${COSIGN:-0}"

command -v npx >/dev/null || { echo "error: npx required"; exit 1; }
command -v yq >/dev/null || { echo "error: yq required (https://github.com/mikefarah/yq)"; exit 1; }
command -v jq >/dev/null || { echo "error: jq required"; exit 1; }
command -v git >/dev/null || { echo "error: git required"; exit 1; }
command -v python3 >/dev/null || { echo "error: python3 required"; exit 1; }

# Packaging-support pre-flight: refuses versions outside the validated
# bracket in registry/bmad-pack-support.yaml unless ALLOW_UNSUPPORTED=1. See
# registry/pack-support-revalidation-runbook.md for the supported path forward.
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-support.sh" bmad "${BMAD_VERSION}"

# --- External-module pin resolution -----------------------------------
#
# External modules (cis/gds/tea) are git-cloned by the upstream installer:
# at 6.3.x from default-branch HEAD (no pin mechanism exists), at 6.4.0+
# from the highest stable git tag unless --pin CODE=TAG is passed. To make
# compositions date-deterministic we resolve, per module, the highest
# pure-semver tag published on or before bmad-method@VERSION's npm publish
# date. Upstream silently ignores malformed pins, so resolved versions are
# verified against the produced manifest after install (fatal on drift).
# See finding-070.

module_repo() {
    case "$1" in
        cis) echo "https://github.com/bmad-code-org/bmad-module-creative-intelligence-suite" ;;
        gds) echo "https://github.com/bmad-code-org/bmad-module-game-dev-studio" ;;
        tea) echo "https://github.com/bmad-code-org/bmad-method-test-architecture-enterprise" ;;
        bmb) echo "https://github.com/bmad-code-org/bmad-builder" ;;
        wds) echo "https://github.com/bmad-code-org/bmad-method-wds-expansion" ;;
        *)   echo "" ;;
    esac
}

iso_to_epoch() {
    python3 -c "import sys,datetime; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).timestamp()))" "$1"
}

# Highest pure-semver tag with tag date <= as-of epoch. Bare partial clone,
# no blobs — a few KB per module repo.
resolve_tag_asof() { # repo_url asof_epoch
    local url="$1" asof="$2" tmp tag
    tmp="$(mktemp -d -t bmad-pin-XXXXXX)"
    git clone --quiet --bare --filter=blob:none "$url" "$tmp/repo.git"
    tag="$(git -C "$tmp/repo.git" for-each-ref \
            --format='%(creatordate:unix) %(refname:short)' refs/tags \
        | awk -v asof="$asof" '$1 <= asof {print $2}' \
        | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V | tail -1 || true)"
    rm -rf "$tmp"
    echo "$tag"
}

version_ge_640() {
    [[ "$(printf '%s\n' "6.4.0" "$1" | sort -V | head -1)" == "6.4.0" ]]
}

PIN_FLAGS=()
REQUESTED_PINS_JSON="{}"
PIN_POLICY="none"
AS_OF_DATE=""

if [[ "${BMAD_PINS}" == "none" ]]; then
    PIN_POLICY="unpinned-floating"
elif ! version_ge_640 "${BMAD_VERSION}"; then
    PIN_POLICY="unpinned-no-mechanism-at-this-version"
    if [[ "${BMAD_PINS}" != "auto" ]]; then
        echo "[build-bmad] FATAL: BMAD_PINS set but bmad ${BMAD_VERSION} has no pin mechanism (--pin exists at 6.4.0+)"
        exit 1
    fi
    echo "[build-bmad] pins: ${PIN_POLICY} (composition is build-time-recorded only)"
elif [[ "${BMAD_PINS}" == "auto" ]]; then
    PIN_POLICY="as-of-release-date"
    AS_OF_DATE="$(npm view bmad-method time --json | jq -r --arg v "${BMAD_VERSION}" '.[$v] // empty')"
    if [[ -z "${AS_OF_DATE}" ]]; then
        echo "[build-bmad] FATAL: no npm publish date for bmad-method@${BMAD_VERSION}"
        exit 1
    fi
    AS_OF_EPOCH="$(iso_to_epoch "${AS_OF_DATE}")"
    echo "[build-bmad] pins: resolving as-of ${AS_OF_DATE}"
    IFS=',' read -ra MODULE_LIST <<< "${BMAD_MODULES}"
    for code in "${MODULE_LIST[@]}"; do
        repo="$(module_repo "$code")"
        [[ -z "$repo" ]] && continue  # built-in (core/bmm) or unknown: version-locked by bmad-method@VERSION
        tag="$(resolve_tag_asof "$repo" "$AS_OF_EPOCH")"
        if [[ -z "$tag" ]]; then
            echo "[build-bmad] FATAL: no semver tag for ${code} (${repo}) at or before ${AS_OF_DATE}"
            exit 1
        fi
        echo "[build-bmad] pin ${code}=${tag}"
        PIN_FLAGS+=(--pin "${code}=${tag}")
        REQUESTED_PINS_JSON="$(jq -c --arg k "$code" --arg v "$tag" '. + {($k): $v}' <<< "$REQUESTED_PINS_JSON")"
    done
else
    PIN_POLICY="explicit"
    IFS=',' read -ra PIN_LIST <<< "${BMAD_PINS}"
    for kv in "${PIN_LIST[@]}"; do
        code="${kv%%=*}"; tag="${kv#*=}"
        if [[ -z "$code" || -z "$tag" || "$code" == "$tag" ]]; then
            echo "[build-bmad] FATAL: malformed BMAD_PINS entry: ${kv}"
            exit 1
        fi
        echo "[build-bmad] pin ${code}=${tag} (explicit)"
        PIN_FLAGS+=(--pin "${code}=${tag}")
        REQUESTED_PINS_JSON="$(jq -c --arg k "$code" --arg v "$tag" '. + {($k): $v}' <<< "$REQUESTED_PINS_JSON")"
    done
fi

# Provenance pre-check: verify the npm package's gitHead against the
# SHA observed during the intake soak window, BEFORE any upstream code
# executes. npm versions are immutable but the git tag is not; this
# check binds the two (upstream-intake dispatches expected_sha).
EXPECTED_UPSTREAM_SHA="${EXPECTED_UPSTREAM_SHA:-}"
if [[ -n "${EXPECTED_UPSTREAM_SHA}" ]]; then
    NPM_GIT_HEAD="$(npm view "bmad-method@${BMAD_VERSION}" gitHead 2>/dev/null || echo '')"
    if [[ -z "${NPM_GIT_HEAD}" ]]; then
        echo "[build-bmad] FATAL: EXPECTED_UPSTREAM_SHA set but npm records no gitHead for bmad-method@${BMAD_VERSION}; cannot verify provenance"
        exit 1
    fi
    if [[ "${NPM_GIT_HEAD}" != "${EXPECTED_UPSTREAM_SHA}" ]]; then
        echo "[build-bmad] FATAL: upstream provenance mismatch: npm gitHead ${NPM_GIT_HEAD} != expected ${EXPECTED_UPSTREAM_SHA} (observed git tag SHA)"
        exit 1
    fi
    echo "[build-bmad] upstream provenance verified: npm gitHead matches observed tag SHA (${NPM_GIT_HEAD})"
fi

WORK="$(mktemp -d -t bmad-pack-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[build-bmad] version=${BMAD_VERSION} modules=${BMAD_MODULES} tools=${BMAD_TOOLS}"
echo "[build-bmad] work=${WORK}"
echo "[build-bmad] out=${OUT_DIR}"
mkdir -p "${OUT_DIR}"

# 1. Run upstream installer in isolated dir.
INSTALL_ROOT="${WORK}/install"
mkdir -p "${INSTALL_ROOT}"
cd "${INSTALL_ROOT}"
echo "[build-bmad] invoking npx bmad-method@${BMAD_VERSION} install (${#PIN_FLAGS[@]} pin flags)"
npx --yes "bmad-method@${BMAD_VERSION}" install \
    --directory "${INSTALL_ROOT}" \
    --modules "${BMAD_MODULES}" \
    --tools "${BMAD_TOOLS}" \
    --action install \
    --user-name arcaven-ci \
    --output-folder _bmad-output \
    ${PIN_FLAGS[@]+"${PIN_FLAGS[@]}"} \
    --yes \
    >"${WORK}/installer.stdout" 2>"${WORK}/installer.stderr"

if [[ ! -d "${INSTALL_ROOT}/_bmad" ]]; then
    echo "[build-bmad] FATAL: installer did not produce _bmad/ under ${INSTALL_ROOT}"
    cat "${WORK}/installer.stderr" >&2
    exit 1
fi

# 2. Capture upstream provenance: git head sha + npm tarball sha.
UPSTREAM_GIT_HEAD="$(npm view "bmad-method@${BMAD_VERSION}" gitHead 2>/dev/null || echo '')"
UPSTREAM_REPO="$(npm view "bmad-method@${BMAD_VERSION}" repository.url 2>/dev/null | sed 's|^git+||;s|\.git$||' || echo '')"
UPSTREAM_TARBALL_URL="$(npm view "bmad-method@${BMAD_VERSION}" dist.tarball 2>/dev/null || echo '')"
UPSTREAM_TARBALL_SHASUM="$(npm view "bmad-method@${BMAD_VERSION}" dist.shasum 2>/dev/null || echo '')"

# 3. Pre-assemble sideshow pack layout (strip _bmad/ prefix, unify with .claude/).
PACK_STAGE="${WORK}/pack"
mkdir -p "${PACK_STAGE}"
cp -R "${INSTALL_ROOT}/_bmad/." "${PACK_STAGE}/"
[[ -d "${INSTALL_ROOT}/.claude" ]] && cp -R "${INSTALL_ROOT}/.claude" "${PACK_STAGE}/"

# 3b. Emit pack.yaml inside the pack (consumed by sideshow's distribute
# layer for consumer-repo convention enforcement — aae-orc-794h).
cat > "${PACK_STAGE}/pack.yaml" <<YAML
# pack.yaml — consumed by sideshow to apply consumer-repo convention.
# See: sideshow/docs/consumer-repo-convention.md (aae-orc-794h).
name: bmad
version: ${BMAD_VERSION}
schema_version: 0.1.0

distribute:
  # Customization bridge (bmad 6.4+ reads _bmad/custom/ at runtime).
  # sideshow symlinks _bmad/custom -> ../_bmad-custom so customization
  # lands in checked-in territory and survives pack version switches.
  # Declared for all bmad versions: pre-6.4 upstream never reads the
  # path, so the bridge is inert there. See
  # sideshow/docs/customization-bridge.md (aae-orc-mkpo).
  custom_bridge:
    upstream_path: _bmad/custom
    per_repo_dir: _bmad-custom
  # Runtime read surfaces upstream resolvers expect at {project-root}/_bmad/
  # (resolve_config's four-file chain + scripts). Enumerated deliberately;
  # the reference scanner (sideshow-packs#2) proposes additions per
  # version. See sideshow#52 / aae-orc finding-074.
  runtime_links:
    - link: scripts
      target: scripts
    - link: _config
      target: _config
    - link: config.toml
      target: config.toml
    - link: config.user.toml
      target: config.user.toml
  gitignore:
    # Pack content — sideshow installs to user-scope; project-local copies
    # are redundant and conflict with multi-user sideshow installs.
    - /_bmad/
    # Tool binding duplicates — sideshow syncs ~/.claude/ at user-scope.
    # Prefixes cover the full module roster; entries for modules not in
    # this composition are harmless.
    - /.claude/commands/bmad-*.md
    - /.claude/skills/bmad-*/
    - /.claude/skills/gds-*/
    - /.claude/skills/cis-*/
    - /.claude/skills/tea-*/
    - /.claude/skills/bmb-*/
    - /.claude/skills/wds-*/
    # Personal config layer (upstream four-file intent: config.user.toml
    # is per-person, config.toml is team-committed).
    - /_bmad-custom/config.user.toml
YAML

# 4. Emit file-manifest.csv (sha256,size,relpath).
echo "[build-bmad] computing file manifest"
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

# 4b. exec-manifest.txt + manifest hashes (aae-orc-d3nq.12): same
# contract shape as build-vsdd-factory.sh so consumers verify every
# pack identically. bmad ships no executables today; an empty manifest
# recording that fact is still part of the signed contract.
(
    cd "${PACK_STAGE}"
    find . -type f -perm -0100 | sed 's|^\./||' | LC_ALL=C sort
) > "${OUT_DIR}/exec-manifest.txt"
if command -v sha256sum >/dev/null; then
    FILE_MANIFEST_SHA="$(sha256sum "${OUT_DIR}/file-manifest.csv" | awk '{print $1}')"
    EXEC_MANIFEST_SHA="$(sha256sum "${OUT_DIR}/exec-manifest.txt" | awk '{print $1}')"
else
    FILE_MANIFEST_SHA="$(shasum -a 256 "${OUT_DIR}/file-manifest.csv" | awk '{print $1}')"
    EXEC_MANIFEST_SHA="$(shasum -a 256 "${OUT_DIR}/exec-manifest.txt" | awk '{print $1}')"
fi

# 5. Parse modules from the bmad manifest for provenance metadata.
BMAD_MANIFEST="${PACK_STAGE}/_config/manifest.yaml"
if [[ ! -f "${BMAD_MANIFEST}" ]]; then
    echo "[build-bmad] FATAL: expected manifest at ${BMAD_MANIFEST}"
    exit 1
fi

# 5b. Verify requested pins took effect. Upstream warns-and-ignores
# malformed pins rather than failing, so the pipeline must be the one
# to fail on composition drift (finding-070).
if [[ "${REQUESTED_PINS_JSON}" != "{}" ]]; then
    echo "[build-bmad] verifying resolved module versions against requested pins"
    PIN_MISMATCH=0
    while IFS=$'\t' read -r code tag; do
        # Normalize the v-prefix on BOTH sides: requested pins are git
        # tags (v0.4.0) while the manifest records bare versions at
        # 6.3.x ("0.2.0") but tag-verbatim at 6.4.0+ ("v0.2.0").
        want="${tag#v}"
        got="$(yq ".modules[] | select(.name == \"${code}\") | .version" "${BMAD_MANIFEST}")"
        got="${got#v}"
        if [[ "${got}" != "${want}" ]]; then
            echo "[build-bmad] PIN DRIFT: ${code} requested ${tag}, manifest has ${got:-<absent>}"
            PIN_MISMATCH=1
        fi
    done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' <<< "${REQUESTED_PINS_JSON}")
    if [[ "${PIN_MISMATCH}" == "1" ]]; then
        echo "[build-bmad] FATAL: composition does not match requested pins"
        exit 1
    fi
    echo "[build-bmad] pins verified"
fi

# 6. Build the tarball (tar from pack stage, gzip).
TARBALL="${OUT_DIR}/bmad-${BMAD_VERSION}-arcaven.tar.gz"
echo "[build-bmad] packaging -> ${TARBALL}"
tar -C "${WORK}" -czf "${TARBALL}" -s '/pack/bmad-'"${BMAD_VERSION}"'/' pack 2>/dev/null \
    || tar -C "${WORK}" --transform "s|^pack|bmad-${BMAD_VERSION}|" -czf "${TARBALL}" pack
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

# 7. Emit install.meta.json (canonical) + install.meta.yaml (derived).
#
# JSON is built via jq to guarantee structural validity: it's the
# attestation predicate cosign attest-blob signs. YAML is derived
# from the JSON via yq -P for human-readable consumption. Building
# JSON-first avoids YAML quoting/indentation pitfalls when
# interpolating multi-line module-manifest data.
#
# schema_version is 0.1.1, not 0.1.0: the nine published bmad releases
# (6.3.0 through 6.10.0, measured 2026-08-01) carry no
# artifact.file_manifest_sha256 / exec_manifest_sha256 (added 5f3d4a4),
# no schema_stability and no acquisition block. Leaving this at 0.1.0
# would stamp a second, different shape with the version string those
# artifacts already use. Additive only, so the bump is a patch and stays
# within sideshow's exact-minor compatibility rule. Do not revert it to
# match the published artifacts; they are immutable and their version
# string is correct for what they contain.
PRODUCED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
META="${OUT_DIR}/install.meta.yaml"
META_JSON="${OUT_DIR}/install.meta.json"
SIGNING_STATUS="$( [[ "${COSIGN}" == "1" ]] && echo 'signed' || echo 'unsigned-local-build' )"

# Extract module metadata from the bmad manifest as a JSON array.
MODULES_JSON="$(yq -o json '.modules' "${BMAD_MANIFEST}")"

jq -n \
  --arg version "${BMAD_VERSION}" \
  --arg produced_at "${PRODUCED_AT}" \
  --arg npm_tarball_url "${UPSTREAM_TARBALL_URL}" \
  --arg npm_tarball_shasum "${UPSTREAM_TARBALL_SHASUM}" \
  --arg git_head "${UPSTREAM_GIT_HEAD}" \
  --arg repository "${UPSTREAM_REPO}" \
  --argjson modules "${MODULES_JSON:-null}" \
  --arg modules_csv "${BMAD_MODULES}" \
  --arg tools "${BMAD_TOOLS}" \
  --arg pin_policy "${PIN_POLICY}" \
  --arg as_of_date "${AS_OF_DATE}" \
  --argjson requested_pins "${REQUESTED_PINS_JSON}" \
  --arg tarball "$(basename "${TARBALL}")" \
  --arg tarball_sha256 "${TARBALL_SHA}" \
  --argjson tarball_bytes "${TARBALL_SIZE}" \
  --argjson file_count "${FILE_COUNT}" \
  --arg file_manifest_sha256 "${FILE_MANIFEST_SHA}" \
  --arg exec_manifest_sha256 "${EXEC_MANIFEST_SHA}" \
  --arg signing_status "${SIGNING_STATUS}" \
  '{
    schema_version: "0.1.1",
    schema_stability: "draft",
    pack: {
      name: "bmad",
      version: $version,
      produced_at: $produced_at,
      produced_by: "sideshow-packs/scripts/build-bmad.sh"
    },
    upstream: {
      npm_package: ("bmad-method@" + $version),
      npm_tarball_url: $npm_tarball_url,
      npm_tarball_shasum: $npm_tarball_shasum,
      git_head: $git_head,
      repository: $repository
    },
    composition: {
      modules_from_manifest: $modules,
      tools: [$tools],
      pin_policy: $pin_policy,
      as_of_date: (if $as_of_date == "" then null else $as_of_date end),
      requested_pins: $requested_pins
    },
    install_invocation: {
      cmd: ("npx --yes bmad-method@" + $version + " install"),
      flags: [
        "--directory <workdir>",
        ("--modules " + $modules_csv),
        ("--tools " + $tools),
        "--action install",
        "--user-name arcaven-ci",
        "--output-folder _bmad-output",
        "--yes"
      ]
    },
    acquisition: {
      method: "npm-composition",
      release_line: "stable"
    },
    artifact: {
      tarball: $tarball,
      tarball_sha256: $tarball_sha256,
      tarball_bytes: $tarball_bytes,
      file_count: $file_count,
      file_manifest_sha256: $file_manifest_sha256,
      exec_manifest_sha256: $exec_manifest_sha256,
      layout: (["_config/", "core/"]
        + ($modules_csv | split(",") | map(. + "/"))
        + [".claude/"])
    },
    signing: { status: $signing_status }
  }' > "${META_JSON}"

# Derive YAML from JSON for human consumption. Explicit -p/-o because
# yq's format auto-detect from .json extension flips output to JSON
# even with -P alone.
yq -p json -o yaml "${META_JSON}" > "${META}"
# Prepend the comment header that explains the artifact origin.
{
    cat <<HEADER
# Frozen-composition artifact provenance — bmad@${BMAD_VERSION}
# Produced by sideshow-packs build-bmad.sh.
# Intended for verification by sideshow install; not yet implemented
# (aae-orc-wk92); verify manually with cosign until then.

HEADER
    cat "${META}"
} > "${META}.tmp" && mv "${META}.tmp" "${META}"

echo "[build-bmad] emitted ${META}"
echo "[build-bmad] emitted ${META_JSON}"
echo "[build-bmad] emitted ${OUT_DIR}/file-manifest.csv (${FILE_COUNT} files)"
echo "[build-bmad] emitted ${OUT_DIR}/exec-manifest.txt"
echo "[build-bmad] tarball ${TARBALL} (${TARBALL_SIZE} bytes, sha256 ${TARBALL_SHA})"

# 8. Signing + attestation (keyless OIDC in CI; opt-in locally).
if [[ "${COSIGN}" == "1" ]]; then
    command -v cosign >/dev/null || { echo "[build-bmad] COSIGN=1 but cosign not installed"; exit 1; }

    echo "[build-bmad] cosign sign-blob (tarball)"
    cosign sign-blob --yes \
        --bundle "${TARBALL}.bundle" \
        --output-signature "${TARBALL}.sig" \
        "${TARBALL}"

    echo "[build-bmad] cosign sign-blob (meta)"
    cosign sign-blob --yes \
        --bundle "${META}.bundle" \
        --output-signature "${META}.sig" \
        "${META}"

    # cosign attest-blob requires the predicate to be JSON. Use our own
    # predicate-type URI rather than --type slsaprovenance because the
    # install.meta schema isn't slsa-shaped (it's our own provenance
    # tree: upstream npm + git + composition + invocation). The
    # actions/attest-build-provenance step (separate) emits the
    # canonical SLSA provenance from GitHub's perspective.
    #
    # The URI carries no version: it identifies the KIND of document,
    # not its shape (aae-orc-d3nq.13). schema_version travels in-band
    # and is read after verification. Releases cut before 2026-08-01
    # attest under .../install-meta/v0.1.0; a verifier accepts both.
    echo "[build-bmad] cosign attest-blob (sideshow install-meta predicate)"
    cosign attest-blob --yes \
        --predicate "${META_JSON}" \
        --type "https://arcaven.com/sideshow/install-meta" \
        --bundle "${TARBALL}.attest.bundle" \
        "${TARBALL}"
else
    echo "[build-bmad] signing skipped (COSIGN=${COSIGN})"
fi

echo "[build-bmad] done"
ls -la "${OUT_DIR}"
