#!/usr/bin/env bash
# Scenario tests for exec-manifest.txt travelling inside the pack
# (aae-orc-6la0l). Self-contained: a synthetic stage, no network. Run from
# anywhere:
#
#   bash scripts/test-exec-manifest.sh
#
# CI runs this via .github/workflows/intake-tests.yml. Needs yq, as
# verify-artifact.sh does.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE="${SD}/write-exec-manifest.sh"
VERIFY="${SD}/verify-artifact.sh"
DIR="$(mktemp -d -t exec-manifest-test-XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

pass=0
fail=0
check_eq() { # name expected actual
    if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else
        fail=$((fail + 1)); echo "FAIL: $1: expected '$2', got '$3'"; fi
}
check() { # name needle haystack
    if grep -qF -- "$2" <<<"$3"; then pass=$((pass + 1)); else
        fail=$((fail + 1)); echo "FAIL: $1: '$2' not in output"; echo "$3" | sed 's/^/    /'; fi
}

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
size() { if [[ "$(uname)" == "Darwin" ]]; then stat -f %z "$1"; else stat -c %s "$1"; fi; }

# make_stage <dir>: a pack stage with two executables and two plain files.
make_stage() {
    local s="$1"
    mkdir -p "$s/bin" "$s/core"
    printf 'name: fixture\nversion: 1.0.0\n' > "$s/pack.yaml"
    printf '#!/bin/sh\n' > "$s/bin/tool.sh";  chmod 755 "$s/bin/tool.sh"
    printf '#!/usr/bin/env python3\n' > "$s/core/run.py"; chmod 755 "$s/core/run.py"
    printf 'doc\n' > "$s/core/doc.md"
    printf '#!/bin/sh\n' > "$s/core/owner-only.sh"; chmod 700 "$s/core/owner-only.sh"
}

# ---- the helper ------------------------------------------------------------
S="$DIR/stage"; make_stage "$S"
out="$(bash "$WRITE" "$S" "$DIR/exec.txt" 2>&1)"; rc=$?
check_eq "helper exits 0" "0" "$rc"
check_eq "helper lists the executables, sorted" $'bin/tool.sh\ncore/owner-only.sh\ncore/run.py' "$(cat "$DIR/exec.txt" 2>/dev/null)"
check_eq "helper copies the manifest into the stage" "$(cat "$DIR/exec.txt" 2>/dev/null)" "$(cat "$S/exec-manifest.txt" 2>/dev/null)"
if [[ -x "$S/exec-manifest.txt" ]]; then check_eq "the in-stage manifest is not executable" "no" "yes"; else pass=$((pass + 1)); fi

# Idempotent: a second run, with the manifest already in the stage, lists the same.
bash "$WRITE" "$S" "$DIR/exec2.txt" >/dev/null 2>&1
check_eq "a second run lists the same executables" "$(cat "$DIR/exec.txt")" "$(cat "$DIR/exec2.txt" 2>/dev/null)"

# A pack with no executables records that: an empty manifest, still in the stage.
E="$DIR/empty"; mkdir -p "$E"; printf 'x\n' > "$E/a.md"
bash "$WRITE" "$E" "$DIR/empty.txt" >/dev/null 2>&1
check_eq "an empty list is written, not skipped" "0" "$(wc -c < "$DIR/empty.txt" 2>/dev/null | tr -d ' ')"
check_eq "the empty manifest is in the stage" "yes" "$([[ -f "$E/exec-manifest.txt" ]] && echo yes || echo no)"

# ---- verify-artifact.sh ----------------------------------------------------
# build_artifact <dir> [variant]: a release directory the verifier reads.
#   variant "no-exec"     the tarball carries no exec-manifest.txt
#   variant "unlisted"    file-manifest.csv has no row for exec-manifest.txt
#   variant "not-exec"    the manifest names a file that is not executable
#   variant "mismatch"    the in-tarball manifest differs from the sibling
build_artifact() {
    local a="$1" variant="${2:-good}" st="$1/work/fixture-1.0.0"
    mkdir -p "$a"
    make_stage "$st"
    if [[ "$variant" != "no-exec" ]]; then
        bash "$WRITE" "$st" "$a/exec-manifest.txt" >/dev/null 2>&1
    else
        : > "$a/exec-manifest.txt"
    fi
    if [[ "$variant" == "not-exec" ]]; then
        printf 'bin/tool.sh\ncore/doc.md\ncore/owner-only.sh\ncore/run.py\n' > "$st/exec-manifest.txt"
        cp "$st/exec-manifest.txt" "$a/exec-manifest.txt"
    fi
    (
        cd "$st"
        find . -type f -print0 | sort -z | while IFS= read -r -d '' f; do
            [[ "$variant" == "unlisted" && "$f" == "./exec-manifest.txt" ]] && continue
            printf '%s,%s,%s\n' "$(sha "$f")" "$(size "$f")" "${f#./}"
        done
    ) > "$a/file-manifest.csv"
    cp "$a/file-manifest.csv" "$st/file-manifest.csv"
    if [[ "$variant" == "mismatch" ]]; then printf 'bin/other.sh\n' > "$a/exec-manifest.txt"; fi
    tar -C "$a/work" -czf "$a/fixture-1.0.0-arcaven.tar.gz" fixture-1.0.0
    rm -rf "$a/work"
    cat > "$a/install.meta.yaml" <<YAML
pack:
  name: fixture
  version: 1.0.0
composition:
  modules_from_manifest: []
YAML
}

run_verify() { bash "$VERIFY" "$1" 2>&1; }

build_artifact "$DIR/good"
out="$(run_verify "$DIR/good")"; rc=$?
check_eq "a well-formed artifact passes (exit)" "0" "$rc"
check "the in-tarball manifest is confirmed" "in-tarball exec-manifest.txt matches the release asset" "$out"
check "the manifest is listed in file-manifest.csv" "exec-manifest.txt has a row in file-manifest.csv" "$out"
check "every listed path is executable" "exec-manifest.txt lists exactly the executable files" "$out"

build_artifact "$DIR/noexec" no-exec
out="$(run_verify "$DIR/noexec")"; rc=$?
check_eq "a tarball with no exec-manifest.txt fails (exit)" "1" "$rc"
check "the failure names the missing manifest" "tarball carries no exec-manifest.txt" "$out"

build_artifact "$DIR/unlisted" unlisted
out="$(run_verify "$DIR/unlisted")"; rc=$?
check_eq "an exec-manifest.txt with no census row fails (exit)" "1" "$rc"
check "the failure names the missing row" "file-manifest.csv has no row for exec-manifest.txt" "$out"

build_artifact "$DIR/notexec" not-exec
out="$(run_verify "$DIR/notexec")"; rc=$?
check_eq "a listed file that is not executable fails (exit)" "1" "$rc"
check "the failure names the drift" "exec-manifest.txt does not match the executable files" "$out"

build_artifact "$DIR/mismatch" mismatch
out="$(run_verify "$DIR/mismatch")"; rc=$?
check_eq "an in-tarball manifest unlike the sibling fails (exit)" "1" "$rc"
check "the failure names the sibling mismatch" "in-tarball exec-manifest.txt differs from the release asset" "$out"

# ---- builder order ---------------------------------------------------------
# The manifest must be written before the hash pass so it is listed in
# file-manifest.csv, and nothing may change the stage between the two. The
# builders need network and upstream installers, so pin the order statically.
order() { # script helper-marker hash-marker
    local h c
    h="$(grep -n -E -- "$2" "$1" | head -1 | cut -d: -f1)"
    c="$(grep -n -F -- "$3" "$1" | head -1 | cut -d: -f1)"
    if [[ -n "$h" && -n "$c" && "$h" -lt "$c" ]]; then echo before; else echo "helper=${h:-none} hash=${c:-none}"; fi
}
check_eq "build-bmad.sh writes exec-manifest.txt before the hash pass" "before" \
    "$(order "${SD}/build-bmad.sh" '^bash "[$][{]SCRIPT_DIR[}]/write-exec-manifest[.]sh" "[$][{]PACK_STAGE[}]"' 'computing file manifest')"
check_eq "build-vsdd-factory.sh writes exec-manifest.txt before the hash pass" "before" \
    "$(order "${SD}/build-vsdd-factory.sh" '^bash "[$][{]SCRIPT_DIR[}]/write-exec-manifest[.]sh" "[$][{]PACK_STAGE[}]"' 'computing file manifest')"
for b in build-bmad.sh build-vsdd-factory.sh; do
    check_eq "${b} no longer builds the exec list inline" "0" "$(grep -c 'find . -type f -perm -0100' "${SD}/${b}")"
done

echo "exec-manifest tests: ${pass} passed, ${fail} failed"
[[ "${fail}" == "0" ]]
