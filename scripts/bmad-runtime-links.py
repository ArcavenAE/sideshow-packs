#!/usr/bin/env python3
"""Print the pack.yaml `runtime_links` entries for a staged bmad tree.

sideshow links each entry from {project-root}/_bmad/<link> to the store copy,
so an upstream resolver or skill that reads a path under _bmad/ finds it from a
bound repo. The list was a hand list of four (scripts, _config, config.toml,
config.user.toml), which left every module config unresolved: a bound repo
could not read _bmad/wds/config.yaml although native resolves it (F-d,
sideshow-packs#43).

The list is now derived from the installer's own _bmad/ tree: every top-level
directory, minus the two that must not be linked, plus the two top-level
config files when present.

  custom   bridged by sideshow to the repo's own _bmad-custom (custom_bridge)
  render   written at run time; a link into the read-only store would break it

Output is the YAML list body at the indent pack.yaml uses, one entry per line
pair, in a stable order (directories sorted, then the config files).
"""

import argparse
import sys
from pathlib import Path

NOT_LINKED = {"custom", "render"}
CONFIG_FILES = ("config.toml", "config.user.toml")


def links(bmad_dir: Path):
    dirs = sorted(
        p.name for p in bmad_dir.iterdir()
        if p.is_dir() and p.name not in NOT_LINKED and not p.name.startswith(".")
    )
    files = [f for f in CONFIG_FILES if (bmad_dir / f).is_file()]
    return dirs + files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bmad-dir", required=True, help="the installer's _bmad/ directory")
    args = parser.parse_args()
    root = Path(args.bmad_dir)
    if not root.is_dir():
        sys.stderr.write(f"error: not a directory: {root}\n")
        return 1
    names = links(root)
    if "scripts" not in names or "_config" not in names:
        sys.stderr.write("error: the installer tree has no scripts/ or _config/; the layout may have changed\n")
        return 2
    for n in names:
        print(f"    - link: {n}")
        print(f"      target: {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
