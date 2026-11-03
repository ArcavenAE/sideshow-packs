<!--
Authoring note: this block is a comment, so GitHub does not show it in the
release body. Copy this file to FILL-PACK-vFILL-VERSION.md, replace every FILL marker,
and attach it unedited:

  gh release edit FILL-PACK-vFILL-VERSION -R ArcavenAE/sideshow-packs \
    --notes-file docs/release-notes/FILL-PACK-vFILL-VERSION.md

The pipeline creates releases as drafts with no body (build-pack.yml,
action-gh-release), so the notes are authored, not generated. Before attaching,
search the file for FILL: a marker left in place shows in the release body.

Habits from the 6.12.4 review:

- Keep the authoring note in this comment and the release text below it, so
  the attached bytes are the published bytes.
- Say which build each figure comes from: the signed release build, or the
  test build.
- State an effect only as strongly as you observed it. For a claim about what
  happens (a file is ignored, a skill halts), run it, and show the
  commands and their output in the notes, or say where they are; if you
  inferred it from the pack contents, say "inferred, not run".
- Make a claim a consumer can check, with the command that checks it. For
  activation: `sideshow list` marks the active version with `*`, and
  `sideshow install --no-activate` installs without switching.
- Write links to the repo as full
  https://github.com/ArcavenAE/sideshow-packs/blob/main/... URLs, because a
  repo path in a code span does not resolve on a release page.
- State the install steps a consumer needs. Sideshow takes an extracted
  directory, not a tarball (`internal/pack/pack.go`, `ValidateShape`, and
  `docs/repo-bindings-enablement.md` in ArcavenAE/sideshow), and install does
  not sync bindings (`README.md` quickstart, `sideshow commands sync`).
- Pin the cosign identity to build-pack.yml@refs/heads/main, and verify every
  signed asset a consumer reads.
-->
# FILL: pack and version release notes

FILL: one or two sentences on what this release is and why to take it.

**Composition.** FILL: modules, versions, and what changed against the
previous release.

**Artifact.** `FILL-asset-name`, FILL-size bytes, sha256 `FILL-digest`.
`file-manifest.csv` lists FILL-count files with their hashes.

## Notes for consumers

- FILL: anything a consumer must do or watch for, one bullet each.
- **Extract the tarball, then pass the directory to `sideshow install --from`.**
  `sideshow install` takes a directory, not a tarball.
- **Run `sideshow commands sync` after install.** `sideshow install` flips the
  active version but does not sync bindings; `sideshow use` does.
- **`sideshow install` activates what it installs.** `sideshow list` marks the
  active version with `*`. Pass `--no-activate` to install without changing
  the active version (a first install of a pack always activates).

## Verify

```sh
cosign verify-blob \
  --bundle FILL-ASSET.bundle \
  --certificate-identity 'https://github.com/ArcavenAE/sideshow-packs/.github/workflows/build-pack.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  FILL-ASSET

cosign verify-blob-attestation \
  --bundle FILL-ASSET.attest.bundle \
  --certificate-identity 'https://github.com/ArcavenAE/sideshow-packs/.github/workflows/build-pack.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --type https://arcaven.com/sideshow/install-meta \
  FILL-ASSET

cosign verify-blob \
  --bundle install.meta.yaml.bundle \
  --certificate-identity 'https://github.com/ArcavenAE/sideshow-packs/.github/workflows/build-pack.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  install.meta.yaml
```

FILL: say what each command printed for this release.
