#!/usr/bin/env bash
# Emit the top-level `identity:` block for the bmad pack.yaml.
#
# The block tells sideshow which keys the pack's runtime reads from the
# human-authored user layer, so sideshow carries no per-pack name for it
# (aae-orc-aht7g, read by aae-orc-213u3). The shape is fixed by the architect
# ruling of 2026-11-10:
#   - `layer` is repo-relative, inside _bmad-custom/, ends in .toml, has no `..`.
#   - `table` is core only.
#   - key names match ^[a-z][a-z0-9_]*$ and are unique.
#   - the `from` vocabulary is closed to three literals: user-name-flag,
#     git-config-user-name, repo-dir-name. `from` is an ordered fallback.
# Stdout is spliced into pack.yaml by build-bmad.sh, at column 0, as a sibling
# of `distribute`.
set -euo pipefail

cat <<'YAML'
identity:
  layer: _bmad-custom/config.user.toml
  table: core
  keys:
    - name: user_name
      from: [user-name-flag, git-config-user-name]
    - name: project_name
      from: [repo-dir-name]
YAML
