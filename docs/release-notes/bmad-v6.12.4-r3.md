<!--
Authoring note: this block is a comment, so GitHub does not show it in the
release body. The two FILL markers below take their values from the signed
release build (artifact size, sha256). Replace them, search the file for FILL,
then attach it as the body of the bmad-v6.12.4-r3 release:

  gh release edit bmad-v6.12.4-r3 -R ArcavenAE/sideshow-packs \
    --notes-file docs/release-notes/bmad-v6.12.4-r3.md
-->
# bmad 6.12.4-r3 release notes

Every wds skill now installs under the `bmad-wds-` prefix, so wds no longer
puts bare `memory` and `sync` skills in a shared skills directory, where
`/memory` ran the wds state backend instead of the Claude Code built-in. The
prefix is the one upstream's own wds help catalog (`wds/module-help.csv`)
already uses.

This is a packaging re-issue of the 6.12.4 composition. The base releases stay
immutable (see docs/release-url-format.md). It also carries the `render_skill.py` patch from `bmad-v6.12.4-r2` (equal duplicate config keys, sideshow-packs#65), unchanged.

**Artifact.** `bmad-6.12.4-r3-arcaven.tar.gz`, FILL-size bytes, sha256
`FILL-digest`.

## The patch

`scripts/patch-wds-skill-prefix.py` renames the 15 wds skills: a leading
`wds-` is dropped and `bmad-wds-` is prepended (`wds-0-project-setup` becomes
`bmad-wds-0-project-setup`, `memory` becomes `bmad-wds-memory`). It rewrites
each skill's frontmatter `name:`, every `skill:<name>` reference, the skill's
manifest row and the three `[agents.*]` tables in `config.toml`. The six global commands the wds sync tool
installs into `~/.claude/commands/` become `/bmad-wds-saga`, `/bmad-wds-freya`,
`/bmad-wds-mimir`, `/bmad-wds-start`, `/bmad-wds-wrap` and
`/bmad-wds-handoff`. Paths into the module (`workflows/wds-*/`,
`_bmad/wds/tools/memory/SKILL.md`) are not renamed.

Upstream's catalog names do not map one to one onto the shipped skills, so the
rename is mechanical and the catalog is left as shipped. Upstream tracks the bare
names as https://github.com/bmad-code-org/bmad-method-wds-expansion/issues/38.
The step is a no-op once upstream ships prefixed names, and is removed then.

`install.meta` and the in-store `pack.yaml` list the rename in `patches`
(id `wds-skill-prefix`, with the full old-to-new map).

## Notes for consumers

- **Run `sideshow commands sync` after install**, so the old `wds-*`,
  `memory` and `sync` bindings are withdrawn and the prefixed ones bound.
- **A `_bmad-custom/` override keyed by an old wds skill name** needs renaming
  to the new name.
- **Commands already synced by wds** (`~/.claude/commands/saga.md` and the
  rest) stay until removed by hand; the next wds activation installs the
  prefixed ones.

## Verify

```sh
gh attestation verify bmad-6.12.4-r3-arcaven.tar.gz --repo ArcavenAE/sideshow-packs
ls .claude/skills | grep -cE '^(wds-|memory$|sync$)'   # expect 0
```
