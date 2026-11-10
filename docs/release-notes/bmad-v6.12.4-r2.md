<!--
Authoring note: this block is a comment, so GitHub does not show it in the
release body. The two FILL markers below take their values from the signed
release build (artifact size, sha256, file count). Replace them, search the file
for FILL, then attach it as the body of the bmad-v6.12.4-r2 draft release:

  gh release edit bmad-v6.12.4-r2 -R ArcavenAE/sideshow-packs \
    --notes-file docs/release-notes/bmad-v6.12.4-r2.md

The render results in this file come from the patched script run against the
extracted 6.12.4 tree in a scratch repo, not from the signed release build.
Re-run them against the r2 asset before attaching.
-->
# bmad 6.12.4-r2 release notes

`bmad-build` and `bmad-build-auto` start again in a repo that has both bmm and
gds installed. In 6.12.4 both stop before doing any work, with the first of
these two lines (`bmad-build-auto` fails on the second key):

```text
HALT: ambiguous config value `implementation_artifacts` found at: modules.bmm.implementation_artifacts, modules.gds.implementation_artifacts
HALT: ambiguous config value `planning_artifacts` found at: modules.bmm.planning_artifacts, modules.gds.planning_artifacts
```

This is a packaging re-issue. The upstream content is the 6.12.4 composition of
the base release, and one script differs by one condition. The base
`bmad-v6.12.4` release stays immutable (see
https://github.com/ArcavenAE/sideshow-packs/blob/main/docs/release-url-format.md).

**Artifact.** `bmad-6.12.4-r2-arcaven.tar.gz`, FILL-size bytes, sha256
`FILL-digest`.

## The patch

This pack carries one build-time edit to upstream bytes. `scripts/render_skill.py`
resolves a short config key by collecting every module that defines it and
stopping when there is more than one, without comparing the values. In the
default composition `bmm` and `gds` define `implementation_artifacts` and
`planning_artifacts` with the same value, so the resolver stops. Upstream tracks
it as https://github.com/bmad-code-org/BMAD-METHOD/issues/2718 and this pack as
https://github.com/ArcavenAE/sideshow-packs/issues/65.

The edit changes one condition. Matches whose values are equal resolve to the
first match, as if the key were defined once. Matches whose values differ still
stop with the same message. Nothing else in the file changes; the diff against
the upstream file is one line out and three lines in (two of them a comment).

- Upstream `scripts/render_skill.py` sha256:
  `8496d0d8b449d64c21b42a9aab3b13fc8a813a430c0695ffd84ad75bb1da7942`
- Patched sha256:
  `c5abda6f78ed46da5af3382bb520bd1c2e3e4081651adb64c5c5013b5d078f39`
- Upstream issue: https://github.com/bmad-code-org/BMAD-METHOD/issues/2718

`install.meta` lists the patch in a new `patches` list (`schema_version` 0.1.4,
additive), and the in-store `pack.yaml` carries the same record. An empty list
would mean the pack ships upstream bytes. The census row for the file
(`_config/files-manifest.csv`) is refreshed with the patched hash, and the
installer's hash is kept in the `rewrites` record of `pack.yaml`.

**The patch is removed once upstream fixes the issue.** The build stops if the
expected upstream text is not found exactly once, so a fix or a change upstream
cannot be missed: the step is dropped or updated by hand.

## What was checked

Run against the extracted 6.12.4 tree in a scratch repo (test build, not the
signed release build), with the render command the skills run:

```sh
uv run --no-cache _bmad/scripts/render_skill.py --project-root <repo> --skill ~/.claude/skills/bmad-build
```

- Unpatched: exit 1 and the first HALT line above.
- Patched: exit 0, and the one `workflow.md` instruction the skill says to
  follow is printed.
- `bmad-build-auto`: the same, with the `planning_artifacts` HALT before and
  exit 0 after.

`scripts/test-patch-render-skill.sh` covers equal values (resolve), unequal
values (still stop), one differing value among three (still stops), values of
different types (still stop), a missing key, and the build stopping when the
upstream text is absent or appears twice.

## Notes for consumers

- **Extract the tarball, then pass the directory to `sideshow install --from`.**
  `sideshow install` takes a directory, not a tarball.
- **Run `sideshow commands sync` after install.** `sideshow install` flips the
  active version but does not sync bindings; `sideshow use` does.
- **`sideshow install` activates what it installs.** `sideshow list` marks the
  active version with `*`. Pass `--no-activate` to install without changing
  the active version.

## Verify

```sh
gh attestation verify bmad-6.12.4-r2-arcaven.tar.gz --repo ArcavenAE/sideshow-packs
```

The signer identity is `build-pack.yml@refs/heads/main` in
ArcavenAE/sideshow-packs. To confirm the patch is in the extracted pack:

```sh
grep -c 'sideshow-packs patch render-skill-equal-duplicate-keys' scripts/render_skill.py   # expect 1
```

Upstream content, composition and packaging-support status are the base 6.12.4
notes (`docs/release-notes/bmad-v6.12.4.md`); nothing there changed.
