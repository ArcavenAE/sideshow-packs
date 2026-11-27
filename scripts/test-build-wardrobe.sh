#!/usr/bin/env bash
# Scenario tests for build-wardrobe.sh and the workflow wiring for wardrobe
# (SP1, design docs/design/2026-11-19-i626-vendor-packs-as-marvel-teams.md,
# section 4.6). Self-contained: a local fixture repo stands in for wardrobe,
# no network. Run from anywhere:
#
#   bash scripts/test-build-wardrobe.sh
#
# Needs git, jq and yq. The fixture's scripts/pack.sh imitates the real
# wardrobe pack.sh output layout (company.toml, roles/, contents/, scripts/,
# pack.yaml); the real one is never run here.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SD}/.." && pwd)"
BUILD="${SD}/build-wardrobe.sh"
WF="${ROOT}/.github/workflows/build-pack.yml"
DIR="$(mktemp -d -t build-wardrobe-test-XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

pass=0
fail=0
check_eq() { # name expected actual
    if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else
        fail=$((fail + 1)); echo "FAIL: $1: expected '$2', got '$3'"; fi
}
check() { # name needle haystack
    if grep -qF -- "$2" <<<"$3"; then pass=$((pass + 1)); else
        fail=$((fail + 1)); echo "FAIL: $1: '$2' not in output"; echo "$3" | sed 's/^/    /'; fi
}

# make_fixture <dir> <pack.yaml version> <tag version>: a git repo laid out
# like wardrobe, tagged wardrobe-v<tag version>.
make_fixture() {
    local d="$1" pv="$2" tv="$3"
    mkdir -p "$d/company/roles" "$d/contents/roles" "$d/scripts"
    printf 'schema_version: 1\nname: wardrobe\nversion: %s\ncontents: contents/\ninstall:\n  layout: release\n' "$pv" > "$d/pack.yaml"
    printf 'name = "wardrobe"\n[source]\ncontents_tree = "abc123"\n' > "$d/company/company.toml"
    printf 'role: builder\n' > "$d/company/roles/builder.yaml"
    printf 'index: []\n' > "$d/contents/index.yaml"
    printf 'role: architect\n' > "$d/contents/roles/architect.yaml"
    printf '#!/usr/bin/env bash\n# sourced helpers\n' > "$d/scripts/lib.sh"
    cat > "$d/scripts/pack.sh" <<'PACK'
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:?usage: pack.sh <out-dir>}"
mkdir -p "$out"
cp -R "$here/contents" "$out/contents"
cp -R "$here/scripts" "$out/scripts"
cp -R "$here/company/roles" "$out/roles"
cp "$here/pack.yaml" "$out/pack.yaml"
v="$(yq -r '.version' "$here/pack.yaml")"
awk -v v="$v" '{print} /^name = / && !d {print "version = \"" v "\""; d=1}' "$here/company/company.toml" > "$out/company.toml"
PACK
    chmod 755 "$d/scripts/pack.sh"
    (
        cd "$d" || exit 1
        git init -q -b main
        git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false add -A
        git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m fixture
        git -c user.name=t -c user.email=t@example.invalid -c tag.gpgsign=false tag "wardrobe-v${tv}"
    )
}

# 1. The workflow routes a wardrobe tag and dispatch to the wardrobe build.
wf="$(cat "${WF}")"
check "T1a tag push trigger lists wardrobe-v*" "'wardrobe-v*'" "${wf}"
check "T1b dispatch pack options include wardrobe" "options: [bmad, vsdd-factory, wardrobe]" "${wf}"
check "T1c build step has a wardrobe arm" "bash scripts/build-wardrobe.sh" "${wf}"

# 2. A fixture build emits the tarball and its sidecars.
mkdir -p "${DIR}/fx"
FX="$(cd "${DIR}/fx" && pwd -P)"   # canonical, so src_override compares as recorded
make_fixture "${FX}" 0.3.0 0.3.0
OUT="${DIR}/out"
log="$(WARDROBE_VERSION=0.3.0 WARDROBE_SRC="${FX}" OUT_DIR="${OUT}" bash "${BUILD}" 2>&1)"
rc=$?
check_eq "T2a build exits 0" "0" "${rc}"
TB="${OUT}/wardrobe-0.3.0-arcaven.tar.gz"
check_eq "T2b tarball exists" "yes" "$([[ -f "${TB}" ]] && echo yes || echo no)"
for f in install.meta.yaml file-manifest.csv exec-manifest.txt; do
    check_eq "T2c ${f} exists" "yes" "$([[ -f "${OUT}/${f}" ]] && echo yes || echo no)"
done

# 3. The tarball carries what both readers need.
X="${DIR}/x"
mkdir -p "${X}"
tar -C "${X}" -xzf "${TB}" 2>/dev/null
R="${X}/wardrobe-0.3.0"
for p in company.toml roles contents scripts pack.yaml file-manifest.csv exec-manifest.txt; do
    check_eq "T3a tarball has ${p}" "yes" "$([[ -e "${R}/${p}" ]] && echo yes || echo no)"
done
check_eq "T3b company.toml carries the version" "0.3.0" \
    "$(yq -p toml -o json '.version' "${R}/company.toml" 2>/dev/null | tr -d '"')"
check_eq "T3c no .git in the pack" "no" "$([[ -e "${R}/.git" ]] && echo yes || echo no)"
check "T3d exec-manifest lists scripts/pack.sh" "scripts/pack.sh" "$(cat "${R}/exec-manifest.txt" 2>/dev/null)"

# 4. install.meta.yaml binds the artifact and the source commit.
M="${OUT}/install.meta.yaml"
sha() { # a missing file yields a marker, never "", so an unbuilt output cannot match an empty field
    [[ -f "$1" ]] || { echo "<missing:$(basename "$1")>"; return; }
    if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
check_eq "T4a pack.name" "wardrobe" "$(yq '.pack.name' "${M}" 2>/dev/null)"
check_eq "T4b pack.version" "0.3.0" "$(yq '.pack.version' "${M}" 2>/dev/null)"
check_eq "T4c upstream.tag" "wardrobe-v0.3.0" "$(yq '.upstream.tag' "${M}" 2>/dev/null)"
check_eq "T4d upstream.commit_sha is the fixture commit" "$(git -C "${FX}" rev-parse HEAD)" \
    "$(yq '.upstream.commit_sha' "${M}" 2>/dev/null)"
check_eq "T4e artifact.tarball_sha256" "$(sha "${TB}")" "$(yq '.artifact.tarball_sha256' "${M}" 2>/dev/null)"
check_eq "T4f artifact.file_manifest_sha256" "$(sha "${OUT}/file-manifest.csv")" \
    "$(yq '.artifact.file_manifest_sha256' "${M}" 2>/dev/null)"
check_eq "T4g artifact.exec_manifest_sha256" "$(sha "${OUT}/exec-manifest.txt")" \
    "$(yq '.artifact.exec_manifest_sha256' "${M}" 2>/dev/null)"
check_eq "T4h a non-canonical src is recorded as src_override" "${FX}" "$(yq '.upstream.src_override' "${M}" 2>/dev/null)"

# 5. Refusals.
FX2="${DIR}/fx-mismatch"
make_fixture "${FX2}" 0.2.0 0.3.0
out="$(WARDROBE_VERSION=0.3.0 WARDROBE_SRC="${FX2}" OUT_DIR="${DIR}/out2" bash "${BUILD}" 2>&1)"
rc=$?
check_eq "T5a pack.yaml version != tag version exits 1" "1" "${rc}"
check "T5b names the pack.yaml version" "0.2.0" "${out}"
check "T5b2 names the requested version" "0.3.0" "${out}"
check_eq "T5c no tarball after a mismatch" "no" "$([[ -e "${DIR}/out2/wardrobe-0.3.0-arcaven.tar.gz" ]] && echo yes || echo no)"

out="$(WARDROBE_VERSION=9.9.9 WARDROBE_SRC="${FX}" OUT_DIR="${DIR}/out3" bash "${BUILD}" 2>&1)"
rc=$?
check_eq "T5d a missing tag exits 1" "1" "${rc}"
check "T5e names the missing tag" "wardrobe-v9.9.9" "${out}"

# 6. Signing needs a commit pin (review of #80): a tag push passes no pin, so a
#    signing build with none would notarize whatever the tag names right now.
out="$(COSIGN=1 WARDROBE_VERSION=0.3.0 WARDROBE_SRC="${FX}" OUT_DIR="${DIR}/out4" bash "${BUILD}" 2>&1)"
rc=$?
check_eq "T6a COSIGN=1 with no pin exits 1" "1" "${rc}"
check "T6b names the missing pin" "no upstream SHA pin" "${out}"
check_eq "T6c no tarball from a refused signing build" "no" "$([[ -e "${DIR}/out4/wardrobe-0.3.0-arcaven.tar.gz" ]] && echo yes || echo no)"

out="$(COSIGN=1 EXPECTED_UPSTREAM_SHA="$(git -C "${FX}" rev-parse HEAD)" WARDROBE_VERSION=0.3.0 WARDROBE_SRC="${FX}" OUT_DIR="${DIR}/out5" bash "${BUILD}" 2>&1)"
rc=$?
check_eq "T6d COSIGN=1 with a non-canonical src exits 1" "1" "${rc}"
check "T6e names the non-canonical src" "non-canonical" "${out}"

out="$(EXPECTED_UPSTREAM_SHA=0000000000000000000000000000000000000000 WARDROBE_VERSION=0.3.0 WARDROBE_SRC="${FX}" OUT_DIR="${DIR}/out6" bash "${BUILD}" 2>&1)"
rc=$?
check_eq "T6f a pin that does not match exits 1" "1" "${rc}"
check "T6g names the provenance mismatch" "provenance mismatch" "${out}"

# 6h. With no env pin the register supplies it (same fallback as vsdd-factory).
REG="${DIR}/register.yaml"
printf 'validated:\n  - min: "0.3.0"\n    max: "0.3.0"\n    upstream_commit: "%s"\n' "$(git -C "${FX}" rev-parse HEAD)" > "${REG}"
out="$(COSIGN=1 WARDROBE_REGISTER="${REG}" WARDROBE_VERSION=0.3.0 WARDROBE_SRC="${FX}" OUT_DIR="${DIR}/out7" bash "${BUILD}" 2>&1)"
check "T6h the pin comes from the register" "SHA pin from register" "${out}"

echo "${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
