# bmad v6.12.1: installed pack parity with a native install

Status: design, for review. Tracking: [ArcavenAE/sideshow-packs#43](https://github.com/ArcavenAE/sideshow-packs/issues/43). Fault ledger: [`docs/faults/bmad-v6.12.1-ledger.md`](../faults/bmad-v6.12.1-ledger.md).

## Why

A sideshow bmad pack should behave like a native `bmad-method` install of the same release. Today it does not, in eight measured ways. Two of them are visible on the first command a user runs: `doctor` fails on a clean install, and `status` reports a pack that does nothing as if it were fine. The goal is to publish 6.12.1 with those faults found, each with a failing check written first, and fixed or knowingly deferred.

## Scope

The packaging in this repo (build, register, release) and the sideshow paths a bmad user touches: install, `commands sync`, `project init`, `status`, `doctor`, `coexist-check`, and the permissions install writes. Out of scope: bmad's own upstream behavior, except where it decides what native means.

## Method

**Oracle.** A native install of `bmad-method@6.12.1` with the register's six modules:

```sh
mise exec node@24.18.0 -- npx -y bmad-method@6.12.1 install --directory "$N" \
  --modules bmm,cis,gds,tea,bmb,wds --tools claude-code --action install \
  --user-name scratch --yes
```

Node is pinned per command (finding-001). The result: 102 skills under `.claude/skills` plus the `_bmad/` tree. A four-module oracle (82 skills) served as a control for the local build default.

**Installed side.** Each in its own scratch HOME so bindings never touch a real config dir:

- A: the published `bmad-v6.12.0-r2` asset.
- B: a local build of 6.12.1 with the six register modules. The build refuses 6.12.1 by default, so B used `ALLOW_UNSUPPORTED=1` for measurement only; it was never published.
- C: B with `CLAUDE_CONFIG_DIR` set to a separate dir.

On each: `sideshow install bmad --from <dir>`, `sideshow commands sync`, then `sideshow project init bmad` in a fresh git repo.

**Comparisons.** B against the oracle, because A mixes the 6.12.0 to 6.12.1 delta into every diff.

1. Skill set: names in native `.claude/skills` against the bound skills dir.
2. Skill bytes: `diff -rq` on the intersection, then each differing file normalized by removing the declared rewrite (store path back to `{project-root}/_bmad/`, the fallback block stripped).
3. Tree: native `_bmad/` against the store, by relative path; then content on the shared paths.
4. Reference closure: every `{project-root}/_bmad/...` path still present in bound skills, `test -e` from the bound repo, kept only where native resolves it.
5. Resolved config: `resolve_config.py` output in the bound repo against native, flattened key by key.
6. Executable bits.
7. Tool verdicts: `doctor`, `status`, `coexist-check` on a clean install and in a bound repo.
8. Harness observations on Claude Code 2.1.289, with `claude -p` in scratch projects or read-only, never changing a real settings file.

**Counting rule.** A fault counts only if its check fails on the unfixed artifact, the comparison is to native, a user sees the difference, and the root cause is distinct. The ledger applies it row by row.

## Results

Parity holds on the content: 102 of 102 skills, and every one of the 189 differing skill files is the declared rewrite and nothing else. Resolved config matches on 156 of 158 keys.

The faults are in what the pack and the tool do around that content:

| # | Fault | Lands in |
|---|---|---|
| F-a | census stale after the CI-identity neutralizer; doctor fails on a clean install | sideshow-packs, plus doctor info in sideshow |
| F-c | `user_name` and `project_name` absent; 152 skills greet a name that never resolves | sideshow |
| F-d | `_bmad/wds/config.yaml` unresolved from a bound repo | sideshow-packs (links), sideshow (rewrite) |
| F-f | status silent on an unsynced pack | sideshow |
| F-g | Read permission written outside `CLAUDE_CONFIG_DIR` | sideshow |
| F-i | doctor tells a bound repo it has no sideshow content | sideshow |
| F-j | the written Read rule matches nothing | sideshow |
| F-k | user-scope pack skills shadow a repo's own native install; preflight says clean | sideshow |

Two observations carry most of the weight, so here is how each was taken.

**F-j.** A scratch project and a store file outside it, four `--settings` files, `--setting-sources project,local` (user settings excluded), `--permission-mode default`. The form install writes, `Read(<abs>/packs/)`, was denied exactly like no rule. `Read(//<abs>/packs/**)` and `Read(//<abs>/packs/)` were allowed. A control read inside the project passed in all four. A single leading slash anchors at the settings source, never the filesystem root, so the result carries to user settings, where it anchors at `~/.claude/`.

**F-k.** Claude Code gives personal skills priority over project skills. A private repo with a native bmad 6.2.2 install of 98 skills shares 86 names with the user-scope skills sideshow bound from 6.10.0. A read-only `claude -p` there, with Bash and write tools disallowed, loaded the user-scope `bmad-help`: the catalog line it quoted exists only in the sideshow copy. The working tree was unchanged.

## Plan

Flat tickets, one repo each. Edges are recorded in bd.

**Before the 6.12.1 release build (sideshow-packs):**

| Ticket | Work | Red check today |
|---|---|---|
| aae-orc-y49j2 | extend the support bracket to 6.12.1 through the revalidation runbook | `scripts/check-support.sh bmad 6.12.1` exits 2 |
| aae-orc-hu9z2 | refresh census hashes after the neutralizer; re-run the census on the staged tree and fail closed; record rewritten files, installer hashes and the neutralizer rule version in the in-store `pack.yaml` | doctor census fail on a clean install |
| aae-orc-ytwiv | derive `runtime_links` from the staged top-level module dirs, excluding `custom` and `render` | `test -e _bmad/wds/config.yaml` in a bound repo exits 1 |
| aae-orc-lw82d | read the local build default from the register | default build ships 82 skills |
| aae-orc-ln72i | publish 6.12.1 through the signed path; blocked by the four above | (reachability below) |

**Following sideshow alpha (no pack bytes change):**

| Ticket | Work | Needs |
|---|---|---|
| aae-orc-jy1j | `project init bmad` seeds `user_name` and `project_name` when absent | |
| aae-orc-zfkxy | status prints an unwired line when synced is below available | |
| aae-orc-89cxz | permission settings path through `foreign.ConfigDir()` | |
| aae-orc-8qmpi | write absolute Read rules with the `//` anchor | aae-orc-89cxz |
| aae-orc-phytt | coexist-check reports skills shadowed between project and user scope | |
| aae-orc-edg8t | doctor cwd-known counts `project init` registrations | |
| aae-orc-psih9 | doctor prints the declared rewrite record as info, never as an exemption | aae-orc-hu9z2 |
| aae-orc-k5vro | rewrite every text file under a bound skill, not only markdown | |

**Release notes** for 6.12.1 carry the pin composition (packs#36), the 102-skill count checked against the register by `verify-artifact.sh`, and a plain list of what needs the sideshow alpha. The pack must not claim a fix that ships only in sideshow.

**Reachability.** Each ticket names its own. For the release as a whole: in a fresh scratch HOME, download the release assets, verify the signature, install, sync, `project init` in a fresh repo, then rerun comparisons 1 to 7 against native 6.12.1. Pass means skill set equal, zero residual after the declared rewrite, census ok, and the F-d path resolving.

## Decisions taken in the design party

- **#41 shape (5 to 0).** Refresh the hashes in the build rather than teach doctor a subtraction list. The record of what was rewritten lives in the in-store `pack.yaml`, because `install.meta` is a release asset and never reaches the store. Doctor reports it as info only. A test proves that an edit to a rewritten file after install still fails the census.
- **F-d shape (3 to 2).** Derived links gate the release; widening the rewrite follows in the alpha, counted once, and must not change bytes the parity comparison checks beyond the declared rewrite. Dissent (distribution, runtime): links alone remove the divergence, and widening the rewrite adds divergence.
- **F-i counts (4 to 1).** Dissent (runtime): native has no doctor to compare against, and the fault blocks no skill.

## Pending ruling

**Where skills go when a repo has its own native install (F-k).** The panel split 3 to 2:

1. Project-scope binding. Personal outranks project, so this works only if the user-scope binding is also removed or narrowed, which changes what a user-wide install means.
2. Refuse to bind. A user-scope binding is machine-wide, so refusing in one repo unbinds nothing.
3. Keep user scope and warn (aae-orc-phytt).

Recommended default: 3 now, as the floor; it ships under any ruling. The ruling on 1 is the operator's. This recommendation is valid until the 6.12.1 release build starts; it will be re-checked then.

## Candidate requirements (provisional, not ratified)

- **R-p1 (provisional; source: F-a measurement).** A published pack's census verifies on a clean install with zero mismatches.
- **R-p2 (provisional; source: F-d, comparison 4).** Every `{project-root}/_bmad/` reference that resolves in a native install of the same release and modules also resolves from a repo bound with `project init`.
- **R-p3 (provisional; source: F-j observation).** Any permission rule sideshow writes is one Claude Code matches against the path it names, shown by a harness check.
- **R-p4 (provisional; source: comparison 2).** Bound skill bytes equal native after removing only the declared rewrite.

## Upstream note

bmad 6.12.1 `render_skill.py` halts for `bmad-build` and `bmad-build-auto` when bmm and gds are both installed (`ambiguous config value implementation_artifacts`). It fails the same way on native, so it is not ours to fix. It may be worth an upstream report after a prior-art search.
