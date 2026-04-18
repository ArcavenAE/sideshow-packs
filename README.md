# sideshow-packs

Frozen-composition publishing pipeline for Arcaven-curated sideshow packs.

Produces signed, versioned tarballs of multi-source content packs (BMAD,
VSDD, etc.) suitable for consumption by
[sideshow](https://github.com/ArcavenAE/sideshow) without executing
untrusted JavaScript on user machines.

**Status:** MVP. bmad support shipped. vsdd-factory + dark-factory
pending (aae-orc-amet).

**Visibility:** private. Some source materials cannot be redistributed.
A stripped-down public mirror is planned for later.

## What this produces

For each pack version, the pipeline emits:

- `<pack>-<version>-arcaven.tar.gz` — the pack tree in sideshow's
  user-install layout (pack content at root, `.claude/` as sibling for
  tool bindings).
- `install.meta.yaml` — provenance manifest: upstream git sha, npm
  tarball sha, per-module versions + sources, install invocation,
  tarball sha256.
- `file-manifest.csv` — per-file sha256 + size.
- `install.meta.yaml.sig` + `install.meta.yaml.bundle` — cosign
  signature + Sigstore Rekor transparency log bundle.
- `<pack>-<version>-arcaven.tar.gz.sig` + `.bundle` — same for the
  tarball itself.
- Provenance attestation via `cosign attest-blob` — SLSA/in-toto
  attestation linking tarball sha to upstream source shas.

## Distribution

Signed artifacts are published as GitHub Release assets on this repo
(private). sideshow's `install.source` contract (aae-orc-h07h) will
reference the release URLs. A stripped-down public mirror will be
added later via `aae-orc-<TBD>`.

## Local build

Requires: `node` (≥ 18), `npx`, `yq`, `bash`. `cosign` optional (signing
is skipped locally without it).

```sh
# Default: bmad 6.3.0 with all modules + claude-code bindings
BMAD_VERSION=6.3.0 scripts/build-bmad.sh
ls artifacts/
```

Produces artifacts in `./artifacts/`. Not signed unless `COSIGN=1` and
you have cosign configured.

## CI build

Triggered by:

- Manual dispatch with inputs: pack name + version.
- Push of a version tag matching `<pack>-v<semver>`.

See `.github/workflows/build-pack.yml`. Signing uses cosign keyless
OIDC via GitHub Actions — no keys to rotate.

## Related orchestrator issues

- `aae-orc-ibil` — this pipeline (the one you're reading).
- `aae-orc-entu` — source-material provenance chain (consumed by the
  `cosign attest-blob` step).
- `aae-orc-mezl` — pluggable source backends (consumers install via
  GitHub Releases backend; future: CDN, apt, plugin marketplace).
- `aae-orc-h07h` — `pack.yaml install:` contract that references the
  signed artifacts from this pipeline.
- `aae-orc-10vq` — overlay artifact spec; overlays also publish via this
  pipeline.
- `aae-orc-7dri` — install parity test consumes `file-manifest.csv` as
  the golden reference.
- `aae-orc-amet` — VSDD ecosystem packs (vsdd, dark-factory, vsdd-factory)
  to add next.

See also `_kos/findings/finding-025-*` and `finding-027-*` in the orc
repo for the probe evidence this pipeline is built from.
