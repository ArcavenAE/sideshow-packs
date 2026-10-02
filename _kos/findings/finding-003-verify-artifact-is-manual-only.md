# finding-003: verify-artifact.sh is run by hand only, and the runbook did not say so

**Date:** 2026-10-02
**Subject:** how a built artifact is verified before its bracket is extended or it is published
**Occasion:** review of sideshow-packs#40 (aae-orc-xorml)
**Evidence:** `.github/workflows/` at `40a45a7` (no workflow calls `scripts/verify-artifact.sh`);
`registry/pack-support-revalidation-runbook.md` Step 3 before and after commit `85fd4c4`.

## Why this is worth writing down

A check that only runs when someone remembers to run it is only as strong as the document that tells them
to. Before `85fd4c4`, Step 3 listed what to look at but never named the script, never said CI does not run
it, and could not warn that a new check fails on releases published before that check existed.

## What was observed

- No workflow invokes `verify-artifact.sh`. Its header calls it "runbook Step 3, as a command instead of a
  checklist".
- #40 added a check that fails on every release published before it ("tarball carries no
  file-manifest.csv"). The PR body said the runbook covered this; the review found it did not, and Step 3 was
  amended in `85fd4c4` to name the command, say CI does not run it, and mark that one FAIL as expected for
  older releases.

## Open

Whether CI should run `verify-artifact.sh` on every build. Its checks are structural (composition, pins,
pack.yaml, manifest equality), so gating on them would not conflict with the diagnostic-not-gate rule, but
the census-delta band is a judgment threshold and would need its own decision.
