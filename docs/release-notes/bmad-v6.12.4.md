# bmad 6.12.4 release notes

Attach as the body of the `bmad-v6.12.4` draft release. The pipeline creates
releases as drafts with no body (`build-pack.yml`, `action-gh-release`), so
this text is authored, not generated.

Figures below come from the signed release build (run 41545200921) and were
checked against the downloaded assets.

---

This is the frozen-composition build of BMad Method 6.12.4, with a recorded
comparison against a native `bmad-method@6.12.4` install: the same 102 skills,
and every byte that differs is the declared rewrite. Installing this artifact
never executes upstream JavaScript on your machine.

**Composition: seven modules**, declared in `registry/bmad-pack-support.yaml`
as `default_modules`, with the five external modules pinned explicitly:

| module | version | source | vs 6.12.0-r2 |
|---|---|---|---|
| core | 6.12.4 | built-in | 6.12.0 |
| bmm | 6.12.4 | built-in | 6.12.0 |
| cis | v0.3.2 | external | unchanged |
| gds | v0.7.2 | external | unchanged |
| tea | v1.27.2 | external | v1.24.0 |
| bmb | v2.2.2 | external | unchanged |
| wds | v0.4.3 | external | unchanged |

Exact commit shas are in `install.meta.yaml`.

**Artifact.** `bmad-6.12.4-arcaven.tar.gz`, 5430826 bytes, sha256
`8fd8b6a4f53fff22da9e338e58bb87a93770519e65fd7a0d5e68547d38307b90`.
`file-manifest.csv` lists 2024 files with their hashes; the extracted pack
holds 2025 files: those 2024 and the manifest itself.

## Parity with a native install

The record is `docs/design/bmad-v6.12.4-native-parity.md`. Comparisons 1 to 7
passed; comparison 8 (harness observations) was not run.

- Skill set: 102 of 102 names equal.
- Skill bytes: 189 of 1943 files differ from a native install; after
  reversing the declared rewrite (the store path, and the appended
  `sideshow:fallback-resolution` block) the residual is 0.
- Resolved config: 156 of 158 keys match; the two missing are `user_name` and
  `project_name`, which the pack deliberately does not ship (see the 6.12.0-r2
  notes).
- Tools in a bound repo: `doctor` 12 ok, 1 warn, 0 fail; `status` 102 of 102
  synced; `coexist-check` clean.

## Notes for consumers

- **`_bmad/custom/` is empty in a bound repo (D-3).** A native install seeds
  two commented template files there (`config.toml`, `config.user.toml`);
  `sideshow project init` creates the directory empty. The templates are all
  comments and `resolve_config.py` returns the same merged result, so no skill
  output differs. Copy the templates from the store if you want them. Tracked
  in ArcavenAE/sideshow#210.
- **`doctor` warns `cwd-known` on a repo bound by `project init` (D-4).**
  Known since 6.12.1 and a sideshow matter, not a pack one.
- **Manifest labels.** `_config/manifest.yaml` records the three external
  modules as `pinned`; a native install records `stable` for the same tag and
  commit.
- **`sideshow install` activates what it installs.** Installing 6.12.4 makes
  it the active bmad version. To go back, run `sideshow use bmad <version>`
  for a version you still have installed.

## Verify

```sh
cosign verify-blob \
  --bundle bmad-6.12.4-arcaven.tar.gz.bundle \
  --certificate-identity-regexp 'https://github.com/ArcavenAE/sideshow-packs/.github/workflows/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  bmad-6.12.4-arcaven.tar.gz

cosign verify-blob-attestation \
  --bundle bmad-6.12.4-arcaven.tar.gz.attest.bundle \
  --certificate-identity-regexp 'https://github.com/ArcavenAE/sideshow-packs/.github/workflows/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --type https://arcaven.com/sideshow/install-meta \
  bmad-6.12.4-arcaven.tar.gz
```

Both print `Verified OK` for this release.
