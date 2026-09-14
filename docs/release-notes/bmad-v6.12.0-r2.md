# bmad 6.12.0-r2 release notes

Attach as the body of the `bmad-v6.12.0-r2` draft release. This is a packaging
re-issue: the upstream content is the same 6.12.0 composition as the base
release, and only the packaging layer changed. The base `bmad-v6.12.0` release
stays immutable (see `docs/release-url-format.md` and finding-108).

---

The 6.12.0 pack shipped the build machine's own install answers as pack
content, so every consumer was addressed by the build robot and the resolver
served the builder's project name inside real repositories. This re-issue
removes them. A frozen-composition pack is meant to carry upstream bmad and
nothing about the machine that assembled it; until now it carried two things
about that machine.

The pipeline runs the upstream installer non-interactively, which means it must
answer the installer's prompts from the build environment. Two of those answers
were written into config and shipped:

- `user_name = "arcaven-ci"` (the CI sentinel) landed in `config.user.toml` and
  in every module `config.yaml` (`core`, `bmm`, `cis`, `gds`, `tea`, `bmb`,
  `wds`). 197 skill files read `user_name`, so this was live content, not an
  inert record. It has shipped in every published bmad pack since 6.10.0
  (aae-orc-988gh).
- `project_name = "install"` (the basename of the pipeline's working directory)
  landed in `config.toml` and `core/config.yaml`. The pack's own
  `resolve_config.py` serves it, so nine skills saw a project named `install`
  regardless of where they ran. It has shipped since 6.11.0, where the field is
  new upstream (aae-orc-m79qn).

## What changed

Both keys are removed from the staged config after the installer runs and
before packaging. No user identity and no project name ship. The removal is
line-based, so every comment, blank line, and other key in those files stays
byte-for-byte as the installer wrote it; the divergence from a native install
is only the absent identity lines.

An absent key is safe here, which was verified rather than assumed:
`resolve_config.py` omits a missing dotted key from its merged output and exits
0, so a skill reading `core.user_name` or `core.project_name` gets a missing
key (its own fallback), never the wrong value. Where you want a real identity,
set it in your repo's `_bmad-custom/config.user.toml` (which the sideshow
customization bridge presents to bmad as `_bmad/custom/config.user.toml`); that
layer is highest priority in the four-file chain, so it supersedes the shipped
config.

`install.meta` records the neutralization in a new `post_install` block
(`schema_version` 0.1.3, additive): which keys were removed and why, so the
provenance stays complete.

## Scope

This re-issue corrects 6.12.0. The fix is in the pipeline
(`scripts/neutralize-ci-identity.py`, wired into `build-bmad.sh`), so it applies
to any version rebuilt through it; older published packs carry the same leak
and can be re-issued the same way if wanted. The fail-closed check aborts the
build if the sentinel survives anywhere in the tree, so a future build cannot
silently reintroduce it.

## Verify

Signature and attestation verification is unchanged from the base release:

```sh
cosign verify-blob \
  --bundle bmad-6.12.0-r2-arcaven.tar.gz.bundle \
  --certificate-identity-regexp 'github.com/ArcavenAE/sideshow-packs' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  bmad-6.12.0-r2-arcaven.tar.gz
```

To confirm the identity is gone, extract and grep:

```sh
tar -xzOf bmad-6.12.0-r2-arcaven.tar.gz | grep -c 'arcaven-ci'   # expect 0
```

Upstream content, composition, and packaging-support status are the base
6.12.0 notes (`docs/release-notes/bmad-v6.12.0.md`); nothing there changed.
