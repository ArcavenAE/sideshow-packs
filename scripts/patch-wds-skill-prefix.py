#!/usr/bin/env python3
"""Bind every wds skill and wds global command under the bmad-wds- prefix.

The wds module (bmad-method-wds-expansion) ships its skills under two kinds of
name that land in a shared skills directory: thirteen `wds-*` names and two
bare ones, `memory` and `sync`. The bare ones shadow Claude Code built-in
commands (`/memory` ran the wds state backend instead of the memory editor),
and neither form matches the one-glob-per-prefix convention the rest of the
pack follows. Its `sync` tool also installs six bare global commands (`/saga`,
`/freya`, `/mimir`, `/start`, `/wrap`, `/handoff`) into ~/.claude/commands/.
Upstream tracks the bare names as bmad-method-wds-expansion#38; this pack
tracks the rename as aae-orc-hdwf4.

Upstream's own help catalog (wds/module-help.csv) already names wds skills
`bmad-wds-*`, so that is the prefix. The catalog's names do not map one to one
onto the shipped skills, so the rename is mechanical: a leading `wds-` is
dropped and `bmad-wds-` is prepended (`wds-0-project-setup` becomes
`bmad-wds-0-project-setup`, `memory` becomes `bmad-wds-memory`). The catalog is
left as shipped.

What is rewritten, and nothing else:

  - each wds skill directory under .claude/skills/, and the `name:` line of its
    SKILL.md frontmatter (and of any other top-level .md in it, such as
    workflow.md, whose frontmatter names the skill);
  - its row in _config/skill-manifest.csv, when it has one (canonicalId and
    name; the path column names the module source, which does not move);
  - its `[agents.<name>]` table in config.toml, when present (party-mode and
    forge-idea resolve agents by that key);
  - every `skill:<name>` reference in a text file of the staged tree;
  - in the wds module and the wds skills only: `/<command>` slash references
    and `commands/<command>.md` file names for the six global commands.

Paths into the module (`workflows/wds-1-project-brief/`, `_bmad/wds/tools/
memory/SKILL.md`, `docs/...`) are not skill references and are left alone.

Upstream precedence: a skill whose name already starts with `bmad-wds-` is
left as upstream named it, and when no wds skill needs renaming the step is a
no-op with an empty record entry list. Remove this step when upstream ships
prefixed names.

Which skills are wds's: the manifest's wds rows, every `wds-*` skill
directory, and `memory` or `sync` only when their frontmatter description
names WDS.

Fail-closed: a wds row whose skill directory is missing, a rename target that
already exists, or a SKILL.md whose frontmatter `name:` does not match its row
stops the build.

The record entry is appended to the build's JSON patch record (the list
patch-render-skill-dup-keys.py writes), for install.meta and the in-store
pack.yaml.
"""

import argparse
import csv
import io
import json
import re
import sys
from pathlib import Path

PATCH_ID = "wds-skill-prefix"
PREFIX = "bmad-wds-"
MODULE = "wds"
SKILLS = Path(".claude") / "skills"
SKILL_MANIFEST = Path("_config") / "skill-manifest.csv"
CONFIG_TOML = Path("config.toml")
BARE_TOOLS = ("memory", "sync")
COMMANDS = ("saga", "freya", "mimir", "start", "wrap", "handoff")
TEXT_SUFFIXES = {".md", ".csv", ".toml", ".yaml", ".yml", ".txt", ".json"}
NAME_CHARS = r"[A-Za-z0-9_-]"

REASON = (
    "wds skills ship as wds-* plus the bare names memory and sync, and its sync "
    "tool installs bare global commands; the bare names shadow Claude Code "
    "built-ins and none match the pack's prefix convention, so every wds skill "
    "and command is bound as bmad-wds-*, the prefix upstream's help catalog uses"
)


def new_name(name: str) -> str:
    return PREFIX + (name[len("wds-"):] if name.startswith("wds-") else name)


def manifest_wds_names(stage: Path) -> list[str]:
    manifest = stage / SKILL_MANIFEST
    if not manifest.is_file():
        return []
    with manifest.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return [r["name"] for r in rows if r.get("module") == MODULE]


def is_wds_tool(skill_md: Path) -> bool:
    """A bare memory or sync skill is wds's only when its frontmatter says so."""
    if not skill_md.is_file():
        return False
    m = re.match(r"---\n(.*?)\n---\n", skill_md.read_text(encoding="utf-8"), re.S)
    return bool(m and re.search(r"^description:.*\bWDS\b", m.group(1), re.M))


def wds_skill_names(stage: Path) -> list[str]:
    """The manifest's wds rows, every wds-* skill directory, and the bare wds
    tools. Some releases (6.10.0) ship the wds skills with no wds rows in the
    manifest, so the directories are read as well."""
    skills = stage / SKILLS
    names = set(manifest_wds_names(stage))
    if skills.is_dir():
        names |= {d.name for d in skills.iterdir() if d.is_dir() and d.name.startswith("wds-")}
        names |= {t for t in BARE_TOOLS if is_wds_tool(skills / t / "SKILL.md")}
    return sorted(names)


def rename_frontmatter(skill_md: Path, old: str, new: str, required: bool = True) -> bool:
    text = skill_md.read_text(encoding="utf-8")
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        if required:
            raise SystemExit(f"error: {skill_md} has no frontmatter block")
        return False
    block = m.group(1)
    pattern = re.compile(rf"^name:\s*['\"]?{re.escape(old)}['\"]?\s*$", re.M)
    if len(pattern.findall(block)) != 1:
        if required:
            raise SystemExit(f"error: {skill_md} frontmatter has no single `name: {old}` line")
        return False
    block = pattern.sub(f"name: {new}", block, count=1)
    skill_md.write_text(f"---\n{block}\n---\n" + text[m.end():], encoding="utf-8")
    return True


def rewrite_manifest(stage: Path, renames: dict[str, str], expected: list[str]) -> int:
    manifest = stage / SKILL_MANIFEST
    if not manifest.is_file():
        return 0
    lines = manifest.read_text(encoding="utf-8").splitlines(keepends=True)
    seen = set()
    for i, line in enumerate(lines):
        row = next(csv.reader(io.StringIO(line)), None)
        if not row or len(row) < 2 or row[0] not in renames or row[0] != row[1]:
            continue
        old = row[0]
        head = f'"{old}","{old}",'
        if not line.startswith(head):
            raise SystemExit(f"error: {SKILL_MANIFEST} row for {old} is not in the quoted form")
        lines[i] = f'"{renames[old]}","{renames[old]}",' + line[len(head):]
        seen.add(old)
    missing = set(expected) - seen
    if missing:
        raise SystemExit(f"error: {SKILL_MANIFEST} has no row to rewrite for {sorted(missing)}")
    manifest.write_text("".join(lines), encoding="utf-8")
    return len(seen)


def text_files(root: Path):
    for p in sorted(root.rglob("*")):
        if p.is_file() and not p.is_symlink() and p.suffix in TEXT_SUFFIXES:
            yield p


def sub_file(path: Path, subs: list[tuple[re.Pattern, str]]) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return 0
    count = 0
    for pattern, repl in subs:
        text, n = pattern.subn(repl, text)
        count += n
    if count:
        path.write_text(text, encoding="utf-8")
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-stage", required=True)
    parser.add_argument("--record", required=True,
                        help="JSON patch record to append to (created when absent).")
    args = parser.parse_args()

    stage = Path(args.pack_stage).resolve()
    if not stage.is_dir():
        sys.stderr.write(f"error: pack stage not found: {stage}\n")
        return 1
    record_path = Path(args.record)
    record = json.loads(record_path.read_text(encoding="utf-8")) if record_path.is_file() else []

    names = [n for n in wds_skill_names(stage) if not n.startswith(PREFIX)]
    if not names:
        print("[patch] wds-skill-prefix: no unprefixed wds skill; nothing to rename")
        record_path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        return 0

    renames = {n: new_name(n) for n in names}
    skills = stage / SKILLS
    for old, new in renames.items():
        if not (skills / old / "SKILL.md").is_file():
            sys.stderr.write(f"error: wds skill {old} is in {SKILL_MANIFEST} but {SKILLS / old}/SKILL.md is missing\n")
            return 1
        if (skills / new).exists():
            sys.stderr.write(f"error: rename target {SKILLS / new} already exists\n")
            return 1

    for old, new in renames.items():
        (skills / old).rename(skills / new)
        rename_frontmatter(skills / new / "SKILL.md", old, new)
        # workflow.md and its kin repeat the skill name in their frontmatter.
        for md in sorted((skills / new).glob("*.md")):
            if md.name != "SKILL.md":
                rename_frontmatter(md, old, new, required=False)
    manifest_rows = rewrite_manifest(stage, renames, [n for n in manifest_wds_names(stage) if n in renames])

    agents_renamed = []
    config = stage / CONFIG_TOML
    if config.is_file():
        text = config.read_text(encoding="utf-8")
        for old, new in renames.items():
            text, n = re.subn(rf"^\[agents\.{re.escape(old)}\]$", f"[agents.{new}]", text, flags=re.M)
            if n:
                agents_renamed.append(old)
        config.write_text(text, encoding="utf-8")

    # skill:<name> anywhere in the staged tree.
    skill_subs = [
        (re.compile(rf"\bskill:{re.escape(old)}(?!{NAME_CHARS})"), f"skill:{new}")
        for old, new in renames.items()
    ]
    # The six global commands, only where wds itself names them: the module
    # tree and the renamed wds skills.
    cmd_subs = []
    for cmd in COMMANDS:
        cmd_subs.append((re.compile(rf"(?<![A-Za-z0-9_./{{}}-])/{cmd}(?!{NAME_CHARS})"), f"/{PREFIX}{cmd}"))
        cmd_subs.append((re.compile(rf"\bcommands([/\\]){cmd}\.md\b"), rf"commands\g<1>{PREFIX}{cmd}.md"))

    skill_refs = sum(sub_file(p, skill_subs) for p in text_files(stage))
    cmd_roots = [stage / MODULE] + [skills / new for new in renames.values()]
    cmd_refs = sum(sub_file(p, cmd_subs) for root in cmd_roots if root.is_dir() for p in text_files(root))

    record.append({
        "id": PATCH_ID,
        "renames": renames,
        "commands": {c: PREFIX + c for c in COMMANDS},
        "manifest_rows_rewritten": manifest_rows,
        "agents_tables_renamed": agents_renamed,
        "skill_references_rewritten": skill_refs,
        "command_references_rewritten": cmd_refs,
        "reason": REASON,
        "upstream_issue": "https://github.com/bmad-code-org/bmad-method-wds-expansion/issues/38",
        "pack_issue": "aae-orc-hdwf4",
        "removed_when": "upstream ships prefixed wds skill and command names",
    })
    record_path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"[patch] {PATCH_ID}: renamed {len(renames)} skills, {len(agents_renamed)} agent tables, "
          f"{skill_refs} skill: references, {cmd_refs} command references")
    return 0


if __name__ == "__main__":
    sys.exit(main())
