# finding-002: a build output shipped only beside the tarball never reaches the machine that installs the pack

**Date:** 2026-10-02
**Subject:** which build outputs travel inside the signed tarball
**Occasion:** aae-orc-xorml (sideshow-packs#39, #40) and a probe of the exec manifest during its harvest
**Evidence:** `scripts/build-bmad.sh` and `scripts/build-vsdd-factory.sh` at `40a45a7`; tarball listings of a
local bmad 6.12.0 build, a local vsdd-factory 1.0.0-rc.23 build, and the published bmad-v6.12.0-r2; sideshow
`internal/pack/pack.go` `verifyExecManifest` at `1b5d716`.

## Why this is worth writing down

The pipeline's value is provenance that holds after install. A build output written only to the release
directory is a sibling asset: it can be downloaded and inspected, but once a user extracts the tarball and
installs it, the output is not on the machine. Anything sideshow wants to check later has to be inside the
tarball, where the tarball's signature also covers it.

## What was observed

- `file-manifest.csv` (per-file sha256, size, path) was written to the release directory only. The installed
  store had no copy, so nothing could re-verify a store version after extraction. Fixed in #40: both
  builders now copy it into the pack stage after the hash pass, and `verify-artifact.sh` asserts the inside
  copy equals the sibling asset.
- `exec-manifest.txt` is still sibling-only. In all three tarballs above, `tar -tzf` lists no
  `exec-manifest.txt`; the sibling files list 14 entries (bmad, all `.py` scripts) and 112 (vsdd-factory).
  sideshow's `verifyExecManifest` reads it from the install source and returns nil when it is absent, so an
  install from an extracted tarball never runs the exec-bit check. Nothing fails; the check is silently off.
- The comment above step 4b in `build-bmad.sh` still says "bmad ships no executables today". The bmad
  manifest above lists 14.

## Open

Whether `exec-manifest.txt` should travel inside the tarball the way `file-manifest.csv` now does, and
whether sideshow should report "no exec manifest" rather than skip silently. Neither is decided here.
