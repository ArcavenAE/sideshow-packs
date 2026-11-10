#!/usr/bin/env bash
# Scenario tests for scripts/bmad-identity-block.sh and its use in
# build-bmad.sh. Self-contained, no network. Run from anywhere:
#
#   bash scripts/test-bmad-identity-block.sh
#
# CI runs this via .github/workflows/intake-tests.yml.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="${SD}/bmad-identity-block.sh"
BUILD="${SD}/build-bmad.sh"

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

EXPECT='identity:
  layer: _bmad-custom/config.user.toml
  table: core
  keys:
    - name: user_name
      from: [user-name-flag, git-config-user-name]
    - name: project_name
      from: [repo-dir-name]'

out="$(bash "$EMIT" 2>&1)"; rc=$?
check_eq "emitter exit" "0" "$rc"
check_eq "emitted block is exactly the ruled YAML" "$EXPECT" "$out"

# Top level, a sibling of distribute: no indent on the opening key.
check_eq "identity: starts in column 0" "identity:" "$(head -n1 <<< "$out")"

# Key names match ^[a-z][a-z0-9_]*$ and are unique.
names="$(sed -n 's/^    - name: //p' <<< "$out")"
check_eq "every key name is well formed" "0" "$(grep -cvE '^[a-z][a-z0-9_]*$' <<< "$names")"
check_eq "key names are unique" "$(wc -l <<< "$names" | tr -d ' ')" "$(sort -u <<< "$names" | wc -l | tr -d ' ')"

# The `from` vocabulary is closed to three literals.
tokens="$(sed -n 's/^      from: \[\(.*\)\]$/\1/p' <<< "$out" | tr ',' '\n' | tr -d ' ')"
check_eq "from tokens stay in the closed vocabulary" "0" \
    "$(grep -cvxE 'user-name-flag|git-config-user-name|repo-dir-name' <<< "$tokens")"

# table is core only; layer is repo-relative, inside _bmad-custom/, ends .toml, no `..`.
check_eq "table is core" "  table: core" "$(grep '^  table:' <<< "$out")"
layer="$(sed -n 's/^  layer: //p' <<< "$out")"
case "$layer" in
    /*|*..*) check_eq "layer is relative with no .." "ok" "bad: $layer" ;;
    _bmad-custom/*.toml) check_eq "layer is under _bmad-custom/ and ends .toml" "ok" "ok" ;;
    *) check_eq "layer is under _bmad-custom/ and ends .toml" "ok" "bad: $layer" ;;
esac

# The emitter is used by the build, and the schema_version record moved to 0.3.0.
check_eq "build calls the emitter" "1" "$(grep -c 'bmad-identity-block.sh' "$BUILD")"
check_eq "build records schema_version 0.3.0" "1" "$(grep -c '^schema_version: 0.3.0$' "$BUILD")"
check_eq "build no longer records schema_version 0.2.0" "0" "$(grep -c '^schema_version: 0.2.0$' "$BUILD")"

# verify-artifact.sh reads pack.yaml schema_version when a composition block is
# present. Published 0.2.0 packs are immutable and must keep verifying, and the
# new shape must verify too.
VERIFY="${SD}/verify-artifact.sh"
check_eq "verify-artifact accepts schema_version 0.2.0 (published packs)" "1" "$(grep -c 'PSV}" == "0.2.0"' "$VERIFY")"
check_eq "verify-artifact accepts schema_version 0.3.0 (identity block)" "1" "$(grep -c 'PSV}" == "0.3.0"' "$VERIFY")"

# Spliced into a pack.yaml shape, identity is a top-level sibling of distribute.
doc="$(printf 'name: bmad\nschema_version: 0.3.0\n\ndistribute:\n  gitignore:\n    - /_bmad/\n\n%s\n' "$out")"
if [[ "$rc" -eq 0 ]] && python3 -c 'import yaml' 2>/dev/null; then
    top="$(python3 -c 'import sys,yaml; print(",".join(sorted(yaml.safe_load(sys.stdin))))' <<< "$doc")"
    check_eq "identity is a top-level key beside distribute" "distribute,identity,name,schema_version" "$top"
fi

echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
