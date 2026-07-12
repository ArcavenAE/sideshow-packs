# Pack-support candidates — how the register generalizes beyond bmad

Analysis of the next pack candidates against the pack-support register
pattern (`registry/<pack>-pack-support.yaml`), and the schema v0.2.0
fields they force. Mock registers: `registry/drafts/*-pack-support.yaml`
(draft-unvalidated; move into `registry/` proper only when a pack
onboards with evidence).

bmad was the EASY case: external upstream, npm semver releases, a real
installer, public-license content, user-scope activation. Each
candidate below breaks at least one of those assumptions.

## The candidates

### vsdd-factory (drbothen/vsdd-factory) — external, gitflow, RC-heavy

- **Structure:** Rust workspace (the factory binary) + `plugins/vsdd-factory`
  (Claude plugin — the actual content-pack surface) + `.claude/`.
- **Versioning:** gitflow, default branch `develop`. Stable release line
  dormant at v0.79.4 (2026-04-24); active line is `v1.0.0-rc.N`
  prerelease GitHub Releases (rc.22 as of 2026-07-03). "Package version
  X" requires choosing a line — the register must say which.
- **Acquisition:** no installer for content; direct-tree capture of the
  plugin dir at a tag.
- **Activation (POLICY, ratified in-session 2026-07-12):** content may
  install to user directories, but vsdd-factory is **enabled/disabled
  per repo only**, managed by sideshow. Never active by default at user
  scope. This is the first pack with a mandatory per-repo activation
  policy — schema needs an `activation` block.
- **Breaks:** single-version-line assumption; user-scope activation
  default.

### multiclaude (ArcavenAE/multiclaude-enhancements) — ours, unversioned

- **Structure:** pure content tree (agents/, commands/, skills/, rules/,
  protocols/, injection/, memory-templates/, bmad-integration/). Gen-1
  material, migrating to packs per
  `docs/atelier-review-2026-07/composition-analysis.md`.
- **Versioning:** NONE. No tags, no releases. Versions must be
  **minted by the packager** (calendar or 0.x at packaging time);
  validated brackets anchor to git SHAs, not upstream versions.
- **Acquisition:** direct-tree, likely per-slice (the finding-019 plan
  was role/process packs, e.g. `roles-multiclaude`, not one monolith).
- **Breaks:** the assumption that an upstream version exists at all.
- **Extraction caution (2026-07-12):** multiclaude and gastown each
  carry their own marvel-analog orchestration layer (multiclaude's
  supervisor/protocols machinery; gastown's workspace manager).
  Extraction takes the roles/workflows/skills and LEAVES the
  orchestration machinery — marvel is our control plane. Onboarding
  step: examine multiclaude-enhancements for what we customized vs
  what is gen-1 boilerplate (the composition-analysis doc is the
  starting map) before drawing slice boundaries.

### gastown (gastownhall/gastown) — external, extraction-only

- **Structure:** Go binary (goreleaser, semver releases, v1.2.1). The
  planned pack is NOT the software — it is the seven infra role
  definitions (mayor, polecat, crew, witness, deacon, refinery, dog;
  finding-019) extracted as a role-library pack (`roles-gastown`).
- **Acquisition:** **extraction** — an authored map from upstream
  source/docs paths to pack artifacts. The extraction map itself is
  version-sensitive content the register must track (paths move
  between upstream releases).
- **Breaks:** the assumption that the pack IS the upstream's install
  output. Pack ≠ software; consumers wanting gastown runtime install
  it separately.

### eos (ArcavenAE/eos) — ours, private, unversioned

- **Structure:** tools repo — skills/, templates/, prompts/, reference/,
  viewer/. Zero operating state by design (state lives in eos-dpg /
  function / person repos, outside pack scope).
- **Versioning:** none yet; minted-by-packager, SHA-anchored brackets
  (same as multiclaude).
- **Redistribution:** **private-channel-required.** The repo is private
  and org-sensitive (DPG/1898 context). Public sideshow-packs releases
  cannot host it — this is the F24 "separate channel" escape hatch
  becoming concrete. Distribution mechanism for private packs is
  unbuilt (wrinkle, not blocker: local `--from` install works today).
- **Breaks:** the public-redistribution assumption baked into this
  repo's release pipeline.

### Also planned (registered here for completeness, no drafts yet)

From finding-019/020 and F24: `vsdd` + `dark-factory` (aae-orc-amet,
same drbothen ecosystem as vsdd-factory), `spectacle` (aae-orc-9f7 —
first-party, trivial case), `roles-bmad` / `process-vsdd` /
`process-kos-probe` (extraction packs over content we already
package), beads-integration pack (orc F6), fleet-bootstrap
(aae-orc-0jl), forestage persona/theme packs (orc F12).

## Schema v0.2.0 — fields the candidates force

Additive; existing bmad register stays valid (defaults reproduce
v0.1.0 behavior):

```yaml
version_scheme: semver-npm | semver-releases | minted-by-packager
  # bmad: semver-npm. vsdd-factory: semver-releases (+ line selection).
  # multiclaude/eos: minted-by-packager.

release_line: stable | prerelease | <branch>   # vsdd-factory: which line
  # a validated bracket applies to. Default stable.

acquisition:
  method: installer | direct-tree | extraction
  # installer: bmad (run upstream installer in CI).
  # direct-tree: vsdd-factory plugins/, multiclaude slices, eos tools.
  # extraction: gastown roles — requires an extraction_map:
  extraction_map:                # extraction only
    - from: <upstream path>
      to: <pack path>

redistribution: public-ok | private-channel-required
  # eos: private-channel-required. Gate: the publish path must refuse
  # public release creation for private-channel packs.

activation:
  default_scope: user | per-repo
  per_repo_required: true|false   # vsdd-factory: true (ratified 2026-07-12)
  rationale: <why>

validated:                        # bracket refs generalize:
  - min: <version>                # versioned upstreams (bmad, vsdd-factory)
    max: <version>
  - ref: <git sha>                # unversioned upstreams (multiclaude, eos)
    minted_version: <what we called it>
```

`check-support.sh` implications: sha-anchored brackets can't do range
math — for minted-scheme packs the gate degrades to exact-ref match
(you validated THIS sha) + guidance, which is the honest semantics
anyway. Per-repo activation enforcement belongs to sideshow (consumer
side, Binding abstraction aae-orc-f13j), not this repo's gate; the
register is where the policy is declared so both sides read one source.

## Onboarding order (proposal)

1. **spectacle** — first-party, trivial, exercises minted-versioning
   with zero risk (aae-orc-9f7 wanted exactly this validation).
2. **vsdd-factory** — forces release_line + activation blocks;
   real external demand (aae-orc-amet).
3. **multiclaude** — sha-anchored brackets; per-slice packs align with
   the composition-analysis migration already underway.
4. **eos** — waits on the private-channel decision (smallest viable:
   private GitHub releases on a private mirror repo + same cosign flow).
5. **gastown roles** — waits on extraction_map authoring; lowest urgency.
