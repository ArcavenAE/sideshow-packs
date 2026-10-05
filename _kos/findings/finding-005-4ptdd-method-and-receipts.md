# finding-005: 4ptdd method and receipts, how eight parity faults were counted against a native bmad install

**Date:** 2026-10-05
**Subject:** the four-round panel run that measured an installed sideshow bmad pack against a native `bmad-method@6.12.1` install
**Occasion:** tracking issue sideshow-packs#43; the design and fault ledger are in sideshow-packs#44
**Evidence:** the party record of four rounds (one brief, five seat replies and one synthesis per round), the F-j settings variants and `claude -p` results, the F-k read-only session result, and the coexist-check output. The record is a gitignored session artifact, not in any repo; this finding is its durable summary.

## Why this is worth writing down

#44 states what the eight faults are. It cannot carry how each was counted, who dissented, or what was ruled out on evidence, and those decide whether a future panel can trust the count or only repeat it. The record lives in a gitignored directory that disappears with the session.

Party records use seat labels, never persona names. The seats here: distribution, runtime, cc-internals, evals, observability, and the architect who ran the checks.

## Method

**Oracle.** A native install of `bmad-method@6.12.1` with the register's six modules (`bmm,cis,gds,tea,bmb,wds`): 102 skills plus the `_bmad/` tree. A four-module oracle (82 skills) served as the control for the local build default. Round 1 first used the four-module oracle against a six-module published pack; runtime caught it, and round 2 rebuilt the oracle. Node is pinned per command, as finding-001 records.

**Counting rule** (round 1, evals, unopposed). A fault counts only if (1) its check fails on the unfixed artifact, (2) the comparison is to native, (3) a user sees the difference, and (4) its root cause is distinct. Pack and tool halves of one symptom are one fault.

**Comparison set** (agreed round 1, run in scratch HOMEs, never against a real config dir): skill set, skill bytes after removing the declared rewrite, `_bmad/` tree, reference closure (`test -e` from a bound repo), resolved config, and the doctor and status verdicts.

**Checks on panelist claims.** The architect ran one command per claim. Of the 15 round 1 checks, 13 confirmed the claim, one refuted it (the ask that r2 lacks bmb and wds; r2 ships both, with 102 SKILL.md entries), and one showed upstream behavior and was dropped: the dangling `skill-manifest.csv` paths exist in native too.

## Tally

Eight faults counted. Votes are seat counts.

| Fault | Votes | Note |
|---|---|---|
| F-a census stale after the CI-identity neutralizer; doctor fails on a clean install | 5 of 5 | sideshow-packs#41, finding-004 |
| F-c `user_name` and `project_name` absent | 3 of 4, then 5 of 5 | counted after a behavior check, below |
| F-d `_bmad/wds/config.yaml` unresolved from a bound repo | 4 of 4 | |
| F-f status silent on an unsynced pack | 5 of 5 | |
| F-g Read permission written outside `CLAUDE_CONFIG_DIR` | 4 of 4 | folded with closed sideshow#136 |
| F-i doctor says a bound repo has no sideshow content | 4 of 5 | runtime dissents |
| F-j the Read rule install writes matches nothing | 5 of 5 | observed, below |
| F-k user-scope pack skills shadow a repo's own native install | 5 of 5 | preflight false-clean measured; shadowing observed |

Not counted: F-b (bracket refuses 6.12.1; 1 of 4, scheduled as work anyway), F-e (merged into F-d, 4 of 5 to split), F-h (local default of four modules; hygiene ticket).

After round 2 the panel had counted five faults, with F-i, F-j and F-k found but unvoted. The bar of eight was met by measurement, not by padding: round 2 said the result would go to director as "seven measured" if round 3 could not support the rest.

**F-c behavior check.** 152 skills greet `{user_name}`, 103 write `{project_name}` or `{{project_name}}` into document headers, and 20 write `**Author:** {{user_name}}`. The module `config.yaml` reads are rewritten to the shared store copies, which carry neither key. That moved F-c from 3 of 4 to counting.

## Ruled out on evidence

| Candidate | Check | Result |
|---|---|---|
| edited bound skill (the bound-skill path; sideshow#90's rules path was not measured) | append to a bound `SKILL.md`, `commands sync`, grep | edit gone; native `install --action update` also drops it. Parity holds for bound skills; says nothing about #90 |
| party roster (sideshow#121) | `resolve_party.py` bound vs native | byte-identical JSON, 20 members. Not reproducible on 6.12.1; 6.10.0 untested |
| `enable` for bmad (sideshow#111), fixed by sideshow#134 | `sideshow enable bmad@6.12.1` and `bmad@6.12.0`, with only 6.12.1 installed | `enable bmad@<installed version>` reaches the layout check and is refused as not a plugin-layout tree. Version resolution, #111's path, runs first (`resolveStore`, `internal/enable/enable.go:92`, before `DiscoverPluginLayout` at `:100`) and was changed by sideshow#134 (1725c12). A version not installed gives "is not installed". The issue's reported case was not re-tested |
| render write target | `render_skill.py` for `bmad-build`, native and bound | both HALT with "ambiguous config value implementation_artifacts" when bmm and gds are both installed. Upstream defect; parity holds |
| residual home-dir sites | read the three call sites | data dir default and `~` expansion are correct; only `permissions.go:33` is a fault (F-g) |
| dangling skill-manifest paths | `test -e` on the first three | dangling in native too |

## F-j, observed

Claude Code 2.1.289, a scratch project, a store file outside it, four `--settings` files, `--setting-sources project,local` (user settings excluded), `--permission-mode default`, `claude -p` with JSON output. Control: a file inside the project.

| Variant | Rule | Inside read | Store read | permission_denials |
|---|---|---|---|---|
| A | none | ok | no | the store file |
| B | `Read(<abs>/packs/)` (the form install writes) | ok | no | the store file |
| C | `Read(//<abs>/packs/**)` | ok | ok | none |
| D | `Read(//<abs>/packs/)` | ok | ok | none |

The generated form matches nothing, exactly like having no rule. The `//` anchor is the whole difference; the missing `**` does not matter (D). A `--settings` file anchors a single-slash path at its own directory and user settings anchor it at `~/.claude/` (permissions docs), so the result carries to user settings.

## F-k, observed

A private repo with a native bmad 6.2.2 install of 98 skills shares 86 names with the user-scope skills sideshow bound from 6.10.0. A read-only `claude -p` there (Bash, Edit, Write and web tools disallowed) was asked to invoke `bmad-help` and quote its catalog line. It loaded the user-scope copy: the line it quoted exists only in the sideshow copy. The working tree was unchanged. Separately, `coexist-check` printed "all checks clean" and exited 0 while all 102 skill names collided in a copy of the native install committed as a repo. The Claude Code skills docs rank personal over project skills; the false-clean preflight is the measured half.

Side observation, not counted: `project init` in that repo wrote a `.gitignore` that matches 2,019 tracked files with no note.

## #41 record location

`install.meta` is a release asset only: absent from the tarball and the store. The in-store `pack.yaml` carries no rewrite record. Any record doctor reads at runtime must live in `pack.yaml`. Common ground, accepted 5 to 0: the build refreshes `_config/files-manifest.csv` after the neutralizer and re-runs the census on the staged tree, a rewrite record with the neutralizer rule version lives in `pack.yaml`, doctor reports that record as info and never as an exemption, and a negative control (editing a rewritten file after install must still fail doctor) is kept.

## Dissents and the open split

- **F-i, runtime:** native has no doctor to compare to, and it blocks no skill from working. Ticketed, not counted by runtime.
- **F-d shape, 3 to 2** for doing both (links derived from the pack's top-level dirs gate the release; widening the rewrite to every text file follows in the sideshow alpha). Distribution and runtime voted links only; distribution notes that widening the rewrite is hygiene, not the F-d fix. Runtime's condition: the links gate the release, and the rewrite must not alter any byte the parity comparison checks beyond the declared rewrite.
- **F-k placement (3 to 2 in the panel, since ruled):** distribution and runtime for binding at project scope; cc-internals, evals and observability for a detection floor. cc-internals' point against project scope as stated: personal scope outranks project scope, so a project binding still loses unless the user-scope binding is also removed. That changes what a user-wide install means, so it went to director as a ruling request.
- **F-k ruling, 2026-10-05:** option 3, keep user scope and warn. `coexist-check` names every skill that collides between a repo's own `.claude/skills` and the user-scope bindings, and which copy the harness loads, shipping in the sideshow alpha as aae-orc-phytt. Option 1 (project-scope binding) was not taken. #44 records the ruling.

## What this adds beyond #44

The counting rule, the checks that dropped candidates, and the dissents. The F-j and F-k measurements are the only two faults whose count depended on a harness observation rather than a code read; both were taken read-only from a logged-in session with no change to any settings file.

## Open

- Whether the counting rule should be written into a requirement, or stay in this record.
