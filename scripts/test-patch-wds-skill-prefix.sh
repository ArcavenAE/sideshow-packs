#!/usr/bin/env bash
# Scenario tests for scripts/patch-wds-skill-prefix.py.
# Self-contained: a small fixture shaped like the wds module of bmad 6.10.0 and
# 6.12.4, no network. Run from anywhere:
#
#   bash scripts/test-patch-wds-skill-prefix.sh
#
# CI runs this via .github/workflows/intake-tests.yml.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="${SD}/patch-wds-skill-prefix.py"
DIR="$(mktemp -d -t wds-prefix-test-XXXXXX)" || exit 1
[[ -n "$DIR" && -d "$DIR" ]] || { echo "FATAL: mktemp gave no usable directory" >&2; exit 1; }
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
check() { # name expected-substring haystack
    if grep -qF -- "$2" <<< "$3"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1: '$2' not found in: $3"
    fi
}
skill() { # stage name description [extra-body]
    mkdir -p "$1/.claude/skills/$2"
    printf -- '---\nname: %s\ndescription: %s\n---\n\n%s\n' "$2" "$3" "${4:-}" > "$1/.claude/skills/$2/SKILL.md"
}

# make_stage DIR [with-manifest]: wds skills, a bare WDS memory and sync, a
# non-wds skill, a module tree, config.toml and (optionally) manifest rows.
make_stage() {
    local S="$1"
    mkdir -p "$S/_config" "$S/wds/skills" "$S/wds/data"
    skill "$S" wds-agent-saga-analyst "Strategic analyst for WDS." 'Read `_wds/tools/memory/SKILL.md` and follow `load`.'
    skill "$S" wds-1-project-brief "Project brief." 'See `skill:wds-2-trigger-mapping` and `workflows/wds-1-project-brief/templates/`.'
    printf -- '---\nname: wds-1-project-brief\ndescription: Project brief.\n---\nbody\n' > "$S/.claude/skills/wds-1-project-brief/workflow.md"
    skill "$S" wds-2-trigger-mapping "Trigger mapping." 'Output goes to `docs/wds-2-trigger-mapping/map.md`.'
    skill "$S" memory "Session state backend for WDS. Called by wrap." 'Called by `/wrap`.'
    skill "$S" sync "Syncs WDS skills to ~/.claude/commands/." \
        'Check `{HOME_DIR}/.claude/commands/wrap.md` against `{WDS_SRC}/skills/wrap.md`. Adds /saga /wrap to sessions. Not https://example.com/wrap.'
    skill "$S" bmad-agent-pm "Product manager." 'Uses `skill:bmad-prd`. Run /start for the PM flow.'
    printf '# /wrap: Session Wrap\n\nType /saga to call Saga, via `skill:wds-1-project-brief`.\n' > "$S/wds/skills/wrap.md"
    printf 'See ~/.claude/wds/tools/memory/SKILL.md and docs/start.md.\n' > "$S/wds/data/notes.md"
    printf '[agents.bmad-agent-pm]\nmodule = "bmm"\n\n[agents.wds-agent-saga-analyst]\nmodule = "wds"\n' > "$S/config.toml"
    {
        echo 'canonicalId,name,description,module,path'
        echo '"bmad-agent-pm","bmad-agent-pm","PM","bmm","_bmad/bmm/agents/bmad-agent-pm/SKILL.md"'
        if [[ "${2:-}" == "with-manifest" ]]; then
            echo '"wds-agent-saga-analyst","wds-agent-saga-analyst","Analyst","wds","_bmad/wds/agents/wds-agent-saga-analyst/SKILL.md"'
            echo '"memory","memory","State","wds","_bmad/wds/tools/memory/SKILL.md"'
        fi
    } > "$S/_config/skill-manifest.csv"
}

# 1. The 6.12.4 shape: manifest rows present.
S="$DIR/s1"; make_stage "$S" with-manifest
echo '[{"id":"earlier-patch"}]' > "$DIR/rec1.json"
out="$(python3 -I "$PATCH" --pack-stage "$S" --record "$DIR/rec1.json" 2>&1)"; rc=$?
check_eq "run exit" "0" "$rc"
check "run reports the count" "renamed 5 skills, 1 agent tables" "$out"
check_eq "skill dirs" \
    "bmad-agent-pm bmad-wds-1-project-brief bmad-wds-2-trigger-mapping bmad-wds-agent-saga-analyst bmad-wds-memory bmad-wds-sync" \
    "$(ls "$S/.claude/skills" | sort | tr '\n' ' ' | sed 's/ $//')"
check_eq "SKILL.md name" "name: bmad-wds-memory" "$(sed -n 2p "$S/.claude/skills/bmad-wds-memory/SKILL.md")"
check_eq "workflow.md name" "name: bmad-wds-1-project-brief" "$(sed -n 2p "$S/.claude/skills/bmad-wds-1-project-brief/workflow.md")"
check "skill: reference rewritten" 'skill:bmad-wds-2-trigger-mapping' "$(cat "$S/.claude/skills/bmad-wds-1-project-brief/SKILL.md")"
check "module path left alone" 'workflows/wds-1-project-brief/templates/' "$(cat "$S/.claude/skills/bmad-wds-1-project-brief/SKILL.md")"
check "docs path left alone" 'docs/wds-2-trigger-mapping/map.md' "$(cat "$S/.claude/skills/bmad-wds-2-trigger-mapping/SKILL.md")"
check "tool path left alone" '_wds/tools/memory/SKILL.md' "$(cat "$S/.claude/skills/bmad-wds-agent-saga-analyst/SKILL.md")"
check "non-wds skill: left alone" 'skill:bmad-prd' "$(cat "$S/.claude/skills/bmad-agent-pm/SKILL.md")"
check "non-wds /start left alone" 'Run /start for the PM flow.' "$(cat "$S/.claude/skills/bmad-agent-pm/SKILL.md")"
sync="$(cat "$S/.claude/skills/bmad-wds-sync/SKILL.md")"
check "sync destination renamed" 'commands/bmad-wds-wrap.md' "$sync"
check "sync source left alone" '{WDS_SRC}/skills/wrap.md' "$sync"
check "sync slash commands renamed" 'Adds /bmad-wds-saga /bmad-wds-wrap' "$sync"
check "URL left alone" 'https://example.com/wrap' "$sync"
check "wds skill's /wrap renamed" 'Called by `/bmad-wds-wrap`.' "$(cat "$S/.claude/skills/bmad-wds-memory/SKILL.md")"
mod="$(cat "$S/wds/skills/wrap.md")"
check "module heading renamed" '# /bmad-wds-wrap: Session Wrap' "$mod"
check "module /saga renamed" 'Type /bmad-wds-saga' "$mod"
check "module skill: renamed" 'skill:bmad-wds-1-project-brief' "$mod"
check "module data paths left alone" 'See ~/.claude/wds/tools/memory/SKILL.md and docs/start.md.' "$(cat "$S/wds/data/notes.md")"
cfg="$(cat "$S/config.toml")"
check "agents table renamed" '[agents.bmad-wds-agent-saga-analyst]' "$cfg"
check "other agents table left alone" '[agents.bmad-agent-pm]' "$cfg"
man="$(cat "$S/_config/skill-manifest.csv")"
check "manifest row renamed" '"bmad-wds-memory","bmad-wds-memory","State","wds","_bmad/wds/tools/memory/SKILL.md"' "$man"
check "manifest non-wds row left alone" '"bmad-agent-pm","bmad-agent-pm"' "$man"
rec="$(python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(len(r), r[0]["id"], r[1]["id"], r[1]["renames"]["memory"], r[1]["manifest_rows_rewritten"])' "$DIR/rec1.json")"
check_eq "record appended" "2 earlier-patch wds-skill-prefix bmad-wds-memory 2" "$rec"

# 2. Upstream precedence: a second run on the renamed tree is a no-op.
out="$(python3 -I "$PATCH" --pack-stage "$S" --record "$DIR/rec2.json" 2>&1)"; rc=$?
check_eq "rerun exit" "0" "$rc"
check "rerun is a no-op" "nothing to rename" "$out"
check_eq "rerun record empty" "[]" "$(tr -d ' \n' < "$DIR/rec2.json")"

# 3. The 6.10.0 shape: no wds rows in the manifest, the directories are read.
S="$DIR/s3"; make_stage "$S"
out="$(python3 -I "$PATCH" --pack-stage "$S" --record "$DIR/rec3.json" 2>&1)"; rc=$?
check_eq "no-manifest-rows exit" "0" "$rc"
check "no-manifest-rows renames from the directories" "renamed 5 skills" "$out"
check_eq "no-manifest-rows manifest untouched" "2" "$(wc -l < "$S/_config/skill-manifest.csv" | tr -d ' ')"

# 4. A bare memory that is not wds's is left alone.
S="$DIR/s4"; make_stage "$S"
skill "$S" memory "Someone else's notes skill." ''
out="$(python3 -I "$PATCH" --pack-stage "$S" --record "$DIR/rec4.json" 2>&1)"; rc=$?
check_eq "foreign memory exit" "0" "$rc"
check_eq "foreign memory kept its name" "memory" "$(ls -d "$S/.claude/skills/memory" 2>/dev/null | xargs basename)"

# 5. FAIL-CLOSED: a rename target that already exists stops the build.
S="$DIR/s5"; make_stage "$S"
skill "$S" bmad-wds-memory "Already here." ''
out="$(python3 -I "$PATCH" --pack-stage "$S" --record "$DIR/rec5.json" 2>&1)"; rc=$?
check_eq "collision exit" "1" "$rc"
check "collision named" "already exists" "$out"
check_eq "collision renamed nothing" "yes" "$([[ -d "$S/.claude/skills/wds-1-project-brief" ]] && echo yes)"

# 6. FAIL-CLOSED: a manifest wds row with no skill directory stops the build.
S="$DIR/s6"; make_stage "$S" with-manifest
rm -rf "$S/.claude/skills/wds-agent-saga-analyst"
out="$(python3 -I "$PATCH" --pack-stage "$S" --record "$DIR/rec6.json" 2>&1)"; rc=$?
check_eq "missing dir exit" "1" "$rc"
check "missing dir named" "SKILL.md is missing" "$out"

echo "patch-wds-skill-prefix: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
