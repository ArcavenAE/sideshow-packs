# finding-004: the identity neutralization edits nine bmad config files after bmad records their hashes

**Date:** 2026-10-02
**Subject:** `scripts/neutralize-ci-identity.py` and bmad's own `_config/files-manifest.csv`
**Occasion:** an end-to-end doctor run while building aae-orc-xorml half 2 (sideshow#139)
**Evidence:** sideshow-packs#41; a fresh-store install of the published bmad-v6.12.0-r2 and `sideshow doctor`;
a recompute of `_config/files-manifest.csv` against the extracted r2 tree.

## Why this is worth writing down

Every user who installs r2 and runs `sideshow doctor` gets a structural FAIL on a clean install. A census
that reports tampering when nothing changed teaches people to ignore the census.

## What was observed

`sideshow doctor` after a clean r2 install:

```
[fail] store-content-census: bmad 6.12.0: 9 of 74 census entries differ from the store tree (first: bmb/config.yaml, bmm/config.yaml, cis/config.yaml); 1948 entries name paths not present in this layout
```

The recompute gives the same nine: every module's `config.yaml`, plus `config.toml` and `config.user.toml`.
Each has a basename in the neutralizer's `CONFIG_BASENAMES`, and no other resolved entry differs. The
pipeline's own `file-manifest.csv` is computed after the edit and matches all 2023 files.

## Likely cause

It looks like the neutralize step (added in #34) rewrites these files after the upstream installer has
written their hashes into its own census, and nothing refreshes those hashes.

## Open

Tracked as #41: refresh the edited files' hashes in `_config/files-manifest.csv`, or record them as
intentionally rewritten. No fix yet.
