# bmad v6.12.1 fault ledger: installed sideshow pack against a native install

Tracking: [ArcavenAE/sideshow-packs#43](https://github.com/ArcavenAE/sideshow-packs/issues/43). Design and method: [`docs/design/bmad-v6.12.1-native-parity.md`](../design/bmad-v6.12.1-native-parity.md).

A row is a fault only if all four hold (counting rule, ruled in round 1 of the design party):

1. Its check fails on the unfixed artifact, and was seen to fail once.
2. The check compares against a native install of the same release, not against our own expectation.
3. The difference changes what a user sees: a skill missing, a wrong value, a false doctor verdict, a broken command, a prompt.
4. It is distinct by root cause. One flaw showing in nine files is one fault; the pack and tool halves of one symptom are one fault.

Oracle: `bmad-method@6.12.1`, modules `bmm,cis,gds,tea,bmb,wds` (the register's `default_modules`), `--tools claude-code`, Node 24.18.0 pinned per command. Installed side: sideshow `0.1.0-alpha.20261004.181713.0346b11`, a local build of 6.12.1 from `main` at b910aba, in a scratch HOME. Claude Code 2.1.289 for harness observations.

## Counted faults

| # | Fault | Evidence: native vs sideshow (command) | Failing check | Fix ticket | Fix PR | Status |
|---|---|---|---|---|---|---|
| F-a | Doctor fails its census on a clean install (packs#41) | Native self-census 74 ok, 0 mismatch. `sideshow doctor bmad --layer 1`: `store-content-census` fail, 9 of 74 differ, on both the published r2 and a 6.12.1 build | `sideshow doctor bmad --layer 1 --json`, census status is fail | aae-orc-hu9z2 (pack), aae-orc-psih9 (doctor info) | | open |
| F-c | `user_name` and `project_name` absent from resolved config | `resolve_config.py`, bound repo vs native: 156 of 158 keys equal; native `scratch` and `proj`, sideshow absent. 152 native skills greet `{user_name}`; 103 write `{project_name}` into document headers | empty output from `resolve_config.py --key core.user_name` in a bound repo (it exits 0 on a missing key) | aae-orc-jy1j | | open |
| F-d | `_bmad/wds/config.yaml` does not resolve from a bound repo | Native: exists. Bound repo: `test -e _bmad/wds/config.yaml` exits 1; `wds-3-scenarios/workflow.xml` reads it (3 refs), and the rewrite skips non-markdown files | `test -e "$REPO/_bmad/wds/config.yaml"` | aae-orc-ytwiv (pack, gates release), aae-orc-k5vro (rewrite) | | open |
| F-f | Status is silent on an unsynced pack (sideshow#85) | Native: skills usable on install. `sideshow status` after install: `available: 102`, `synced: 0`, exit 0, no warning | status shows no unwired line while synced is below available | aae-orc-zfkxy | | open |
| F-g | Read permission written outside `CLAUDE_CONFIG_DIR` | With `CLAUDE_CONFIG_DIR=$C`: skills bind to `$C/skills` (102), the rule lands in `$HOME/.claude/settings.json` | `test -f "$C/settings.json"` after install | aae-orc-89cxz | | open |
| F-i | Doctor says a bound repo has no sideshow content | In a repo where `project init bmad` ran and `status` lists it, `doctor --repo .` warns `cwd-known: ... an agent started here finds no sideshow-managed content` and recommends `enable`, which refuses bmad | cwd-known status is warn in a bound repo | aae-orc-edg8t | | open; counted 4 to 1 |
| F-j | The Read rule install writes matches nothing | Native needs no rule. Observed with `claude -p` and a `--settings` file: the written form `Read(<abs>/packs/)` is denied exactly like no rule; `Read(//<abs>/...)` is allowed; a control read inside the project passes in every variant | written rule does not start with `Read(//` (or `Read(~/`) | aae-orc-8qmpi (needs aae-orc-89cxz) | | open |
| F-k | User-scope pack skills shadow a repo's own native install; preflight says clean | Copy of the native install committed as a repo: `coexist-check` exits 0 "all checks clean" with 102 names in both scopes. Observed read-only in a private repo with a native 6.2.2 install: the session loaded the user-scope sideshow 6.10.0 `bmad-help` | `sideshow coexist-check bmad --repo .` exits 0 in that repo | aae-orc-phytt (detection); placement is a pending ruling | | open |

Eight counted. F-i carries a recorded dissent (runtime seat: native has no doctor to compare, and it blocks no skill).

## Work that ships with the release and does not count

| Item | Evidence | Ticket |
|---|---|---|
| Build refuses 6.12.1 | `build-bmad.sh` with `BMAD_VERSION=6.12.1` exits 2 in check-support; validated `max: 6.12.0` | aae-orc-y49j2 |
| Local build default is four modules | `build-bmad.sh:53` vs register `default_modules`; CI already reads the register | aae-orc-lw82d |
| Publish 6.12.1 | needs the four pack tickets above | aae-orc-ln72i |

## Ruled out on evidence

| Candidate | Command | Why not a fault |
|---|---|---|
| sideshow#90 (edited bound skill lost on sync) | append to a bound `SKILL.md`, sync; same edit on native, `install --action update` | Native drops the edit too; it preserves only `_bmad/custom` |
| sideshow#121 (party roster) | `resolve_party.py` in a bound repo and in native | Byte-identical output, 20 members, all resolved |
| sideshow#111 (enable a non-active version) | `sideshow enable bmad@6.12.0` | "not installed" no longer reproduces; bmad has no enable path by design |
| sideshow#18, #132 | install from a built dir; layout inspection | version read from `pack.yaml`; the two-file layout does not exist in our packs |
| sideshow#136 on the bindings path | `CLAUDE_CONFIG_DIR` install | skills bind correctly; the residue is F-g |
| `_bmad/custom/config.toml` absent | native file content | native file holds only comments; resolved config unchanged |
| `_config/skill-manifest.csv` dangling paths | `test -e` on native | dangling in native too |
| tea pin lag | auto pin in the 6.12.1 build | resolves tea v1.27.2, same as native |
| flat `commands/` binding | `ls` after sync | none written |
| executable bits | `find -perm -u+x` | 14 and 14 |
| version switch leaves stale paths | `sideshow use` both ways | all 189 rewritten files re-synced |
| census leaves 1,948 entries unresolved | native self-census | native leaves the same 1,948; improvement only |
| `bmad-build` render HALT on `implementation_artifacts` | `render_skill.py` on native and bound | identical HALT on native when bmm and gds are both installed; upstream, not ours |

## Parity that holds

Skill set 102 of 102. All 189 differing skill files are identical after removing the declared rewrite (store path substitution and the fallback block). Tree: native-only 0; store-only `pack.yaml` and `file-manifest.csv`. Executable bits equal.
