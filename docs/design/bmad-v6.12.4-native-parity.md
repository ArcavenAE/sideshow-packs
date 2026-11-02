# bmad v6.12.4: installed pack parity with a native install

Status: measurement record, for review. Method: [`bmad-v6.12.1-native-parity.md`](bmad-v6.12.1-native-parity.md).

## Why

The 6.12.4 pack is held back until a native-install comparison for that version is recorded, because without it there is no proof the pack installs the same as bmad's own installer. This record is that comparison. It finds parity on the content: the pack and a native install of the same release carry the same 102 skills, and every byte that differs is the declared rewrite and nothing else.

## Result

Parity holds, with four differences, each attributed below. No fault from this run needs a pack change before publish.

| Comparison | Native 6.12.4 | Pack 6.12.4 | Verdict |
|---|---|---|---|
| 1. Skill set | 102 | 102 | equal names |
| 2. Skill bytes | 1943 files | 1943 files | 189 differ; 0 residual after the declared rewrite |
| 3. `_bmad/` tree | 79 files | the same 79, plus the pack's own skills, `pack.yaml` and two manifests | same paths; 11 files differ in content, attributed below |
| 4. Reference closure | 4 distinct `{project-root}/_bmad/` references still present in bound skills resolve | 3 of 4 resolve from a bound repo | 1 residual (D-3) |
| 5. Resolved config | 158 keys | 156 keys | 156 of 158 match; the 2 are D-1 |
| 6. Executable bits | n/a | n/a | 0 mismatches across 1943 skill files |
| 7. Tool verdicts | n/a | `doctor` 12 ok, 1 warn, 0 fail; `status` 102 of 102 synced; `coexist-check` clean | the one warn is D-4 |
| 8. Harness observations | n/a | n/a | not run |

## Method as run

**Oracle.** A native install into an empty git repo, with a scratch HOME:

```sh
mise exec node@24.18.0 -- npx -y bmad-method@6.12.4 install --directory "$N" \
  --modules bmm,cis,gds,tea,bmb,wds --tools claude-code --action install \
  --user-name scratch --yes
```

This was a fresh install made for this record, into an empty scratch directory created for it, with node v24.18.0 fetched by mise in the same run. The installer's own manifest (`_bmad/_config/manifest.yaml`) records `installation.version: 6.12.4` and `installDate: 2026-11-02T20:56:08.905Z`, and the pack side was installed minutes later in a different scratch HOME. Nothing on the native side was reused from the 6.12.1 record or inferred.

Evidence the native tree is this install:

| Module | Native version | Native sha | Pack sha | Equal |
|---|---|---|---|---|
| core, bmm | 6.12.4 (built in) | n/a | n/a | n/a |
| cis | v0.3.2 | `97298b22fee1c7e482710d3a8414adb5cfccccd9` | `97298b22fee1c7e482710d3a8414adb5cfccccd9` | yes |
| gds | v0.7.2 | `2486f5f5f3b8870baa6cee4615a870c0330f441c` | `2486f5f5f3b8870baa6cee4615a870c0330f441c` | yes |
| tea | v1.27.2 | `d99ad29c62697c152e3393351406686d5bcd323c` | `d99ad29c62697c152e3393351406686d5bcd323c` | yes |
| bmb | v2.2.2 | `4a1422274a2acb0fb0ec0511753da6263948f072` | `4a1422274a2acb0fb0ec0511753da6263948f072` | yes |
| wds | v0.4.3 | `cc16f09fcfab26d35635af1491f36a38a8431c8d` | `cc16f09fcfab26d35635af1491f36a38a8431c8d` | yes |

Tree digests of the native `_bmad/`, run from the scratch root `$R` (the directory holding `native/`):

```sh
cd "$R/native/_bmad" && find . -type f | LC_ALL=C sort | shasum -a 256
shasum -a 256 "$R/native/_bmad/_config/files-manifest.csv"
```

```text
1af5de7a9a445b50a98b7c9159004d4f12e31f80b91ab468288c32231b7a5a39  -
674c9feb3446423be27736b4c6bd603526816377c7d7edf03db10e08e12026fb  native/_bmad/_config/files-manifest.csv
```

The first digest is of the sorted listing (79 paths); the second is of `files-manifest.csv`. The headline counts of this run (102 skills, 189 differing files, 156 of 158 keys) equal the 6.12.1 record's. I did not diff the two releases' skill sets to explain that; the manifest, shas and digests above are what tie these counts to this install, and a reader can compare them against an install of their own.

**Pack side.** The test build of run 41455632526 (`sign=false`, `publish=false`, `allow_unsupported=true`, explicit pins `cis=v0.3.2,gds=v0.7.2,tea=v1.27.2,bmb=v2.2.2,wds=v0.4.3`), tarball sha256 `4c97819850279f38971170ba19a538ca157db1d687e471922d445bfc570c2958`, upstream git head `bab9082c3e884e0d72c759bcd1a6d90bcc01be84`. It is a test artifact, not a release. Installed with sideshow `0.1.0-alpha.20260914.134314.e32032f` in a second scratch HOME: `sideshow install bmad --from <dir>`, `sideshow commands sync`, then `sideshow project init bmad` in a fresh git repo.

**Run conditions.** Scratch HOME and project directories only; no real config directory, sideshow home or marvel socket touched; no publish, tag or install into a live home. Swap free was 1388 MB before and after.

**Installed side C (`CLAUDE_CONFIG_DIR` set).** Run in a third scratch HOME, `$R/chome`, with `CLAUDE_CONFIG_DIR` pointing at an empty directory, `$R/ccfg`. Every path below is relative to the scratch root `$R`; no real home directory is read or written.

```sh
mkdir -p chome cproj ccfg && (cd cproj && git init -q .)
export HOME="$R/chome" CLAUDE_CONFIG_DIR="$R/ccfg"; unset MARVEL_SOCKET SIDESHOW_HOME
sideshow install bmad --from packdir/bmad-6.12.4 --yes
sideshow commands sync
(cd cproj && sideshow project init bmad)
```

```text
Installed 2025 files to chome/.local/share/sideshow/packs/bmad/6.12.4
  Added Read(chome/.local/share/sideshow/packs/) to chome/.claude/settings.json
Synced 102 artifacts across all bindings
skills under ccfg/skills: 0 (the directory does not exist)
skills under chome/.claude/skills: 102
```

The Read rule written is `Read(<scratch>/chome/.local/share/sideshow/packs/)` in `chome/.claude/settings.json`; `ccfg` has no `settings.json`. So with this sideshow build, `CLAUDE_CONFIG_DIR` is ignored for both the skills and the permission. That is the behavior the 6.12.1 record lists as F-g (aae-orc-89cxz), a sideshow matter and not a pack difference.

Side C against side B, same bytes after the home path is normalized (`B` is `packhome/.claude/skills`, `C` is `chome/.claude/skills`):

```sh
python3 -I - <<'EOF'
import os
def files(r):
    o = {}
    for d, _, fs in os.walk(r, followlinks=True):
        for f in fs:
            o[os.path.relpath(os.path.join(d, f), r)] = os.path.join(d, f)
    return o
b, c = files("packhome/.claude/skills"), files("chome/.claude/skills")
R = os.getcwd().encode()
eq = sum(1 for k in b if k in c
         and open(b[k], "rb").read().replace(R + b"/packhome", b"@H")
          == open(c[k], "rb").read().replace(R + b"/chome", b"@H"))
print("B", len(b), "C", len(c), "equal after home normalization", eq)
EOF
```

```text
B 1943 C 1943 equal after home normalization 1943
```

Comparisons 1 to 7 follow the 6.12.1 method: comparisons 1 to 7 passed; comparison 8 not run. Comparison 8 (harness observations) was not repeated, and this record makes no claim about it. The 6.12.1 harness findings (F-j, F-k) concern sideshow's permission rule and skill shadowing, not bytes the pack ships.

## Comparison 2 in detail

189 of 1943 skill files differ. The declared rewrite, applied to the pack side, removes every difference:

- 86 files differ only by the store path written in place of `{project-root}/_bmad/`.
- 103 files also carry the appended fallback-resolution block (the `sideshow:fallback-resolution` markers). Those are the `SKILL.md` files.
- Reversing the two (store path back to `{project-root}/_bmad/`, the block stripped) gives byte equality on all 189. Residual: 0.

The command, and its output from this run (exit status 0):

```sh
python3 -I scripts/compare-native-skills.py \
  "$N/.claude/skills" "$HOME_B/.claude/skills" "$HOME_B/.local/share/sideshow/packs/bmad/6.12.4"
```

```text
skill names equal: True 102
files native 1943 bound 1943 only native 0 only bound 0
differing files 189 {'SKILL.md': 102, 'md': 79, 'other.yaml': 8}
with fallback block 103 store-path only 86
files carrying {project-root}/_bmad/ that are byte-equal in both trees: 41
residual after declared rewrite: 0
```

**Controls for the script.** The script exits 0 only when the skill names are equal, no file exists on one side only, and the residual is 0; an empty tree exits 2. Each was checked on a copy of the bound tree (`cp -RL`), with the script's own exit status read bare:

| Control | Change to the bound copy | Exit | Reported |
|---|---|---|---|
| positive | none | 0 | `only native 0 only bound 0`, residual 0 |
| 1 | one file removed | 1 | `files bound 1942 only native 1` |
| 2 | one file added | 1 | `files bound 1944 only bound 1` |
| 3 | an extra skill directory | 1 | `skill names equal: False` |
| 4 | one line appended to one `SKILL.md` | 1 | `residual after declared rewrite: 1` |
| 5 | empty bound tree | 2 | `an empty tree is a failure` |

**Reconciling 86 with a count of about 94.** The two numbers count different things. Of the 95 non-`SKILL.md` markdown files in the native tree that contain `{project-root}/_bmad/`, 79 differ in the pack (the rewrite changed them) and 16 are byte-equal to native. The 86 above is the count of differing files that carry no fallback block: the 79 markdown files plus 8 `workflow.yaml` files, less one markdown file that does carry the block (103 files carry it: the 102 `SKILL.md` files and that one). A raw count of files containing the string therefore reads higher than 86, since it includes the 16 the rewrite did not touch.

Those 16 are byte-equal to native, so they add nothing to the residual. The string in them sits in prose or in quoted config values (for example `advancedElicitationTask: '{project-root}/_bmad/core/workflows/...'` in the `bmad-teach-me-testing` steps) rather than in the path shapes the rewrite targets. Whether the rewrite should reach them is a rewrite-scope question (ticket aae-orc-k5vro covers part of it) and is outside parity with native, which is the criterion here.

## Differences, each attributed

**D-1. `user_name` and `project_name` absent from the pack (known).** The native installer writes both into `config.toml`, `config.user.toml`, `core/config.yaml` and `bmm/config.yaml`. The pack ships neither, and `resolve_config.py` returns 156 keys against 158. This is fault F-c of the 6.12.1 record (aae-orc-jy1j, a sideshow change after the alpha). No pack bytes change. After these two keys and the timestamps are excluded, all 9 module and root config files match.

**D-2. Timestamps and manifest channel labels.** `_config/manifest.yaml` differs in install and update times, and in the `channel` of three external modules: native records `stable`, the pack records `pinned`. The version and the commit sha of every module are equal. The difference is that the pack names the version through an explicit pin and native reaches the same tag through the stable channel. `_config/files-manifest.csv` differs only in the hashes of the 10 files that D-1 and D-2 change.

**D-3. `_bmad/custom/config.toml` and `config.user.toml` not seeded in a bound repo.** Native ships two commented template files in `_bmad/custom/`. The store carries them, but `project init` creates `_bmad/custom/` in the bound repo as an empty writable directory. One reference to `_bmad/custom/config.toml` therefore resolves natively and not from the bound repo. The files are optional override points whose templates are all comments, and `resolve_config.py` returned the same merged result from the bound repo, so no skill output differs. It is a divergence in what a user finds in the directory, not in behavior. It is a sideshow `project init` matter, not a pack one.

**D-4. `doctor` warns `cwd-known` on a repo bound by `project init`.** Ticket aae-orc-edg8t, known from 6.12.1, a sideshow change. The same `doctor` run reports the census verified (74 entries) and `coexist-check` clean.

## What changed since 6.12.1

The 6.12.1 record found `doctor` failing on a clean install (F-a, the census) and `_bmad/wds/config.yaml` unresolved from a bound repo (F-d). Both pass in this run: the census verifies and `_bmad/wds` resolves in the bound repo.

## Not covered

- Comparison 8 (harness observations) was not run, including the permission rule form (F-j): in side B `sideshow install` asked to add a Read rule and was answered non-interactively, so no settings were written there.
- 6.12.2 and 6.12.3 were diffed, not built or compared.
- The test artifact was built with `allow_unsupported=true`; the register edit that carries this record is what the bracket check reads.
- One run, one native install. Both sides were built on the same day from the same pins.

## Decision this supports

Comparisons 1 to 7 passed; comparison 8 not run. The release criterion is comparisons 1 to 7, and with this record the condition the builder role sets for publishing 6.12.4 (a recorded native parity check for the version) has its record. Publishing is a separate step and waits for review of this record.
