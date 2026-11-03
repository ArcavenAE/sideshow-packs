<!--
Authoring note: this block is a comment, so GitHub does not show it in the
release body. Copy this file to <pack>-v<version>.md, fill the placeholders,
and attach it unedited:

  gh release edit <pack>-v<version> -R ArcavenAE/sideshow-packs \
    --notes-file docs/release-notes/<pack>-v<version>.md

The pipeline creates releases as drafts with no body (build-pack.yml,
action-gh-release), so the notes are authored, not generated.

Keep the authoring note in this comment and the release text below it, so the
attached bytes are the published bytes. Say which build each figure comes
from: the signed release build, or the test build. Write links to the repo
as full https://github.com/ArcavenAE/sideshow-packs/blob/main/... URLs,
because a repo path in a code span does not resolve on a release page.
-->
# <pack> <version> release notes

<One or two sentences: what this release is and why to take it.>

**Composition.** <Modules, versions, and what changed against the previous
release.>

**Artifact.** `<asset name>`, <size> bytes, sha256 `<digest>`.
`file-manifest.csv` lists <n> files with their hashes.

## Notes for consumers

- <Anything a consumer must do or watch for, one bullet each.>

## Verify

```sh
cosign verify-blob \
  --bundle <asset>.bundle \
  --certificate-identity 'https://github.com/ArcavenAE/sideshow-packs/.github/workflows/build-pack.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  <asset>
```
