# vsdd-factory 1.0.0-rc.25: release notes

Attach as the body of the `vsdd-factory-v1.0.0-rc.25` draft release. The
pipeline creates releases as drafts with no body, so this text is authored,
not generated.

File count below is from the verified test build (run 34280184572); the signed
release rebuilds the same tree, so confirm it matches before publishing.

---

Frozen capture of the `vsdd-factory` Claude plugin at upstream
`v1.0.0-rc.25`, signed and attested. Prerelease line: this tracks upstream's
own `rc` sequence and carries no stability promise beyond theirs.

**Upgrade promptly.** Upstream's headline for rc.25 is a HIGH-severity
sandbox-escape fix in the WASM runtime that every hook plugin executes inside
(wasmtime and wasmtime-wasi 46.0.2 to 46.0.3, clearing RUSTSEC-2026-0269 HIGH
and RUSTSEC-2026-0268 MEDIUM). The fix lives inside the committed dispatcher
binaries, so it arrives only by moving to this version.

On this channel there is no machine-wide upgrade. Bindings pin absolute store
version directories on purpose, so each repo moves on its own:

```sh
sideshow disable vsdd-factory --repo <path>
sideshow enable  vsdd-factory@1.0.0-rc.25 --repo <path>
```

**Pinned to a commit, not a tag.** Upstream force-moves release tags by
design, so a tag is not a stable identifier for a signed artifact. This build
pins:

```
tag object  fdfb5133e26aa812efd17af2d1db9e493d016abf
commit      51023185658350afaacaa931a175103d915d14ba
```

If you verify this artifact against upstream and the tag now points somewhere
else, the commit above is the authority for what we packaged.

## Verify

```sh
cosign verify-blob \
  --bundle vsdd-factory-1.0.0-rc.25-arcaven.tar.gz.bundle \
  --certificate-identity-regexp 'github.com/ArcavenAE/sideshow-packs' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  vsdd-factory-1.0.0-rc.25-arcaven.tar.gz
```

`exec-manifest.txt` carries the executable-bit census, and
`file-manifest.csv` lists **1279** files with per-file digests.

## What changed since rc.24

14 commits, 200 files, 54 of them inside `plugins/vsdd-factory`. Upstream's
own notes are the authority on behavior:
https://github.com/drbothen/vsdd-factory/releases/tag/v1.0.0-rc.25

For packaging, three things are worth knowing.

**The executable census moves 117 → 118, and it is not additive this time.**
Two files gained the bit and one lost it:

| change | file | why |
|---|---|---|
| added | `hook-plugins/stamp-state-timestamp.wasm` | new PostToolUse hook (S-17.05) |
| added | `hook-plugins/validate-unvalidated-mutation-marker.wasm` | new next-advance gate (S-25.01) |
| mode 755 → 644 | `hook-plugins/verify-state-timestamp-refresh.wasm` | registry entry deleted; superseded by `stamp-state-timestamp` per ADR-046. The file still ships |

rc.24's notes could say "zero removals" as a clean signal. That sentence is
not available here, and a count alone would not have shown it: +2 and −1 net
to +1. The census delta above is a set comparison, which is the form this
check needs going forward.

**Two shipped WASM plugins are dispatched by neither registry.**
`last-amended-migrate.wasm` and `verify-state-timestamp-refresh.wasm` appear
in `hook-plugins/` with no entry in `hooks-registry.toml` or
`resolvers-registry.toml`. They are inert weight, not executed content: the
dispatcher loads by registry path, so an unreferenced plugin never runs. The
set is recorded in the signed `install.meta` under `content.wasm_orphans` and
in `wasm-orphans.txt`, so it is a stated fact rather than something you have
to discover.

Upstream's own `crates/last-amended-migrate/Cargo.toml` describes that crate
as a "Standalone native CLI binary — NOT a WASM hook plugin", which is the
same shape as the `policy15-attestation-gate.wasm` orphan rc.25 removes and
guards against. This one appears to have arrived after the guard.

**The registry grew a new `on_error` variant.** `block_if_marker` (ADR-048)
is used by five entries and requires the rc.25 dispatcher; upstream notes that
an older dispatcher against this registry fails registry-load validation. On
this channel that pairing is structural. Bindings pin one absolute store
version directory and both files come from it, so a store flip cannot
retarget a bound repo into a skew.

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

Bracket-validated: the register carries a single-rung `1.0.0-rc.25` bracket
pinned to the commit above. All five pipeline assumptions verified at the
source level, and three coherence gates ran on this build: the top-level unit
census (17 units, all dispositioned in the register), wasm/registry
reconciliation (the two orphans above), and the un-rewritten-reference count.

The comparison was done through the GitHub compare and tree APIs rather than
by mirroring the repository, keeping third-party content out of local working
trees.

## Channel divergence, measured

`install.meta` records **25 namespace references in 13 store-reference files**
under `channel_divergence`. These name `/vsdd-factory:<command>` forms that do
not resolve on the repo-bindings channel, where the addressing is the prefixed
bare name (`vsdd-<command>`). The bind-time rewrite reaches materialize units
only, because the store is byte-frozen by design.

Two are compiled into WASM (`validate-artifact-path`,
`warn-pending-wave-gate`) and two are in `templates/` that get copied into
your own `.factory/` state. If a hook or a doc tells you to run
`/vsdd-factory:compact-state`, the command on this channel is
`vsdd-compact-state`.

## Artifact digest

The published tarball's own `sha256` is recorded in the release assets and in
the signed `install.meta`. Verify against those rather than against any digest
transcribed into prose. A hash copied by hand is a hash nobody checked.

```sh
shasum -a 256 vsdd-factory-1.0.0-rc.25-arcaven.tar.gz
```
