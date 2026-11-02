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

## Method as run

**Oracle.** A native install into an empty git repo, with a scratch HOME:

```sh
mise exec node@24.18.0 -- npx -y bmad-method@6.12.4 install --directory "$N" \
  --modules bmm,cis,gds,tea,bmb,wds --tools claude-code --action install \
  --user-name scratch --yes
```

The native installer resolved the external modules to cis v0.3.2, gds v0.7.2, tea v1.27.2, bmb v2.2.2 and wds v0.4.3, the same versions as the pack's explicit pins. Both installers read the same commit for every external module.

**Pack side.** The test build of run 41455632526 (`sign=false`, `publish=false`, `allow_unsupported=true`, explicit pins `cis=v0.3.2,gds=v0.7.2,tea=v1.27.2,bmb=v2.2.2,wds=v0.4.3`), tarball sha256 `4c97819850279f38971170ba19a538ca157db1d687e471922d445bfc570c2958`, upstream git head `bab9082c3e884e0d72c759bcd1a6d90bcc01be84`. It is a test artifact, not a release. Installed with sideshow `0.1.0-alpha.20260914.134314.e32032f` in a second scratch HOME: `sideshow install bmad --from <dir>`, `sideshow commands sync`, then `sideshow project init bmad` in a fresh git repo.

**Run conditions.** Scratch HOME and project directories only; no real config directory, sideshow home or marvel socket touched; no publish, tag or install into a live home. Swap free was 1388 MB before and after.

Comparisons 1 to 7 follow the 6.12.1 method. Comparison 8 (harness observations) was not repeated: none of the 6.12.1 harness findings concerns bytes the pack ships, and the pack did not change in that layer.

## Comparison 2 in detail

189 of 1943 skill files differ. The declared rewrite, applied to the pack side, removes every difference:

- 86 files differ only by the store path written in place of `{project-root}/_bmad/`.
- 103 files also carry the appended fallback-resolution block (the `sideshow:fallback-resolution` markers). Those are the `SKILL.md` files.
- Reversing the two (store path back to `{project-root}/_bmad/`, the block stripped) gives byte equality on all 189. Residual: 0.

The count of differing files is the same, 189, as the 6.12.1 record.

## Differences, each attributed

**D-1. `user_name` and `project_name` absent from the pack (known).** The native installer writes both into `config.toml`, `config.user.toml`, `core/config.yaml` and `bmm/config.yaml`. The pack ships neither, and `resolve_config.py` returns 156 keys against 158. This is fault F-c of the 6.12.1 record (aae-orc-jy1j, a sideshow change after the alpha). No pack bytes change. After these two keys and the timestamps are excluded, all 9 module and root config files match.

**D-2. Timestamps and manifest channel labels.** `_config/manifest.yaml` differs in install and update times, and in the `channel` of three external modules: native records `stable`, the pack records `pinned`. The version and the commit sha of every module are equal. The difference is that the pack names the version through an explicit pin and native reaches the same tag through the stable channel. `_config/files-manifest.csv` differs only in the hashes of the 10 files that D-1 and D-2 change.

**D-3. `_bmad/custom/config.toml` and `config.user.toml` not seeded in a bound repo.** Native ships two commented template files in `_bmad/custom/`. The store carries them, but `project init` creates `_bmad/custom/` in the bound repo as an empty writable directory. One reference to `_bmad/custom/config.toml` therefore resolves natively and not from the bound repo. The files are optional override points whose templates are all comments, and `resolve_config.py` returned the same merged result from the bound repo, so no skill output differs. It is a divergence in what a user finds in the directory, not in behavior. It is a sideshow `project init` matter, not a pack one.

**D-4. `doctor` warns `cwd-known` on a repo bound by `project init`.** Ticket aae-orc-edg8t, known from 6.12.1, a sideshow change. The same `doctor` run reports the census verified (74 entries) and `coexist-check` clean.

## What changed since 6.12.1

The 6.12.1 record found `doctor` failing on a clean install (F-a, the census) and `_bmad/wds/config.yaml` unresolved from a bound repo (F-d). Both pass in this run: the census verifies and `_bmad/wds` resolves in the bound repo.

## Not covered

- Harness observations (comparison 8) and the permission rule form (F-j): `sideshow install` asked to add a Read rule and was answered non-interactively, so no settings were written.
- 6.12.2 and 6.12.3 were diffed, not built or compared.
- The test artifact was built with `allow_unsupported=true`; the register edit that carries this record is what the bracket check reads.
- One run, one native install. Both sides were built on the same day from the same pins.

## Decision this supports

With this record, the condition for publishing 6.12.4 that the builder role sets (a recorded native parity check for the version) is met on the content. Publishing is a separate step and waits for review of this record.
