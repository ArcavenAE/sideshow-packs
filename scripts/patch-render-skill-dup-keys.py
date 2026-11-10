#!/usr/bin/env python3
"""Let render_skill.py accept a short config key defined with equal values.

Upstream scripts/render_skill.py resolves a short config token such as
`{{.implementation_artifacts}}` by searching the whole merged config for every
scalar of that name, and halts when it finds more than one, without looking at
the values. With bmm and gds both installed, each module defines
`implementation_artifacts` and `planning_artifacts` with the same value, so
`bmad-build` and `bmad-build-auto` halt before doing any work. Upstream tracks it
as bmad-code-org/BMAD-METHOD#2718; this pack tracks it as
ArcavenAE/sideshow-packs#65.

Until upstream fixes it, the build makes one narrow edit to the staged copy:
duplicates whose values are equal resolve to the first match, and duplicates
whose values differ still halt with the same message. Nothing else in the file
changes. The edit is an exact-text replacement of one condition, so the
resulting diff against a native install is a few lines and easy to audit.

Remove this step, its tests and its build wiring when upstream lands a fix.

Fail-closed: if render_skill.py is present and the expected upstream text is not
found exactly once (and the file is not already patched), the build stops. That
is the signal to check whether upstream fixed the issue or changed the function,
and to drop or update this step, rather than ship an edit that did not apply.

A pack with no scripts/render_skill.py (releases before the file existed) has
nothing to patch; the record is an empty list.

The record (JSON list) is written for the build to put in install.meta and in
the in-store pack.yaml: file, the sha256 of the upstream bytes, the sha256 of
the patched bytes, the reason, and the upstream issue.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

TARGET = Path("scripts") / "render_skill.py"
PATCH_ID = "render-skill-equal-duplicate-keys"
UPSTREAM_ISSUE = "https://github.com/bmad-code-org/BMAD-METHOD/issues/2718"
MARKER = "sideshow-packs patch render-skill-equal-duplicate-keys"

OLD = (
    "    if len(matches) > 1:\n"
    '        paths = ", ".join(path for path, _ in matches)\n'
    '        raise RenderError(f"ambiguous config value `{key}` found at: {paths}")\n'
)
NEW = (
    f"    # {MARKER}: equal values are one value.\n"
    "    # Remove when upstream fixes BMAD-METHOD#2718.\n"
    "    if len({(type(value), value) for _, value in matches}) > 1:\n"
    '        paths = ", ".join(path for path, _ in matches)\n'
    '        raise RenderError(f"ambiguous config value `{key}` found at: {paths}")\n'
)

REASON = (
    "render_skill.py halts when a short config key matches more than one module "
    "even if every match has the same value, so bmad-build and bmad-build-auto "
    "cannot start where bmm and gds are both installed; equal values now resolve "
    "to one value and unequal values still halt"
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-stage", required=True,
                        help="Staged pack tree (the assembled _bmad content).")
    parser.add_argument("--record", required=True,
                        help="File to write the JSON patch record to.")
    args = parser.parse_args()

    stage = Path(args.pack_stage).resolve()
    if not stage.is_dir():
        sys.stderr.write(f"error: pack stage not found: {stage}\n")
        return 1
    record_path = Path(args.record)
    target = stage / TARGET

    if not target.is_file():
        print(f"[patch] no {TARGET} in the staged tree; nothing to patch")
        record_path.write_text("[]\n", encoding="utf-8")
        return 0

    original = target.read_bytes()
    text = original.decode("utf-8")

    if MARKER in text:
        sys.stderr.write(
            f"error: {TARGET} already carries the patch marker; the staged tree "
            "should hold upstream bytes\n"
        )
        return 1
    if text.count(OLD) != 1:
        sys.stderr.write(
            f"error: expected upstream text found {text.count(OLD)} time(s) in "
            f"{TARGET}, want exactly 1. Check whether upstream fixed "
            "BMAD-METHOD#2718 or changed _resolve_short_config, then drop or "
            "update scripts/patch-render-skill-dup-keys.py\n"
        )
        return 1

    patched = text.replace(OLD, NEW).encode("utf-8")
    target.write_bytes(patched)

    record = [{
        "id": PATCH_ID,
        "file": TARGET.as_posix(),
        "upstream_sha256": sha256_bytes(original),
        "patched_sha256": sha256_bytes(patched),
        "reason": REASON,
        "upstream_issue": UPSTREAM_ISSUE,
        "pack_issue": "https://github.com/ArcavenAE/sideshow-packs/issues/65",
        "removed_when": "upstream fixes the issue",
    }]
    record_path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"[patch] {PATCH_ID}: patched {TARGET} "
          f"({record[0]['upstream_sha256'][:12]} -> {record[0]['patched_sha256'][:12]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
