#!/usr/bin/env bash
# Tests for scripts/reattest-check.py: the offline provenance checks the
# re-attest job runs before it signs anything (aae-orc-hti53). The fixtures are
# the install.meta.json and the Rekor entry of three published releases: a bmad
# and a vsdd-factory release under the current predicate type, and a bmad release
# under the older /v0.1.0 type, so the byte-level match is shown against real
# signed data.
# No network. Run from anywhere:
#
#   bash scripts/test-reattest-check.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="${HERE}/reattest-check.py"
FIX="${HERE}/fixtures/reattest"
DIR="$(mktemp -d -t reattest-test-XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

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

sha_of() { python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["artifact"]["tarball_sha256"])' "$1/install.meta.json"; }

stmt() { # fixture-dir [meta-override] [sha-override]
    local d="$1" meta="${2:-$1/install.meta.json}" sha="${3:-}"
    [[ -n "$sha" ]] || sha="$(sha_of "$d")"
    python3 -I "${CHECK}" statement --meta "$meta" --bundle "$d/old-rekor-bundle.json" \
        --name "$(cat "$d/tarball-name")" --sha256 "$sha" 2>&1
}

CUR="https://arcaven.com/sideshow/install-meta"
OLD="https://arcaven.com/sideshow/install-meta/v0.1.0"

# 1. Each published release rebuilds to the payload hash its Rekor entry records.
for pair in "bmad-v6.12.4-r3:${CUR}" "vsdd-factory-v1.0.0-rc.24:${CUR}" "bmad-v6.3.0:${OLD}"; do
    tag="${pair%%:*}"
    want="${pair#*:}"
    out="$(stmt "${FIX}/${tag}")"
    rc=$?
    check_eq "${tag}: rebuilt statement matches the recorded payload hash (rc)" "0" "$rc"
    check_has "${tag}: reports the predicate type that matched" "predicate-type=${want} " "${out} "
done

# 2. A changed predicate no longer matches, and the report names both hashes.
R3="${FIX}/bmad-v6.12.4-r3"
python3 -I - "${R3}/install.meta.json" "${DIR}/meta-edited.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
m["schema_version"] = m["schema_version"] + "x"
json.dump(m, open(sys.argv[2], "w"))
PY
out="$(stmt "${R3}" "${DIR}/meta-edited.json")"
rc=$?
check_eq "edited predicate is refused (rc)" "1" "$rc"
check_has "edited predicate reports MISMATCH" "MISMATCH" "$out"
check_has "edited predicate reports the recorded hash" "recorded=e1e5046a88a1c409ffa06d15984be11465a66ba91c04400956bbb3e54ebee9cc" "$out"
check_has "edited predicate reports a computed hash" "computed=" "$out"

# 3. A different tarball digest in the statement no longer matches.
out="$(stmt "${R3}" "${R3}/install.meta.json" "$(printf '0%.0s' {1..64})")"
rc=$?
check_eq "wrong tarball digest is refused (rc)" "1" "$rc"
check_has "wrong tarball digest reports MISMATCH" "MISMATCH" "$out"

# 4. A rekor bundle with no payloadHash is an error, not a pass.
echo '{"rekorBundle":{"Payload":{"body":"e30="}}}' > "${DIR}/empty-rekor.json"
python3 -I "${CHECK}" statement --meta "${R3}/install.meta.json" --bundle "${DIR}/empty-rekor.json" \
    --name "$(cat "${R3}/tarball-name")" --sha256 "$(sha_of "${R3}")" > "${DIR}/out.txt" 2>&1
check_eq "a rekor entry with no payloadHash is refused (rc)" "2" "$?"
check_has "a rekor entry with no payloadHash says ERROR" "ERROR" "$(cat "${DIR}/out.txt")"

# 5. The new bundle must carry the same predicate and subject digest.
mknew() { # outfile meta-path sha
    python3 -I - "$1" "$2" "$3" <<'PY'
import base64, json, sys
out, meta, sha = sys.argv[1:4]
st = {"_type": "https://in-toto.io/Statement/v1", "subject": [{"name": "x", "digest": {"sha256": sha}}],
      "predicateType": "https://arcaven.com/sideshow/install-meta", "predicate": json.load(open(meta))}
env = {"dsseEnvelope": {"payload": base64.b64encode(json.dumps(st).encode()).decode(), "payloadType": "application/vnd.in-toto+json", "signatures": []}}
json.dump(env, open(out, "w"))
PY
}
SHA="$(sha_of "${R3}")"
mknew "${DIR}/new-ok.json" "${R3}/install.meta.json" "${SHA}"
out="$(python3 -I "${CHECK}" new --bundle "${DIR}/new-ok.json" --meta "${R3}/install.meta.json" --sha256 "${SHA}" 2>&1)"
check_eq "new bundle with the same predicate and subject passes (rc)" "0" "$?"
check_has "new bundle pass says OK" "OK" "$out"

mknew "${DIR}/new-badpred.json" "${DIR}/meta-edited.json" "${SHA}"
out="$(python3 -I "${CHECK}" new --bundle "${DIR}/new-badpred.json" --meta "${R3}/install.meta.json" --sha256 "${SHA}" 2>&1)"
check_eq "new bundle with a changed predicate is refused (rc)" "1" "$?"
check_has "changed predicate says MISMATCH predicate" "MISMATCH predicate" "$out"

mknew "${DIR}/new-badsub.json" "${R3}/install.meta.json" "$(printf 'f%.0s' {1..64})"
out="$(python3 -I "${CHECK}" new --bundle "${DIR}/new-badsub.json" --meta "${R3}/install.meta.json" --sha256 "${SHA}" 2>&1)"
check_eq "new bundle with a changed subject digest is refused (rc)" "1" "$?"
check_has "changed subject says MISMATCH subject" "MISMATCH subject" "$out"

# 5b. The statement itself is checked: a foreign predicateType, a wrong _type
# and a second subject are each refused (architect read of 045187c, P1 and P3).
mkstmt() { # outfile variant
    python3 -I - "$1" "$2" "${R3}/install.meta.json" "${SHA}" <<'PY'
import base64, json, sys
out, variant, meta, sha = sys.argv[1:5]
good = {"name": "x", "digest": {"sha256": sha}}
other = {"name": "y", "digest": {"sha256": "f" * 64}}
st = {"_type": "https://in-toto.io/Statement/v1", "subject": [good],
      "predicateType": "https://arcaven.com/sideshow/install-meta", "predicate": json.load(open(meta))}
if variant == "foreign-type":
    st["predicateType"] = "https://example.com/other-predicate"
elif variant == "wrong-statement-type":
    st["_type"] = "https://example.com/Statement/v9"
elif variant == "two-subjects-match-first":
    st["subject"] = [good, other]
elif variant == "two-subjects-match-second":
    st["subject"] = [other, good]
env = {"dsseEnvelope": {"payload": base64.b64encode(json.dumps(st).encode()).decode(), "payloadType": "application/vnd.in-toto+json", "signatures": []}}
json.dump(env, open(out, "w"))
PY
}
for pair in "foreign-type:predicateType" "wrong-statement-type:_type" "two-subjects-match-first:subject" "two-subjects-match-second:subject"; do
    variant="${pair%%:*}"
    field="${pair#*:}"
    mkstmt "${DIR}/new-${variant}.json" "${variant}"
    out="$(python3 -I "${CHECK}" new --bundle "${DIR}/new-${variant}.json" --meta "${R3}/install.meta.json" --sha256 "${SHA}" 2>&1)"
    check_eq "${variant}: refused (rc)" "1" "$?"
    check_has "${variant}: says MISMATCH ${field}" "MISMATCH ${field}" "$out"
done

# 5c. A statement for a different artifact name is a different statement.
out="$(python3 -I "${CHECK}" statement --meta "${R3}/install.meta.json" --bundle "${R3}/old-rekor-bundle.json" \
    --name "other-1.0.0-arcaven.tar.gz" --sha256 "${SHA}" 2>&1)"
check_eq "a wrong --name is refused (rc)" "1" "$?"
check_has "a wrong --name says MISMATCH" "MISMATCH" "$out"

echo '{"base64Signature":"x","cert":"y","rekorBundle":{}}' > "${DIR}/new-legacy.json"
python3 -I "${CHECK}" new --bundle "${DIR}/new-legacy.json" --meta "${R3}/install.meta.json" --sha256 "${SHA}" > "${DIR}/out.txt" 2>&1
check_eq "a bundle with no dsseEnvelope is refused (rc)" "1" "$?"
check_has "a bundle with no dsseEnvelope says MISMATCH" "MISMATCH" "$(cat "${DIR}/out.txt")"

echo "passed=${pass} failed=${fail}"
[[ "${fail}" -eq 0 ]] || exit 1
