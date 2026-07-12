# LLM Revalidation Runbook — packaging an unsupported version

You (an LLM agent or a human) are here because `scripts/check-support.sh`
flagged a version outside every validated bracket in
`registry/<pack>-pack-support.yaml`. This runbook is the supported path to either
(a) extend the validated bracket with evidence, or (b) package
best-effort with eyes open.

The register is the contract: **do not extend a bracket without
completing the verification below**, and **do add a wrinkle entry for
every behavior change you find**, even ones the pipeline absorbs
silently. The register is only useful if wrinkles are recorded when
discovered, not when they bite.

## Step 0 — Orient

1. Read `registry/<pack>-pack-support.yaml` in full: the `pipeline_assumptions`
   define what "supported" means; the `wrinkles` show the kinds of
   shifts this upstream has produced before and where their edges were.
2. Read the evidence findings referenced by the most recent validated
   bracket — they demonstrate the method at full fidelity.
3. Identify the gap: `NEW_VERSION` vs the bracket's `max`. Every
   release tag between them must be examined, not just the target.

## Step 1 — Diff the upstream installer across the gap

```sh
git clone --filter=blob:none <upstream.repo> work/upstream
cd work/upstream
git tag --sort=version:refname   # identify stable tags in the gap
```

For each consecutive stable-tag pair from `max` to `NEW_VERSION`:

```sh
git diff --stat vA..vB -- <installer paths>   # discover layout first; bmad: tools/
```

Check each `pipeline_assumptions` entry explicitly:

- **argv contract** — diff the install command's flag parsing; look for
  removed/renamed flags, newly required flags, new interactive prompts
  (anything that could hang a `--yes` non-interactive run).
- **output layout** — constants/functions that name the output dir and
  config/manifest paths.
- **manifest shape** — the manifest writer; key renames, list→map
  shape changes, value format changes (see wrinkle
  `manifest-version-v-prefix` for a precedent: even a `v`-prefix
  change breaks consumers).
- **module set / resolution** — module registry files, external-module
  clone/resolve logic, pin mechanics, new/renamed/retired modules.
- **engines / environment** — `package.json` engines, new external
  tool checks, network endpoints contacted at build time.
- Read the GitHub release notes for every tag in the gap
  (`gh release view <tag> --json body`).

## Step 2 — Test-build without publishing

Dispatch the pipeline with signing and publishing OFF:

```sh
gh workflow run build-pack.yml -R ArcavenAE/sideshow-packs \
  -f pack=<pack> -f version=<NEW_VERSION> -f pins=auto \
  -f sign=false -f publish=false
```

(If the register gate blocks CI, this is the one sanctioned use of
`allow_unsupported=true` / `ALLOW_UNSUPPORTED=1` — a revalidation
test-build with publish=false.)

On failure: read the run's `installer.stderr` capture, map the failure
to the assumption it violates, and adapt `scripts/build-<pack>.sh`
behind a version guard if the change is absorbable.

## Step 3 — Verify the artifact, not just the exit code

Download the workflow artifact and check:

1. `install.meta.json` — `requested_pins` vs `modules_from_manifest`
   (versions AND shas present), `pin_policy`, plausible `file_count`
   vs the previous version's.
2. `file-manifest.csv` — spot-diff against the previous version's:
   wholesale tree renames signal a structural re-issue (precedent:
   6.2.2→6.3.0 was 2600+ file ops; 6.4→6.5 was ~stable).
3. `pack.yaml` inside the tarball — present, correct version,
   `custom_bridge`/gitignore sections intact.

## Step 4 — Update the register (this is the deliverable)

In `registry/<pack>-pack-support.yaml`:

1. Extend the validated bracket's `max` (or open a new bracket if the
   gap contains an unabsorbable break), update `validated_at`, `method`.
2. Add one `wrinkles` entry per behavior change found — including
   changes that required no adaptation (`severity:
   adaptation-not-needed`); the next reader needs to know it was seen.
3. Reference evidence: a finding in the orc `_kos/findings/` for
   anything substantive, upstream commits/PRs, run IDs.
4. Commit register + any script adaptations together, referencing the
   bd ticket for the packaging request.

## Step 5 — Decide on publish

Bracket extended ≠ release published. Publishing (tag push → sign +
attest + GitHub Release) is a separate, deliberate act after content
review. Never publish from an `ALLOW_UNSUPPORTED` build.

## If the user wants best-effort WITHOUT revalidation

Set `ALLOW_UNSUPPORTED=1` (or workflow input `allow_unsupported=true`).
The build proceeds; the register is not extended; the artifact's
provenance will not claim validated support. State plainly in any
handoff that the artifact is best-effort against an unvalidated
upstream version, and list which assumptions were NOT verified.
