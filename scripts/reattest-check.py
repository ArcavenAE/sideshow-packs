#!/usr/bin/env python3
"""Provenance checks for scripts/reattest-release.sh (aae-orc-hti53).

Two subcommands, both offline and stdlib only.

  statement  Rebuild the in-toto statement a published release's original
             build signed, from its install.meta.json, and compare its sha256
             with the payload hash the release's old attestation bundle
             records in its Rekor entry. A match shows the predicate the job
             is about to re-sign is the one that was signed.

  new        Check that a newly written attestation bundle carries the same
             predicate and the same subject digest.

Exit status: 0 the check passed, 1 it did not (the output starts MISMATCH),
2 the input is unusable (the output starts ERROR).
"""
import argparse
import base64
import hashlib
import json
import sys

PREDICATE_TYPES = (
    "https://arcaven.com/sideshow/install-meta",
    "https://arcaven.com/sideshow/install-meta/v0.1.0",
)
STATEMENT_TYPE = "https://in-toto.io/Statement/v0.1"
STATEMENT_TYPES = (STATEMENT_TYPE, "https://in-toto.io/Statement/v1")


def fail(msg):
    print("ERROR " + msg)
    sys.exit(2)


def mismatch(msg):
    print("MISMATCH " + msg)
    sys.exit(1)


def load_json(path):
    try:
        with open(path, "rb") as f:
            return json.loads(f.read())
    except (OSError, ValueError) as e:
        fail("cannot read %s: %s" % (path, e))


def go_json(value):
    """Serialise as Go's encoding/json does for a decoded value: keys sorted,
    compact, and the three HTML characters and U+2028/U+2029 escaped."""
    text = json.dumps(value, separators=(",", ":"), sort_keys=True, ensure_ascii=False)
    for ch, esc in (("<", "\\u003c"), (">", "\\u003e"), ("&", "\\u0026"),
                    (" ", "\\u2028"), (" ", "\\u2029")):
        text = text.replace(ch, esc)
    return text


def statement_bytes(predicate_type, name, sha256, meta):
    # Field order is the order the original attest-blob wrote them in.
    return (
        '{"_type":%s,"predicateType":%s,"subject":[{"name":%s,"digest":{"sha256":%s}}],"predicate":%s}'
        % (go_json(STATEMENT_TYPE), go_json(predicate_type), go_json(name), go_json(sha256), go_json(meta))
    ).encode("utf-8")


def recorded_payload_hash(bundle_path):
    b = load_json(bundle_path)
    try:
        body = base64.b64decode(b["rekorBundle"]["Payload"]["body"])
        entry = json.loads(body)
        value = entry["spec"]["payloadHash"]["value"]
    except (KeyError, TypeError, ValueError) as e:
        fail("no payloadHash in the Rekor entry of %s: %s" % (bundle_path, e))
    if not isinstance(value, str) or len(value) != 64:
        fail("the payloadHash in %s is not a sha256 value" % bundle_path)
    return value


def cmd_statement(a):
    meta = load_json(a.meta)
    recorded = recorded_payload_hash(a.bundle)
    try:
        attested = meta["artifact"]["tarball_sha256"]
    except (KeyError, TypeError):
        fail("%s has no artifact.tarball_sha256" % a.meta)
    if attested != a.sha256:
        mismatch("tarball-digest install.meta.json=%s tarball=%s" % (attested, a.sha256))
    tried = []
    first = None
    for ptype in PREDICATE_TYPES:
        computed = hashlib.sha256(statement_bytes(ptype, a.name, a.sha256, meta)).hexdigest()
        first = first or computed
        tried.append(ptype)
        if computed == recorded:
            print("OK predicate-type=%s payload-hash=%s" % (ptype, recorded))
            return 0
    mismatch("recorded=%s computed=%s tried=%s" % (recorded, first, ",".join(tried)))


def cmd_new(a):
    meta = load_json(a.meta)
    b = load_json(a.bundle)
    try:
        payload = base64.b64decode(b["dsseEnvelope"]["payload"])
        stmt = json.loads(payload)
    except (KeyError, TypeError, ValueError):
        mismatch("no dsseEnvelope payload in %s" % a.bundle)
    if not isinstance(stmt, dict):
        mismatch("the payload is not an in-toto statement")
    if stmt.get("_type") not in STATEMENT_TYPES:
        mismatch("_type %r is not an in-toto statement type this job accepts" % (stmt.get("_type"),))
    if stmt.get("predicateType") not in PREDICATE_TYPES:
        mismatch("predicateType %r is not an install-meta type" % (stmt.get("predicateType"),))
    if stmt.get("predicate") != meta:
        mismatch("predicate differs from install.meta.json")
    subjects = stmt.get("subject")
    if not isinstance(subjects, list) or len(subjects) != 1:
        mismatch("subject must list exactly one artifact, got %r" % (subjects,))
    try:
        got = subjects[0]["digest"]["sha256"]
    except (KeyError, TypeError):
        mismatch("subject has no sha256 digest")
    if got != a.sha256:
        mismatch("subject digest=%s tarball=%s" % (got, a.sha256))
    print("OK predicate and subject digest match")
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("statement")
    s.add_argument("--meta", required=True)
    s.add_argument("--bundle", required=True)
    s.add_argument("--name", required=True)
    s.add_argument("--sha256", required=True)
    n = sub.add_parser("new")
    n.add_argument("--bundle", required=True)
    n.add_argument("--meta", required=True)
    n.add_argument("--sha256", required=True)
    a = p.parse_args()
    return cmd_statement(a) if a.cmd == "statement" else cmd_new(a)


if __name__ == "__main__":
    sys.exit(main())
