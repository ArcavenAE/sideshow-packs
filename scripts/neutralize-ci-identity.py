#!/usr/bin/env python3
"""Neutralize CI-build identity leaked into bmad installer-managed config.

The frozen-composition build runs the upstream installer non-interactively
with build-environment answers: --user-name (a CI sentinel) and the working
directory name (which the installer records as project_name). Those answers
are install-time personal and project state, not pack content, but the
installer writes them into config.user.toml, config.toml, and every module
config.yaml. From there they ship to every consumer, and the resolver serves
them inside real repos. See aae-orc-988gh (user_name) and aae-orc-m79qn
(project_name).

This step removes those two keys from the staged tree after the installer runs
and before packaging, so the pack carries no build identity. The four-file
customization chain (config.user.toml then custom/config.user.toml) is where a
consumer sets their own identity; an absent key resolves to absent, which a
consumer override then supersedes. Verified against scripts/resolve_config.py:
a missing dotted key is omitted from the merged output and the resolver exits
0, so omission never crashes and never substitutes a wrong value.

Removal is line-based on purpose. A TOML or YAML round-trip would reformat the
file and produce a large spurious diff against a native install; the pack's
value is that its divergence from a native install is small and auditable, so
only the identity assignment lines are dropped and every comment, blank line,
and other key is left byte-for-byte intact.

Fail-closed: after scrubbing, any residual sentinel value anywhere in the tree,
or any remaining user_name / project_name assignment in a scrubbed config file,
is a fatal error, so a silent miss cannot ship.
"""

import argparse
import re
import sys
from pathlib import Path

# Version of the scrub rule, recorded in the in-store pack.yaml next to the
# census rows the build refreshed. Bump it when the rule changes what it
# rewrites. `--rule-version` prints it so build-bmad.sh does not copy it.
NEUTRALIZER_RULE_VERSION = 1

# Config files the installer writes identity answers into. Matched by exact
# base name anywhere in the staged tree (top-level config.toml /
# config.user.toml plus every module's config.yaml).
CONFIG_BASENAMES = {"config.toml", "config.user.toml", "config.yaml"}

# Keys that carry install-answer identity. A line is an assignment when the key
# is followed by ':' (YAML) or '=' (TOML), allowing leading whitespace.
IDENTITY_KEYS = ("user_name", "project_name")
ASSIGN_RE = re.compile(r"^\s*(" + "|".join(IDENTITY_KEYS) + r")\s*[:=]")


def scrub_file(path: Path):
    """Drop identity assignment lines from one file. Returns removed lines."""
    original = path.read_text(encoding="utf-8")
    kept, removed = [], []
    # Preserve the trailing-newline shape: splitlines(keepends=True) keeps each
    # line's own terminator, so rejoining is byte-exact for the kept lines.
    for line in original.splitlines(keepends=True):
        if ASSIGN_RE.match(line):
            removed.append(line.rstrip("\n"))
        else:
            kept.append(line)
    if removed:
        path.write_text("".join(kept), encoding="utf-8")
    return removed


def main():
    if "--rule-version" in sys.argv[1:]:
        print(NEUTRALIZER_RULE_VERSION)
        return 0
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pack-stage", required=True,
        help="Staged pack tree to scrub (the assembled _bmad content).",
    )
    parser.add_argument(
        "--sentinel-user", required=True,
        help="The --user-name value passed to the installer; its literal "
             "presence anywhere in the tree after scrubbing is a fatal error.",
    )
    args = parser.parse_args()

    stage = Path(args.pack_stage).resolve()
    if not stage.is_dir():
        sys.stderr.write(f"error: pack stage not found: {stage}\n")
        return 1

    config_files = sorted(
        p for p in stage.rglob("*") if p.is_file() and p.name in CONFIG_BASENAMES
    )
    if not config_files:
        sys.stderr.write(
            f"error: no config files ({', '.join(sorted(CONFIG_BASENAMES))}) "
            f"under {stage}; the installer layout may have changed\n"
        )
        return 1

    total_removed = 0
    for path in config_files:
        for line in scrub_file(path):
            rel = path.relative_to(stage)
            print(f"[neutralize] {rel}: dropped {line.strip()}")
            total_removed += 1
    print(f"[neutralize] removed {total_removed} identity assignment line(s) "
          f"across {len(config_files)} config file(s)")

    # Verification gate 1: the CI user sentinel must appear nowhere in the tree.
    # The sentinel is a value we control and never legitimate pack content, so
    # any occurrence is a leak the line scrub failed to catch.
    sentinel_hits = []
    for path in stage.rglob("*"):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue  # binary or unreadable: cannot carry the text sentinel
        if args.sentinel_user in text:
            sentinel_hits.append(path.relative_to(stage))
    if sentinel_hits:
        sys.stderr.write(
            f"error: sentinel user '{args.sentinel_user}' still present after "
            f"scrub in: {', '.join(str(p) for p in sentinel_hits)}\n"
        )
        return 2

    # Verification gate 2: no identity assignment survives in any config file.
    residual = []
    for path in config_files:
        for line in path.read_text(encoding="utf-8").splitlines():
            if ASSIGN_RE.match(line):
                residual.append(f"{path.relative_to(stage)}: {line.strip()}")
    if residual:
        sys.stderr.write(
            "error: identity assignment survived scrub:\n  "
            + "\n  ".join(residual) + "\n"
        )
        return 2

    print("[neutralize] verified: no CI identity remains in staged config")
    return 0


if __name__ == "__main__":
    sys.exit(main())
