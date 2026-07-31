# Release URL Format

Stable URL contract for sideshow-packs releases. Used by sideshow's
client-side install path (`aae-orc-wk92`) to resolve `pack@version` to
fetch URLs.

## Tag format

Each release is anchored to a git tag:

```
<pack>-v<semver>
```

Examples:

- `bmad-v6.3.0`
- `bmad-v6.5.0` (future)
- `vsdd-factory-v1.0.0-rc.23` (prerelease line; rc suffix is part of
  the semver and survives the tag parse)

The tag triggers `.github/workflows/build-pack.yml` which builds,
signs, and uploads the release. The workflow parses the tag at
[`build-pack.yml:73`][1] (`PACK="${TAG%%-v*}"`, `VERSION="${TAG#*-v}"`).

## Release page URL

```
https://github.com/ArcavenAE/sideshow-packs/releases/tag/<pack>-v<semver>
```

Example: <https://github.com/ArcavenAE/sideshow-packs/releases/tag/bmad-v6.3.0>

## Asset URL pattern

```
https://github.com/ArcavenAE/sideshow-packs/releases/download/<pack>-v<semver>/<filename>
```

## Asset inventory per release

For pack `<pack>` at version `<v>`:

| Asset | Purpose |
|---|---|
| `<pack>-<v>-arcaven.tar.gz` | The pack tree in sideshow's user-install layout (pack content at root, `.claude/` as sibling) |
| `<pack>-<v>-arcaven.tar.gz.sig` | cosign detached signature over the tarball (raw signature bytes) |
| `<pack>-<v>-arcaven.tar.gz.bundle` | cosign signing bundle: signature + Sigstore Rekor log entry + cert chain (single-file verifiable bundle) |
| `<pack>-<v>-arcaven.tar.gz.attest.bundle` | cosign attestation bundle: in-toto attestation (predicate-type `https://arcaven.com/sideshow/install-meta/v0.1.0`) signed via Sigstore |
| `install.meta.yaml` | Human-readable provenance (upstream npm + git + composition + invocation) |
| `install.meta.json` | Machine-readable predicate (same shape as YAML, no comments) |
| `install.meta.yaml.sig` / `install.meta.yaml.bundle` | cosign sig + bundle for the YAML |
| `file-manifest.csv` | Per-file `sha256,size,relpath` — the parity reference for `aae-orc-7dri` |

## Resolution by sideshow

Given a request for `bmad@6.3.0`, sideshow's install path constructs:

```
https://github.com/ArcavenAE/sideshow-packs/releases/download/bmad-v6.3.0/bmad-6.3.0-arcaven.tar.gz
```

For verification it also fetches:

```
.../bmad-6.3.0-arcaven.tar.gz.bundle          # signature bundle
.../bmad-6.3.0-arcaven.tar.gz.attest.bundle   # attestation bundle
.../install.meta.json                          # canonical provenance
.../file-manifest.csv                          # post-extract integrity check
```

## Verification recipe

After download:

```sh
# Verify the signature bundle (no key needed; Sigstore Rekor backed)
cosign verify-blob \
  --bundle bmad-6.3.0-arcaven.tar.gz.bundle \
  --certificate-identity-regexp "https://github.com/ArcavenAE/sideshow-packs/.github/workflows/.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  bmad-6.3.0-arcaven.tar.gz

# Verify the attestation (provenance predicate)
cosign verify-blob-attestation \
  --bundle bmad-6.3.0-arcaven.tar.gz.attest.bundle \
  --certificate-identity-regexp "https://github.com/ArcavenAE/sideshow-packs/.github/workflows/.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --type "https://arcaven.com/sideshow/install-meta/v0.1.0" \
  bmad-6.3.0-arcaven.tar.gz
```

Both should print `Verified OK`. Any other output (signature mismatch,
identity mismatch, Rekor lookup failure) is a tampering or
misconfiguration signal — refuse the artifact.

After extract, a sideshow client should additionally verify
`file-manifest.csv` matches the on-disk tree (sha256 per file). This
catches extraction-time corruption and ensures bytewise reproducibility
of the install state.

## Identity binding

Releases are bound to:

- **Repository:** `ArcavenAE/sideshow-packs`
- **Workflow:** `.github/workflows/build-pack.yml` on `refs/heads/main`
- **OIDC issuer:** `https://token.actions.githubusercontent.com`

The cosign keyless signing flow embeds these into the certificate's
SAN and OIDC claims. Verification regex patterns above are anchored to
this binding. Future release-channel work (`stable` / `next`, per the
F24 charter) may layer additional identity rules on top — those are
separate trust decisions, not URL changes.

## Tag re-cuts

If a tag must be re-cut (e.g., the first published artifacts had a
build defect like the missing-signing-on-tag-trigger bug fixed in
[e666f4f][2]), follow this procedure:

1. `gh release delete <tag> --yes` — remove the prior draft release
2. `git push --delete origin <tag>` — remove the remote tag
3. `git tag -d <tag>` — remove the local tag
4. Apply the fix to `main`
5. `git tag -s <tag> -m "..."` — re-sign the tag at the fix commit
6. `git push origin <tag>` — triggers a fresh signed build

Re-cuts are reversible only while the release is still draft. Once a
release is published (out of draft state), treat the artifacts as
immutable; defects are corrected via overlay artifacts (`aae-orc-10vq`)
or a new minor version, not by re-cutting.

## Schema versioning

`install.meta.yaml` and `install.meta.json` declare `schema_version`
at the top. Today's schema is `0.1.0`. Future bumps follow
`docs/schema-versioning.md` in the sideshow repo (`aae-orc-xe7l`).

## Related

- `aae-orc-u84w` — first release cut (this work).
- `aae-orc-wk92` — sideshow client-side fetch + verify (next).
- `aae-orc-ibil` — frozen-composition pipeline (closed; this is its
  publishing surface).
- `aae-orc-mezl` — pluggable source backends. Today's only backend is
  GitHub Releases (this URL format). Future backends layer on top.
- `aae-orc-bgbm` — `install.meta` schema v0.2 (build env + builder
  identity + multi-backend source types).

[1]: ../.github/workflows/build-pack.yml
[2]: https://github.com/ArcavenAE/sideshow-packs/commit/e666f4f

## Latest marker policy

The repo-wide GitHub Latest marker tracks the **highest published
(non-draft) bmad pack version**. It is set explicitly at publish time
(`gh release edit <tag> --latest`), never left to GitHub's default,
which follows publish order and lands on the wrong release after a
batch backfill (observed 2026-07-12: nine releases published within
seconds left Latest on `bmad-v6.3.0` for two weeks; corrected
2026-07-30, `aae-orc-l7t7`). The upstream-intake workflow verifies the
marker on every run and self-heals drift.

Consumers must **never resolve `/releases/latest`**. This repo
publishes multiple packs over time (`aae-orc-zb12` onboarding), so a
single repo-wide marker cannot identify "the current version" of any
one pack. Resolution is always by explicit tag (`<pack>-v<semver>`)
per this document. The marker exists for humans landing on the repo
page, nothing else.

## Publishing gotchas

- **Never push more than 3 tags in one `git push`.** GitHub suppresses
  push events beyond three tags per push — workflows silently do not
  fire (hit 2026-07-12: 8 `bmad-v*` tags pushed together triggered
  zero builds). Recovery: `workflow_dispatch` with `publish=true` per
  version — the release step attaches to the already-pushed tag.
- Releases are created as **drafts** by design (both tag-trigger and
  dispatch); publishing the draft is a deliberate second step
  (`gh api -X PATCH .../releases/<id> -f draft=false`).
