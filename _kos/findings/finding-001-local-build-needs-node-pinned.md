# finding-001: a local build-bmad.sh run fails before the installer when no node version is selected

**Date:** 2026-09-27
**Subject:** running `scripts/build-bmad.sh` outside CI
**Occasion:** building bmad 6.12.0-r2 ahead of its tag (aae-orc-jxaij), from main at `c0f0aaf`
**Evidence:** local build log, 2026-09-27; `.github/workflows/build-pack.yml:72-74`
(`actions/setup-node`, `node-version: '24'`); `mise ls node` on the build host.

## Why this is worth writing down

A local build is how a release is prepared and checked before its tag starts
the signing and publishing run. If a local build stops on the host's tool
selection, the check before the release is the step that gets skipped.

## Symptom

`BMAD_VERSION=6.12.0 ... scripts/build-bmad.sh` exited 1 before invoking the
upstream installer. The tail of its output, verbatim:

```
Set a global default version with one of the following:
mise use -g node@24.18.0
mise use -g node@25.9.0
mise ERROR Version: 2026.7.18 macos-arm64 (2026-07-30)
mise ERROR Run with --verbose or MISE_VERBOSE=1 for more information
```

## Cause

`npx` on this host is a mise shim. The repository selects no node version
(no `mise.toml`, `.tool-versions`, `.node-version` or `.nvmrc`), and the
host has no global default, so the shim refuses to pick one. CI never sees
this because `setup-node` pins node 24 before the build step.

## Workaround applied

Run the one command under CI's node major, without changing any config:

```sh
mise exec node@24.18.0 -- env BMAD_VERSION=6.12.0 ... scripts/build-bmad.sh
```

The build then ran to completion (rc 0) and produced an artifact whose
external-module pins and shas match the published base release.

## Open

Whether the repository should pin node to match CI (a `mise.toml` or
`.node-version` with `24`) is a repo decision, not taken here. The workaround
is enough for a one-off build; a pin would keep a local build on the same node
major as the published one.
