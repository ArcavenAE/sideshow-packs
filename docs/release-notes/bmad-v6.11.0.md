# bmad 6.11.0 — release notes

Attach as the body of the `bmad-v6.11.0` draft release. The pipeline creates
releases as drafts with no body (`build-pack.yml`, `action-gh-release`), so
this text is authored, not generated.

Two values must be filled from the built artifact before publishing; they are
marked `<fill>` below and are the only placeholders in this file.

---

Frozen-composition build of BMad Method 6.11.0, assembled by running the
upstream installer once in auditable CI and signing the result. Installing
this artifact never executes upstream JavaScript on your machine.

**Composition — six modules.** `core`, `bmm`, `cis`, `gds`, `tea`, `bmb`,
`wds`. This is the full composition, and it is now declared in
`registry/bmad-pack-support.yaml` as `default_modules` rather than as a
literal inside the build workflow. The previous arrangement could not be
overridden on the tag-push path, which is how the 2026-08-01 `-r2` batch came
to ship without `bmb` and `wds` while its notes claimed identical content
(sideshow-packs#20). Composition is now a property of the pack, recorded
beside the support bracket that validated it.

External modules are pinned as-of the upstream release date; the exact
versions and commit shas are recorded in `install.meta.yaml`.

## Verify

```sh
cosign verify-blob \
  --bundle bmad-6.11.0-arcaven.tar.gz.bundle \
  --certificate-identity-regexp 'github.com/ArcavenAE/sideshow-packs' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  bmad-6.11.0-arcaven.tar.gz
```

`install.meta.yaml` is signed separately and carries the full source chain:
upstream git sha, npm tarball digests, and the resolved version of every
external module. `file-manifest.csv` lists `<fill: file count>` files with
per-file digests.

## Before you upgrade

This is the largest upstream release we have packaged, and three of its
changes will affect a working install. None of them are packaging defects;
all three are upstream behavior you should meet deliberately.

**1. Rename your customization files, or unattended runs will refuse to
start.** Skills were renamed and their customization files were not. The
shim offers to migrate, but it requires explicit approval and never
overwrites — declined or unavailable, it halts rather than forwarding. In
your repo's `_bmad-custom/` (which the sideshow bridge presents to bmad as
`_bmad/custom/`):

| old | new |
|---|---|
| `bmad-quick-dev{,.user}.toml` | `bmad-build{,.user}.toml` |
| `bmad-dev-auto{,.user}.toml` | `bmad-build-auto{,.user}.toml` |
| `bmad-sprint-status.toml` | `bmad-sprint-planning.toml` |
| `bmad-document-project.toml` | `bmad-project-context.toml` |
| `bmad-generate-project-context.toml` | `bmad-project-context.toml` |

Config resolution is now a four-file layered TOML chain: `_bmad/config.toml`
→ `config.user.toml` → `custom/config.toml` → `custom/config.user.toml`. The
per-module `_bmad/bmm/config.yaml` still ships and older skills still read
it, so 6.11.0 is the migration, not the cutover.

Related: renderers now halt on a missing config key or an unparseable
override instead of silently rendering an empty string or ignoring the file.
A `{{.var}}` absent from your merged config exits 1. That is an improvement,
and it will surface overrides that were quietly broken.

**2. `uv` with Python 3.11+ is now a hard runtime requirement for rendered
skills.** `bmad-build` and `bmad-build-auto` halt outright when `uv` is
unavailable — there is no interpreter fallback. Installing this pack does not
install `uv`, and the failure appears at skill-run time rather than at
install time, so it is worth checking before you need it:

```sh
uv --version && uv run --python 3.11 python -c 'print("ok")'
```

The installer's own `uv` check is warn-don't-block, which is why a successful
install tells you nothing about this.

**3. The skill catalog is much smaller, and the agent roster lost a member.**
Core drops from fourteen skills to eight. Three review skills and two
editorial skills become lenses on a single `bmad-review`, selected through
`[[workflow.lenses]]`. Three research skills become `bmad-deep-recon`.
`bmad-document-project` and `bmad-generate-project-context` become
`bmad-project-context`. `bmad-quick-dev` → `bmad-build`, `bmad-dev-auto` →
`bmad-build-auto`. Retired IDs keep working through forwarding shims in
`v6-shims/` until the v7 cut.

Removed outright, and listed in upstream's `removals.txt`:
`bmad-agent-tech-writer` (Paige), `bmad-check-implementation-readiness`,
`bmad-index-docs`, `bmad-shard-doc`. `bmad-spec` moved from core into `bmm`,
so core-only installs no longer receive it.

Two consequences worth stating plainly. Your synced binding count will drop
after `sideshow commands sync` — that is the removals processing working, not
content going missing. And the `[agents.*]` roster loses Paige, so party mode
convenes a smaller cast than it did on 6.10.0.

## What's new upstream

The headline is that Quick Dev becomes Build, the one official way BMad
implements code, and Phase 4 becomes a single chain: `bmad-sprint-planning →
bmad-build → bmad-code-review`.

- **`bmad-project-context`** produces one verified block inside your
  repository's `AGENTS.md` instead of generated documentation. Anything
  derivable from source is read live and never stored.
- **`bmad-review` with configurable lenses**, and `[[workflow.review_layers]]`
  in the build and code-review skills lets you add, replace, or disable a
  reviewer — including swapping in an external tool over bash, and therefore a
  different model.
- **A verification-gap reviewer** that asks "if this behavior broke, would any
  test fail?" rather than "is this wrong?"
- **`bmad-retrospective` rebuilt as evidence-based epic review** — it requires
  a source reference on every finding and refuses an epic with unfinished
  stories instead of closing quietly.
- **`bmad-sprint-planning` on a deterministic Python core** (`sprint_plan.py`,
  37 tests) owning parsing, status merging, and drift checks, with judgment
  left to the model.
- **Inspectable workflow snapshots** — skills render through a shared
  `render_skill.py` that publishes immutable content-addressed copies under
  `_bmad/render/`, each with a manifest of renderer and source hashes.
- **Antigravity CLI** joins the installer targets, separate from the
  Antigravity IDE entry so the two cannot collide.

Full upstream notes: https://github.com/bmad-code-org/BMAD-METHOD/releases/tag/v6.11.0

## Packaging-support status

Verified against all six pipeline assumptions at the source level across the
`v6.10.0..v6.11.0` gap: the installer's argv entry points
(`bmad-cli.js`, `commands/install.js`) are unchanged, the output directory is
unchanged, the manifest shape changes only by excluding the new `render/`
tree from module enumeration, external-module pin mechanics are unchanged
apart from git-environment sanitization, `claude-code` binding emission is
untouched, and the Node engines floor stays at `>=20.12.0`.

Four new wrinkles are recorded in `registry/bmad-pack-support.yaml`:
`render-dir-under-bmad`, `git-env-sanitization`,
`uv-hard-requirement-rendered-skills`, `platform-antigravity-cli`, plus two
consumer-migration entries covering the catalog consolidation and the
customization renames.

`install.meta.yaml` declares the validated-support state honestly. Check it
before treating this artifact as bracket-validated.

## Artifact digest

```
sha256  <fill: from file-manifest.csv / the release asset>
```
