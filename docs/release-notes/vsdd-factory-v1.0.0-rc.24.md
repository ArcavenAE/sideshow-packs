# vsdd-factory 1.0.0-rc.24 — release notes

Attach as the body of the `vsdd-factory-v1.0.0-rc.24` draft release. The
pipeline creates releases as drafts with no body, so this text is authored,
not generated.

One value must be filled from the built artifact before publishing, marked
`<fill>` below.

---

Frozen capture of the `vsdd-factory` Claude plugin at upstream
`v1.0.0-rc.24`, signed and attested. Prerelease line: this tracks upstream's
own `rc` sequence and carries no stability promise beyond theirs.

**Pinned to a commit, not a tag.** Upstream force-moves release tags by
design, so a tag is not a stable identifier for a signed artifact. This build
pins:

```
tag object  2f97d5e91b2c70da97c5a0156770b577f5e22416
commit      89f6f87cf476b1f57d979962eabf0d9b20a49e69
```

If you verify this artifact against upstream and the tag now points somewhere
else, the commit above is the authority for what we packaged.

## Verify

```sh
cosign verify-blob \
  --bundle vsdd-factory-1.0.0-rc.24-arcaven.tar.gz.bundle \
  --certificate-identity-regexp 'github.com/ArcavenAE/sideshow-packs' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  vsdd-factory-1.0.0-rc.24-arcaven.tar.gz
```

`exec-manifest.txt` carries the executable-bit census, and
`file-manifest.csv` lists `<fill: file count>` files with per-file digests.

## What changed since rc.23

56 commits, 261 files. The substance is in the Rust dispatcher
(`crates/factory-dispatcher/`), the plugin's phase workflows, and the release
and CI plumbing. Upstream's own notes are the authority on behavior:
https://github.com/DrBothen/vsdd-factory/releases/tag/v1.0.0-rc.24

For packaging, the meaningful delta is the executable surface. The census
moves **112 → 117**, and it is purely additive — five files gained the
executable bit, none lost it:

| added | kind |
|---|---|
| `hook-plugins/validate-cross-site-correspondence.wasm` | hook plugin |
| `hook-plugins/validate-factory-path-staging.wasm` | hook plugin |
| `hook-plugins/verify-state-timestamp-advisory.wasm` | hook plugin |
| `tests/fixtures/pr-manager-trunk/gh` | test fixture |
| `tests/fixtures/pr-manager-trunk/git` | test fixture |

Three new validating hook plugins and two fake CLI fixtures for a trunk-mode
PR-manager test. Zero removals is the clean signal here: a dropped executable
would have meant content going missing rather than arriving.

The build gate needed no adjustment for this. It derives the expected count
from the tag's own tree and compares it against what staging produced, so it
verifies that capture preserved the executable bits rather than checking
against a stored number — it expects 117 here on its own.

## Enablement

This is a plugin-class pack: it activates per-repo through repo-bindings,
not through user-scope binding sync. `sideshow commands sync` will tell you
so rather than binding it globally.

```sh
sideshow enable vsdd-factory --repo <path>
sideshow coexist-check vsdd-factory --repo <path>   # ten-check preflight
sideshow disable vsdd-factory --repo <path>          # exact ledger-replay reversal
```

See the pack's enablement runbook for the full sequence.

## Packaging-support status

Verified against all five pipeline assumptions at the source level:
`plugins/vsdd-factory` is present and complete (2072 paths), the Claude
plugin manifest is present at `.claude-plugin/plugin.json`, no cargo build is
required because prebuilt dispatcher binaries still ship in-tree under
`bin/`, the exec-bit census is accounted for above, and the Claude Code
harness floor is advisory and unchanged.

The comparison was done through the GitHub compare and tree APIs rather than
by mirroring the repository, keeping third-party content out of local working
trees.

`install.meta.yaml` declares the validated-support state honestly. Check it
before treating this artifact as bracket-validated.

## Artifact digest

```
sha256  <fill: from the release asset>
```
