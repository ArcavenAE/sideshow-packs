# bmad 6.12.0 release notes

Attach as the body of the `bmad-v6.12.0` draft release. The pipeline creates
releases as drafts with no body (`build-pack.yml`, `action-gh-release`), so
this text is authored, not generated.

Figures below come from the verified test build (run 34284724143); the signed
release rebuilds the same tree, so confirm they match before publishing.

---

Frozen-composition build of BMad Method 6.12.0, assembled by running the
upstream installer once in auditable CI and signing the result. Installing
this artifact never executes upstream JavaScript on your machine.

**One change dominates this release for anyone upgrading a working install:
the deprecated v6 compatibility shims are gone.** Upstream made them opt-in
on fresh installs, and a frozen-composition build is always a fresh install,
so this pack ships none of the 20 shims the 6.11.0 pack carried. If anything
you run still calls a retired v6 skill name, it stops resolving here. The
full list and its replacements are below.

**Composition: seven modules.** `core`, `bmm`, `cis`, `gds`, `tea`, `bmb`,
`wds`, declared in `registry/bmad-pack-support.yaml` as `default_modules`.
External modules are pinned as-of the upstream release date; exact versions
and commit shas are in `install.meta.yaml`. As built and verified:

| module | version | source | vs 6.11.0 |
|---|---|---|---|
| core | 6.12.0 | built-in | 6.11.0 |
| bmm | 6.12.0 | built-in | 6.11.0 |
| cis | v0.3.2 | external | v0.2.1 |
| gds | v0.7.2 | external | v0.6.0 |
| tea | v1.24.0 | external | v1.21.10 |
| bmb | v2.2.2 | external | v2.1.0 |
| wds | v0.4.3 | external | unchanged |

The file census is 2023 files, down 2 from 6.11.0. A net figure that small
hides real churn, so every path was attributed: 86 removed, 84 added, and
each one falls into exactly one of four causes. 32 files across 20 retired
skill IDs are the shim bindings this release drops. 8 for 8 are `bmad-checkpoint-preview` renamed to
`bmad-walkthrough`. 5 are compiled Python artefacts (`__pycache__`, `.pyc`)
that the installer now filters out of skill copies. The rest is content
arriving and leaving with the `gds`, `tea`, and `cis` pin advances above. No
path was left unexplained.

## Verify

```sh
cosign verify-blob \
  --bundle bmad-6.12.0-arcaven.tar.gz.bundle \
  --certificate-identity-regexp 'github.com/ArcavenAE/sideshow-packs' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  bmad-6.12.0-arcaven.tar.gz
```

`install.meta.yaml` is signed separately and carries the full source chain:
upstream git sha (`05bfbd46d00766ec88eb9b42e76be2c575d64d7b`), npm tarball
digest, and the resolved version and commit of every external module.
`file-manifest.csv` lists 2023 files with per-file digests.

## Before you upgrade

**1. The v6 compatibility shims are gone.** Upstream 6.11.0 renamed a large
part of the skill catalog and left forwarding shims behind under `v6-shims/`.
6.12.0 makes those shims opt-in: `--shims` keeps them, and with no flag a
fresh install ships none. This pack is built with no flag, which matches what
`npx bmad-method install` does on a fresh tree.

Concretely, these names no longer resolve. Each replacement is installed and
ready:

| retired name | replacement |
|---|---|
| `bmad-quick-dev` | `bmad-build` |
| `bmad-dev-auto` | `bmad-build-auto` |
| `bmad-create-prd`, `bmad-edit-prd`, `bmad-validate-prd` | `bmad-prd` (create / update / validate intent) |
| `bmad-create-architecture` | `bmad-architecture` (create intent) |
| `bmad-create-story`, `bmad-dev-story` | `bmad-build` |
| `bmad-document-project`, `bmad-generate-project-context` | `bmad-project-context` |
| `bmad-market-research`, `bmad-technical-research`, `bmad-domain-research` | `bmad-deep-recon` |
| `bmad-review-adversarial-general`, `bmad-review-edge-case-hunter`, `bmad-review-verification-gap`, `bmad-editorial-review`, `bmad-editorial-review-prose`, `bmad-editorial-review-structure` | `bmad-review` lenses |
| `bmad-sprint-status` | `bmad-sprint-planning` |

A shim is marked by `metadata.lifecycle: shim` in its own `SKILL.md`, not by
where it sits: `bmad-generate-project-context` lives under `plan/` alongside
live skills and is still a shim.

If you customized a shimmed skill and have not yet moved that customization
to its replacement, do that before upgrading. Upstream's own guidance is that
shims disappear entirely at v7, so this is the transition either way; the
pack simply arrives at it now rather than later.

**2. `bmad-checkpoint-preview` is now `bmad-walkthrough`** (code `CK` → `WT`).
The old ID forwarded only through a shim, so in this pack it does not exist.
Rename its customization files in your repo's `_bmad-custom/` (which the
sideshow bridge presents to bmad as `_bmad/custom/`):

| old | new |
|---|---|
| `bmad-checkpoint-preview.toml` | `bmad-walkthrough.toml` |
| `bmad-checkpoint-preview.user.toml` | `bmad-walkthrough.user.toml` |

The 6.11.0 renames still apply if you are coming from 6.10.0 or earlier; that
table is in the 6.11.0 notes.

**3. Two upstream defaults changed under you.** `persistent_facts` now ships
empty, so if you relied on `project-context.md` auto-loading, re-add it to
your override. And `{diff_output}` became `{diff_file}`; update any custom
review override that interpolates it.

**4. `uv` with Python 3.11+ remains a hard runtime requirement** for
`bmad-build` and `bmad-build-auto`, unchanged from 6.11.0. Installing this
pack does not install `uv`, and the failure appears at skill-run time:

```sh
uv --version && uv run --python 3.11 python -c 'print("ok")'
```

## What's new upstream

- **Build sizes its own ceremony.** It decides how much process a change
  needs after investigating it rather than before, so a simple change gets a
  two-section spec and finishes in one session.
- **Review triage logs a verdict and evidence for every finding**, so nothing
  is dropped silently. Several review bugs went with it: layers that returned
  nothing, serial launches, and re-reviews redoing settled work.
- **Build no longer auto-triggers** on interactive edits, git bookkeeping, or
  formatting chores.
- **`bmad-project-context` adopts a handwritten `AGENTS.md`** instead of
  rewriting it.
- **Three installer targets added**: Polytoken, Grok, ZCode. `claude-code` is
  untouched.
- Docs reorganized by task, Korean translation added, and fixes across
  customization resolution, review dispatch, and Windows encoding.
- `llms.txt` and `llms-full.txt` are no longer published upstream.

Full upstream notes: https://github.com/bmad-code-org/BMAD-METHOD/releases/tag/v6.12.0

## Packaging-support status

Verified against all six pipeline assumptions at the source level across the
`v6.11.0..v6.12.0` gap. Nine installer files changed; none of them break an
assumption:

- **argv-contract** holds. `--shims` / `--no-shims` are added; every flag the
  pipeline passes is unchanged. The new shim prompt cannot hang a scripted
  run. `_selectShimPreference` returns before the confirm on `--yes`, and
  again on a non-TTY stdin.
- **bmad-output-dir** holds; the layout is untouched.
- **manifest-shape** holds. `installation.installShims` is added beside
  `.modules` when shims are available; it is a new key, not a reshape.
- **module-set** holds; `bmad-modules.yaml` is byte-identical.
- **claude-sibling** holds; `platform-codes.yaml` adds three unrelated
  targets.
- **node-engine** holds at `>=20.12.0`.

Four new wrinkles are recorded in `registry/bmad-pack-support.yaml`:
`shims-opt-in-fresh-install`, `checkpoint-preview-renamed-walkthrough`,
`pycache-filtered-from-skill-copies`, `platform-grok-polytoken-zcode`.

`install.meta.yaml` declares the validated-support state honestly. Check it
before treating this artifact as bracket-validated.

## Artifact digest

The published tarball's `sha256` is recorded in the release assets and in the
signed `install.meta`. Verify against those rather than a digest transcribed
into prose. A hash copied by hand is a hash nobody checked.

```sh
shasum -a 256 bmad-6.12.0-arcaven.tar.gz
```
