#!/usr/bin/env bash
# Scenario tests for scripts/patch-render-skill-dup-keys.py.
# Self-contained: a fixture holding the upstream 6.12.4 resolver functions, no
# network. Run from anywhere:
#
#   bash scripts/test-patch-render-skill.sh
#
# CI runs this via .github/workflows/intake-tests.yml.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="${SD}/patch-render-skill-dup-keys.py"
DIR="$(mktemp -d -t render-patch-test-XXXXXX)" || exit 1
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
check() { # name expected-substring output
    if grep -qF -- "$2" <<< "$3"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1: expected to find '$2' in:"
        printf '    %s\n' "$3"
    fi
}
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# The functions below are copied from upstream bmad-method 6.12.4,
# scripts/render_skill.py (RenderError, _require_string, _resolve_config_value,
# _find_config_values, _resolve_short_config), so the patch is tested against
# the text it edits.
make_stage() { # dir
    local s="$1"
    mkdir -p "$s/scripts"
    cat > "$s/scripts/render_skill.py" <<'PY'
from pathlib import Path
from typing import Any


class RenderError(ValueError):
    """Raised when rendering cannot safely publish a snapshot."""


def _require_string(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise RenderError(f"{label} must be a string")
    return value


def _resolve_config_value(value: Any, label: str, project_root: Path) -> str:
    text = _require_string(value, label)
    if "{project-root}" not in text:
        return text
    resolved = text.replace("{project-root}", str(project_root))
    if not Path(resolved).is_absolute():
        raise RenderError(f"{label} must resolve to an absolute path: {resolved}")
    return resolved


def _find_config_values(data: Any, key: str, prefix: str = "") -> list[tuple[str, Any]]:
    matches: list[tuple[str, Any]] = []
    if not isinstance(data, dict):
        return matches
    for name, value in data.items():
        path = f"{prefix}.{name}" if prefix else name
        if name == key and not isinstance(value, (dict, list)):
            matches.append((path, value))
        matches.extend(_find_config_values(value, key, path))
    return matches


def _resolve_short_config(
    central: dict[str, Any], key: str, project_root: Path
) -> tuple[str, str]:
    matches = _find_config_values(central, key)
    if not matches:
        raise RenderError(f"missing config value `{key}`")
    if len(matches) > 1:
        paths = ", ".join(path for path, _ in matches)
        raise RenderError(f"ambiguous config value `{key}` found at: {paths}")
    path, value = matches[0]
    return path, _resolve_config_value(value, f"config.{path}", project_root)
PY
}

# Run _resolve_short_config from a render_skill.py against a config. Prints
# "ok <path> <value>" or "err <message>".
resolve() { # render_skill.py json-config key
    python3 -I - "$1" "$2" "$3" <<'PY'
import importlib.util, json, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("render_skill", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
try:
    path, value = mod._resolve_short_config(json.loads(sys.argv[2]), sys.argv[3], Path("/proj"))
    print("ok", path, value)
except mod.RenderError as e:
    print("err", e)
PY
}

EQUAL='{"modules":{"bmm":{"implementation_artifacts":"{project-root}/out"},"gds":{"implementation_artifacts":"{project-root}/out"}}}'
UNEQUAL='{"modules":{"bmm":{"implementation_artifacts":"{project-root}/a"},"gds":{"implementation_artifacts":"{project-root}/b"}}}'
SINGLE='{"modules":{"bmm":{"implementation_artifacts":"{project-root}/out"}}}'
THREE='{"modules":{"bmm":{"k":"v"},"gds":{"k":"v"},"cis":{"k":"v"}}}'
MIXED='{"modules":{"bmm":{"k":"v"},"gds":{"k":"v"},"cis":{"k":"w"}}}'
TYPES='{"modules":{"bmm":{"k":1},"gds":{"k":true}}}'

S="$DIR/stage"
make_stage "$S"
cp "$S/scripts/render_skill.py" "$DIR/upstream.py"
up_sha="$(sha "$S/scripts/render_skill.py")"

# RED: the unpatched upstream text halts on equal values.
check "unpatched halts on equal values" "err ambiguous config value \`implementation_artifacts\` found at: modules.bmm.implementation_artifacts, modules.gds.implementation_artifacts" \
    "$(resolve "$S/scripts/render_skill.py" "$EQUAL" implementation_artifacts)"

# GREEN: apply the patch.
out="$(python3 "$PATCH" --pack-stage "$S" --record "$DIR/rec.json" 2>&1)"; rc=$?
check_eq "patch exit" "0" "$rc"
check "patch reports the file" "patched scripts/render_skill.py" "$out"

check "equal values resolve to the first match" "ok modules.bmm.implementation_artifacts /proj/out" \
    "$(resolve "$S/scripts/render_skill.py" "$EQUAL" implementation_artifacts)"
check "unequal values still halt" "err ambiguous config value \`implementation_artifacts\` found at: modules.bmm.implementation_artifacts, modules.gds.implementation_artifacts" \
    "$(resolve "$S/scripts/render_skill.py" "$UNEQUAL" implementation_artifacts)"
check "a single match is unchanged" "ok modules.bmm.implementation_artifacts /proj/out" \
    "$(resolve "$S/scripts/render_skill.py" "$SINGLE" implementation_artifacts)"
check "three equal matches resolve" "ok modules.bmm.k v" \
    "$(resolve "$S/scripts/render_skill.py" "$THREE" k)"
check "one differing match of three still halts" "err ambiguous config value \`k\` found at: modules.bmm.k, modules.gds.k, modules.cis.k" \
    "$(resolve "$S/scripts/render_skill.py" "$MIXED" k)"
check "equal-looking values of different types still halt" "err ambiguous config value" \
    "$(resolve "$S/scripts/render_skill.py" "$TYPES" k)"
check "a missing key still reports missing" "err missing config value \`nope\`" \
    "$(resolve "$S/scripts/render_skill.py" "$EQUAL" nope)"

# The edit is small and confined to the one condition.
changed="$(diff "$DIR/upstream.py" "$S/scripts/render_skill.py" | grep -c '^[<>]')"
check_eq "diff against upstream is 1 line out and 3 in" "4" "$changed"
check_eq "marker is present once" "1" "$(grep -c 'sideshow-packs patch render-skill-equal-duplicate-keys' "$S/scripts/render_skill.py")"

# The record carries what install.meta and pack.yaml need.
rec="$(python3 -I -c '
import json, sys
r = json.load(open(sys.argv[1]))
p = r[0]
print(len(r), p["id"], p["file"], p["upstream_sha256"], p["patched_sha256"], p["upstream_issue"], p["removed_when"])
' "$DIR/rec.json")"
new_sha="$(sha "$S/scripts/render_skill.py")"
check_eq "record names the patch and both hashes" \
    "1 render-skill-equal-duplicate-keys scripts/render_skill.py ${up_sha} ${new_sha} https://github.com/bmad-code-org/BMAD-METHOD/issues/2718 upstream fixes the issue" "$rec"

# FAIL-CLOSED: a second run on the patched tree stops and leaves the file alone.
out="$(python3 "$PATCH" --pack-stage "$S" --record "$DIR/rec2.json" 2>&1)"; rc=$?
check_eq "second run exit" "1" "$rc"
check "second run names the marker" "already carries the patch marker" "$out"
check_eq "second run leaves the file alone" "$new_sha" "$(sha "$S/scripts/render_skill.py")"

# FAIL-CLOSED: upstream text that is not there (fixed or changed) stops the build.
S2="$DIR/stage2"; make_stage "$S2"
python3 -I - "$S2/scripts/render_skill.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("if len(matches) > 1:", "if len(set(v for _, v in matches)) > 1:"))
PY
before="$(sha "$S2/scripts/render_skill.py")"
out="$(python3 "$PATCH" --pack-stage "$S2" --record "$DIR/rec3.json" 2>&1)"; rc=$?
check_eq "changed upstream text exit" "1" "$rc"
check "changed upstream text is named" "found 0 time(s)" "$out"
check_eq "changed upstream text leaves the file alone" "$before" "$(sha "$S2/scripts/render_skill.py")"

# FAIL-CLOSED: the expected text twice is ambiguous, not patched.
S3="$DIR/stage3"; make_stage "$S3"
python3 -I - "$S3/scripts/render_skill.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
i = s.index("    if len(matches) > 1:")
j = s.index("    path, value = matches[0]")
open(p, "w").write(s + "\n" + s[i:j])
PY
out="$(python3 "$PATCH" --pack-stage "$S3" --record "$DIR/rec4.json" 2>&1)"; rc=$?
check_eq "duplicated upstream text exit" "1" "$rc"
check "duplicated upstream text is named" "found 2 time(s)" "$out"

# No render_skill.py: nothing to patch, an empty record, exit 0.
S4="$DIR/stage4"; mkdir -p "$S4/bmm"; printf 'a\n' > "$S4/bmm/x.md"
out="$(python3 "$PATCH" --pack-stage "$S4" --record "$DIR/rec5.json" 2>&1)"; rc=$?
check_eq "no render_skill.py exit" "0" "$rc"
check_eq "no render_skill.py record is empty" "[]" "$(tr -d ' \n' < "$DIR/rec5.json")"

# A missing stage is an error.
python3 "$PATCH" --pack-stage "$DIR/none" --record "$DIR/rec6.json" >/dev/null 2>&1; rc=$?
check_eq "missing stage exit" "1" "$rc"

# The build wires the patch after the neutralizer and before the census refresh,
# and carries the record into install.meta and pack.yaml.
has() { grep -qF -- "$1" "${SD}/build-bmad.sh" && echo yes || echo no; }
check_eq "build runs the patch" "yes" "$(has 'patch-render-skill-dup-keys.py"')"
check_eq "build puts the record in install.meta" "yes" "$(has '--argjson patches')"
n_line="$(grep -n 'neutralize-ci-identity.py\" \\' "${SD}/build-bmad.sh" | head -1 | cut -d: -f1)"
p_line="$(grep -n 'patch-render-skill-dup-keys.py\" \\' "${SD}/build-bmad.sh" | head -1 | cut -d: -f1)"
r_line="$(grep -n 'bmad-census.py\" refresh' "${SD}/build-bmad.sh" | head -1 | cut -d: -f1)"
[[ -n "$n_line" && -n "$p_line" && -n "$r_line" && "$n_line" -lt "$p_line" && "$p_line" -lt "$r_line" ]] \
    && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: build order neutralize<patch<census refresh (lines: '$n_line' '$p_line' '$r_line')"; }

echo "render-skill patch tests: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
