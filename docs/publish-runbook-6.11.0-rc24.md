# Publish runbook — bmad 6.11.0 and vsdd-factory 1.0.0-rc.24

Everything up to the publish gate is staged on branch
`feat/6.11.0-and-rc24-packaging`. The remaining steps need an identity with
write/admin on `ArcavenAE/sideshow-packs`; `arcavenai` has pull-only access
and gets HTTP 403 on `workflow_dispatch`.

Run these from `aae-orc/sideshow-packs`.

## 0. Push the staged work

```sh
git push -u origin feat/6.11.0-and-rc24-packaging
gh pr create --fill      # composition fix + Step-1 revalidation + release notes
```

The composition fix must land before any build, or the tag-push path will
narrow the composition again exactly as it did on 2026-08-01.

## 1. Test builds — runbook Step 2 (unsigned, unpublished)

Both versions sit outside their validated brackets, so `allow_unsupported` is
required. This is the runbook's one sanctioned use of it: a revalidation
test-build with `publish=false`.

```sh
gh workflow run build-pack.yml -R ArcavenAE/sideshow-packs \
  -f pack=bmad -f version=6.11.0 \
  -f pins=auto -f sign=false -f publish=false -f allow_unsupported=true

gh workflow run build-pack.yml -R ArcavenAE/sideshow-packs \
  -f pack=vsdd-factory -f version=1.0.0-rc.24 \
  -f sign=false -f publish=false -f allow_unsupported=true
```

Note there is no `-f modules=...` on the bmad run. That is the point of the
fix: composition now comes from the register (`bmm,cis,gds,tea,bmb,wds`), so
dispatch and tag-push produce the same thing. If you pass `-f modules` you
are overriding the register, which is supported but should be deliberate.

Watch them:

```sh
gh run list -R ArcavenAE/sideshow-packs --workflow build-pack.yml --limit 5
gh run watch -R ArcavenAE/sideshow-packs <run-id>
```

On failure, read the run's `installer.stderr` capture and map the failure to
the assumption it violates before adapting anything.

## 2. Verify the artifacts — runbook Step 3

Download each run's artifact and check three things.

```sh
gh run download -R ArcavenAE/sideshow-packs <run-id> -D /tmp/verify
```

1. **`install.meta.json`** — `requested_pins` against `modules_from_manifest`
   (versions *and* shas present), `pin_policy`, and a plausible `file_count`
   against the previous version's.
2. **Composition, explicitly.** This is the check the r2 batch lacked:

   ```sh
   yq -r '.upstream.modules[] | "\(.name) \(.version)"' /tmp/verify/install.meta.yaml
   ```

   Expect seven rows for bmad: core, bmm, cis, gds, tea, **bmb**, **wds**.
   Five rows means the register was not read and the fix did not take.
3. **`file-manifest.csv`** — spot-diff against 6.10.0's. Expect growth from
   the new `_bmad/render/` snapshot tree and shrinkage from the retired
   skills; wholesale tree renames would signal a structural re-issue needing
   its own analysis.

For vsdd-factory, confirm `exec-manifest.txt` shows **117** executables.

## 3. Extend the brackets — runbook Step 4

Only after Steps 2 and 3 pass. In each register, replace the
`revalidation_in_progress` entry with a real bracket extension: move `max`,
set `validated_at`, write `method`, and cite the run ids as evidence. Keep
every wrinkle already recorded.

For vsdd-factory, the bracket is single-rung, so also set `upstream_commit`
to `89f6f87cf476b1f57d979962eabf0d9b20a49e69` — upstream force-moves release
tags, so the commit is the binding identity.

Commit the register with the run ids in the message.

## 4. Publish — runbook Step 5

Publishing is a separate deliberate act after content review, and it is never
done from an `ALLOW_UNSUPPORTED` build. Once the brackets are extended, the
gate passes on its own and the tag push is a clean signed build:

```sh
git tag -s bmad-v6.11.0 -m "bmad 6.11.0"
git push origin bmad-v6.11.0

git tag -s vsdd-factory-v1.0.0-rc.24 -m "vsdd-factory 1.0.0-rc.24"
git push origin vsdd-factory-v1.0.0-rc.24
```

Each tag push builds, signs (cosign keyless, Sigstore Rekor), attests, and
creates a **draft** release with no body.

## 5. Attach the release notes

The pipeline sets no release body. The notes are authored and waiting:

```sh
gh release edit bmad-v6.11.0 -R ArcavenAE/sideshow-packs \
  --notes-file docs/release-notes/bmad-v6.11.0.md

gh release edit vsdd-factory-v1.0.0-rc.24 -R ArcavenAE/sideshow-packs \
  --notes-file docs/release-notes/vsdd-factory-v1.0.0-rc.24.md
```

Both files contain `<fill>` placeholders for the artifact digest and file
count, which are only knowable after the build. Fill them before attaching.

Then verify a signature end-to-end from the published assets before taking
the draft live, and mark vsdd-factory as a prerelease.

## 6. After publishing

- Consumers upgrading bmad need the customization-file renames in the notes
  (`bmad-quick-dev.toml` → `bmad-build.toml`, and four more). Those files live
  in each repo's `_bmad-custom/`; upgrading the pack does not rename them, and
  an unattended run on an old name with a legacy override halts.
- On any machine that installs 6.11.0, the store must be unlocked first
  (`chmod -R u+w`) — installs freeze the version dir read-only.
- The 6.4.0–6.9.0 `-r2` releases carry the same narrowed composition. Decide
  whether they are re-issued as `-r3` or left with corrected release notes
  saying what they actually contain (sideshow-packs#20).
