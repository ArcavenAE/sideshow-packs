#!/usr/bin/env python3
"""Keep bmad's own census (_config/files-manifest.csv) true for the staged tree.

The upstream installer hashes every file it writes into
_config/files-manifest.csv. The build then edits some of those files (the CI
identity neutralizer, scripts/neutralize-ci-identity.py), so on a clean install
sideshow's store-content-census reports the edited files as changed
(sideshow-packs#41, finding-004). Two subcommands:

  refresh  Re-hash every census row whose file exists in the staged tree and
           replace only the hash of rows that differ, leaving every other byte
           of the CSV alone. Writes a record of each rewrite (path and the
           hash the installer recorded) for the in-store pack.yaml.
  verify   Re-run the census over the staged tree. Any row whose file exists
           and whose hash differs is fatal (exit 2). Rows naming paths that are
           not in this layout are counted, not failed, as sideshow's census does.

An absent census is not an error: older bmad releases may not ship one, and
there is then nothing to refresh or check.

Hash is sha256 hex, the same as sideshow's census (internal/doctor).
"""

import argparse
import csv
import hashlib
import io
import sys
from pathlib import Path

CENSUS = Path("_config") / "files-manifest.csv"
PATH_COL, HASH_COL = 3, 4  # type,name,module,path,hash


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def rows(stage: Path):
    """Yield (line, rel, want) for each data row of the census."""
    census = stage / CENSUS
    with census.open("r", encoding="utf-8", newline="") as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if i == 0:
            yield line, None, None  # header
            continue
        rec = next(csv.reader(io.StringIO(line)), [])
        if len(rec) <= HASH_COL:
            yield line, None, None
            continue
        yield line, rec[PATH_COL], rec[HASH_COL]


def cmd_refresh(args) -> int:
    stage = Path(args.pack_stage).resolve()
    census = stage / CENSUS
    if not census.is_file():
        print(f"[census] no {CENSUS} in the staged tree; nothing to refresh")
        Path(args.record).write_text(record_text(args.rule_version, []), encoding="utf-8")
        return 0
    out, changed = [], []
    for line, rel, want in rows(stage):
        target = stage / rel if rel else None
        if rel and target.is_file():
            got = sha256(target)
            if got != want:
                if line.count(want) != 1:
                    sys.stderr.write(f"error: cannot rewrite the hash for {rel} unambiguously\n")
                    return 1
                line = line.replace(want, got)
                changed.append((rel, want))
        out.append(line)
    if changed:
        census.write_text("".join(out), encoding="utf-8", newline="")
    for rel, old in changed:
        print(f"[census] refreshed {rel} (installer hash {old[:12]})")
    print(f"[census] refreshed {len(changed)} census row(s)")
    Path(args.record).write_text(record_text(args.rule_version, changed), encoding="utf-8")
    return 0


def record_text(rule_version, changed) -> str:
    lines = ["", "rewrites:", f"  neutralizer_rule_version: {rule_version}"]
    if not changed:
        lines.append("  census_refreshed: []")
    else:
        lines.append("  census_refreshed:")
        for rel, old in sorted(changed):
            lines.append(f"    - path: {rel}")
            lines.append(f"      installer_sha256: {old}")
    return "\n".join(lines) + "\n"


def cmd_verify(args) -> int:
    stage = Path(args.pack_stage).resolve()
    if not (stage / CENSUS).is_file():
        print(f"[census] no {CENSUS} in the staged tree; nothing to verify")
        return 0
    verified, unresolved, bad = 0, 0, []
    for _line, rel, want in rows(stage):
        if not rel:
            continue
        target = stage / rel
        if not target.is_file():
            unresolved += 1
        elif sha256(target) == want:
            verified += 1
        else:
            bad.append(rel)
    if bad:
        sys.stderr.write(
            f"error: {len(bad)} of {verified + len(bad)} census entries differ from the "
            f"staged tree (first: {', '.join(bad[:3])})\n"
        )
        return 2
    print(f"[census] verified {verified} census entries ({unresolved} name paths not in this layout)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("refresh")
    r.add_argument("--pack-stage", required=True)
    r.add_argument("--record", required=True, help="file to write the pack.yaml rewrites block to")
    r.add_argument("--rule-version", required=True, help="neutralizer rule version to record")
    r.set_defaults(fn=cmd_refresh)
    v = sub.add_parser("verify")
    v.add_argument("--pack-stage", required=True)
    v.set_defaults(fn=cmd_verify)
    args = parser.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
