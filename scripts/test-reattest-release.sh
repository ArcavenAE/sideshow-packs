#!/usr/bin/env bash
# End-to-end test of scripts/reattest-release.sh with gh and cosign replaced by
# stubs on PATH (aae-orc-hti53). No network, no signing. It pins the wiring the
# unit checks cannot: that the job hashes the real downloaded tarball, that it
# signs only after every check passes, and that a failed check uploads nothing.
# Run from anywhere:
#
#   bash scripts/test-reattest-release.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/reattest-release.sh"
ROOT="$(mktemp -d -t reattest-e2e-XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

pass=0
fail=0
check_eq() { # name expected actual
    if [[ "$2" == "$3" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1: expected '$2', got '$3'"
    fi
}
check_has() { # name needle haystack
    if [[ "$3" == *"$2"* ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1: output does not contain '$2': $3"
    fi
}

TAG="demo-v1.0.0"
TARBALL="demo-1.0.0-arcaven.tar.gz"
TYPE="https://arcaven.com/sideshow/install-meta"

mkdir -p "${ROOT}/bin"
cat > "${ROOT}/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: the release lives in $STORE; uploads land in $UPLOADS.
case "$1 $2" in
    "release view")
        if [[ "$*" == *"isDraft"* ]]; then echo false; exit 0; fi
        { ls "${STORE}"; ls "${UPLOADS}"; } 2>/dev/null
        exit 0 ;;
    "release download")
        dir="."
        while [[ $# -gt 0 ]]; do [[ "$1" == "--dir" ]] && dir="$2"; shift; done
        cp "${STORE}"/* "${dir}/"
        exit 0 ;;
    "release upload")
        echo "upload $4" >> "${CALLS}"
        cp "$4" "${UPLOADS}/"
        exit 0 ;;
esac
echo "gh stub: unexpected $*" >&2
exit 1
STUB
cat > "${ROOT}/bin/cosign" <<'STUB'
#!/usr/bin/env bash
# Stub cosign: verify-* succeed unless FAIL_VERIFY_BLOB is set; attest-blob
# writes a new-format bundle for the predicate and blob it was given.
echo "cosign $*" >> "${CALLS}"
case "$1" in
    verify-blob)
        [[ -z "${FAIL_VERIFY_BLOB:-}" ]] || { echo "stub: signature refused" >&2; exit 1; }
        exit 0 ;;
    verify-blob-attestation) exit 0 ;;
    attest-blob)
        shift
        pred="" ; type="" ; out="" ; blob=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --predicate) pred="$2"; shift 2 ;;
                --type) type="$2"; shift 2 ;;
                --bundle) out="$2"; shift 2 ;;
                --yes) shift ;;
                *) blob="$1"; shift ;;
            esac
        done
        python3 -I - "${pred}" "${type}" "${out}" "${blob}" <<'PY'
import base64, hashlib, json, sys
pred, ptype, out, blob = sys.argv[1:5]
sha = hashlib.sha256(open(blob, "rb").read()).hexdigest()
st = {"_type": "https://in-toto.io/Statement/v1", "subject": [{"name": blob, "digest": {"sha256": sha}}],
      "predicateType": ptype, "predicate": json.load(open(pred))}
json.dump({"dsseEnvelope": {"payload": base64.b64encode(json.dumps(st).encode()).decode(),
                            "payloadType": "application/vnd.in-toto+json", "signatures": []}}, open(out, "w"))
PY
        exit 0 ;;
esac
exit 1
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/cosign"

# A release the stubs serve: a small tarball, the two old bundles and the
# install.meta.json. The old bundle's Rekor entry records the payload hash of
# the statement written out longhand here, not built by reattest-check.py.
mkrelease() { # store-dir
    local store="$1"
    mkdir -p "${store}"
    printf 'tarball bytes for the end-to-end test\n' > "${store}/${TARBALL}"
    echo '{}' > "${store}/${TARBALL}.bundle"
    python3 -I - "${store}" "${TARBALL}" "${TYPE}" <<'PY'
import base64, hashlib, json, os, sys
store, name, ptype = sys.argv[1:4]
sha = hashlib.sha256(open(os.path.join(store, name), "rb").read()).hexdigest()
meta = {"schema_version": "0.2.0", "pack": {"name": "demo", "version": "1.0.0"}, "artifact": {"tarball_sha256": sha}}
open(os.path.join(store, "install.meta.json"), "w").write(json.dumps(meta, indent=2) + "\n")
compact = '{"artifact":{"tarball_sha256":"%s"},"pack":{"name":"demo","version":"1.0.0"},"schema_version":"0.2.0"}' % sha
stmt = '{"_type":"https://in-toto.io/Statement/v0.1","predicateType":"%s","subject":[{"name":"%s","digest":{"sha256":"%s"}}],"predicate":%s}' % (ptype, name, sha, compact)
payload_hash = hashlib.sha256(stmt.encode()).hexdigest()
body = base64.b64encode(json.dumps({"kind": "dsse", "spec": {"payloadHash": {"algorithm": "sha256", "value": payload_hash}}}).encode()).decode()
json.dump({"base64Signature": "x", "cert": "y", "rekorBundle": {"Payload": {"body": body}}}, open(os.path.join(store, name + ".attest.bundle"), "w"))
PY
}

run() { # case-name [env assignments...] ; runs the script, sets RC, CASE and per-case dirs
    local name="$1"; shift
    CASE="${ROOT}/${name}"
    mkdir -p "${CASE}/uploads" "${CASE}/tmp"
    : > "${CASE}/calls.log"
    : > "${CASE}/summary.md"
    [[ -d "${CASE}/store" ]] || mkrelease "${CASE}/store"
    env "$@" PATH="${ROOT}/bin:${PATH}" TAG="${TAG}" GITHUB_REPOSITORY="o/r" GH_TOKEN=x \
        STORE="${CASE}/store" UPLOADS="${CASE}/uploads" CALLS="${CASE}/calls.log" \
        GITHUB_STEP_SUMMARY="${CASE}/summary.md" RUNNER_TEMP="${CASE}/tmp" \
        bash "${SCRIPT}" > "${CASE}/out.log" 2>&1
    RC=$?
}
calls() { cat "${CASE}/calls.log"; }

# 1. The happy path. The signed subject is the digest of the real tarball.
run happy
check_eq "happy path succeeds (rc)" "0" "$RC"
check_has "happy path uploads the v2 asset" "upload ${TARBALL}.attest.v2.bundle" "$(calls)"
check_has "happy path signs with the predicate type the old bundle matched" "--type ${TYPE}" "$(calls)"
real="$(shasum -a 256 "${CASE}/store/${TARBALL}" | cut -d' ' -f1)"
got="$(python3 -I - "${CASE}/uploads/${TARBALL}.attest.v2.bundle" <<'PY'
import base64, json, sys
b = json.load(open(sys.argv[1]))
print(json.loads(base64.b64decode(b["dsseEnvelope"]["payload"]))["subject"][0]["digest"]["sha256"])
PY
)"
check_eq "the uploaded bundle's subject is the sha256 of the real tarball" "$real" "$got"

# 2. A tarball whose bytes differ from the digest install.meta.json names:
#    nothing is signed or uploaded.
mkrelease "${ROOT}/tampered/store"
printf 'changed after the release was cut\n' >> "${ROOT}/tampered/store/${TARBALL}"
run tampered
check_eq "a changed tarball stops the run (rc)" "1" "$RC"
check_has "a changed tarball is reported at the payload hash check" "payload hash" "$(cat "${CASE}/summary.md")"
check_eq "a changed tarball signs nothing" "0" "$(calls | grep -c attest-blob)"
check_eq "a changed tarball uploads nothing" "0" "$(find "${CASE}/uploads" -type f | wc -l | tr -d ' ')"

# 3. An edited predicate: the rebuilt statement no longer hashes to the record.
mkrelease "${ROOT}/edited/store"
python3 -I - "${ROOT}/edited/store/install.meta.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); m["schema_version"] = "0.2.1"; json.dump(m, open(sys.argv[1], "w"))
PY
run edited
check_eq "an edited predicate stops the run (rc)" "1" "$RC"
check_eq "an edited predicate signs nothing" "0" "$(calls | grep -c attest-blob)"

# 4. An old signature that does not verify.
run badsig FAIL_VERIFY_BLOB=1
check_eq "a refused old signature stops the run (rc)" "1" "$RC"
check_has "a refused old signature is reported" "old signature" "$(cat "${CASE}/summary.md")"
check_eq "a refused old signature signs nothing" "0" "$(calls | grep -c attest-blob)"

# 5. The asset name is already on the release: nothing is replaced.
mkrelease "${ROOT}/exists/store"
echo '{}' > "${ROOT}/exists/store/${TARBALL}.attest.v2.bundle"
run exists
check_eq "an existing v2 asset stops the run (rc)" "1" "$RC"
check_has "an existing v2 asset is reported" "existing asset" "$(cat "${CASE}/summary.md")"
check_eq "an existing v2 asset uploads nothing" "0" "$(find "${CASE}/uploads" -type f | wc -l | tr -d ' ')"

# 6. A tag that is not a pack-version tag.
TAG="Bad Tag" run badtag
check_eq "a malformed tag stops the run (rc)" "1" "$RC"

echo "passed=${pass} failed=${fail}"
[[ "${fail}" -eq 0 ]] || exit 1
