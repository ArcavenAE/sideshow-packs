#!/usr/bin/env bash
# pin-lag.sh: report how far a built pack's external-module pins trail
# upstream today.
#
# Usage: pin-lag.sh <install.meta.yaml>
#
# build-bmad.sh pins each external module (cis, gds, tea, bmb, wds) to
# the highest pure-semver tag published on or before the upstream npm
# publish date. That makes the composition reproducible, and it also
# means any module release after that date is absent from the pack. A
# native install resolves the stable channel at install time, so the gap
# between the two widens after publication with nothing reporting it.
# This script is the report (aae-orc-soh8q).
#
# Diagnostic, not a gate: it exits 0 whatever the lag, and nonzero only
# on usage or parse errors. Newer tags are not a defect; they are what a
# consumer needs to see to decide whether the as-of composition suits.
#
# Tags come from `git ls-remote --tags <repoUrl>`. Test seam:
# PIN_LAG_TAGS_DIR=<dir> reads <dir>/<module>.txt (one tag per line)
# instead of the network.

set -euo pipefail

META="${1:?usage: pin-lag.sh <install.meta.yaml>}"
TAGS_DIR="${PIN_LAG_TAGS_DIR:-}"

command -v yq >/dev/null || { echo "error: yq required" >&2; exit 1; }
[[ -f "${META}" ]] || { echo "error: no such file: ${META}" >&2; exit 1; }

pack="$(yq -r '.pack.name // ""' "${META}")"
version="$(yq -r '.pack.version // ""' "${META}")"
policy="$(yq -r '.composition.pin_policy // "unrecorded"' "${META}")"
as_of="$(yq -r '.composition.as_of_date // ""' "${META}")"

if [[ -z "${pack}" || -z "${version}" ]]; then
    echo "error: ${META} has no pack.name/pack.version" >&2
    exit 1
fi

echo "[pin-lag] ${pack} ${version}: pin policy ${policy}${as_of:+, as of ${as_of}}"

list_tags() { # module repo_url
    if [[ -n "${TAGS_DIR}" ]]; then
        cat "${TAGS_DIR}/$1.txt" 2>/dev/null || true
    else
        git ls-remote --tags --refs "$2" 2>/dev/null | awk '{sub("refs/tags/","",$2); print $2}'
    fi
}

# strictly_newer A B: A sorts after B under sort -V
strictly_newer() { [[ "$1" != "$2" && "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; }

n="$(yq '.composition.modules_from_manifest | length' "${META}")"
externals=0
lagging=0
unknown=0
for ((i = 0; i < n; i++)); do
    src="$(yq -r ".composition.modules_from_manifest[$i].source" "${META}")"
    [[ "${src}" == "external" ]] || continue
    externals=$((externals + 1))
    name="$(yq -r ".composition.modules_from_manifest[$i].name" "${META}")"
    pinned="$(yq -r ".composition.modules_from_manifest[$i].version" "${META}")"
    repo="$(yq -r ".composition.modules_from_manifest[$i].repoUrl // \"\"" "${META}")"

    tags="$(list_tags "${name}" "${repo}" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' || true)"
    if [[ -z "${tags}" ]]; then
        unknown=$((unknown + 1))
        echo "  ${name} ${pinned}: could not list upstream tags (${repo:-no repoUrl}); lag unknown"
        continue
    fi

    newer=()
    while IFS= read -r t; do
        strictly_newer "${t}" "${pinned}" && newer+=("${t}")
    done < <(sort -V <<< "${tags}")

    if ((${#newer[@]} == 0)); then
        echo "  ${name} ${pinned}: current"
    else
        lagging=$((lagging + 1))
        echo "  ${name} ${pinned}: ${#newer[@]} newer upstream, newest ${newer[${#newer[@]}-1]} (${newer[*]})"
    fi
done

# An unknown lag is never reported as current: the all-clear line needs
# every external module checked.
if ((externals == 0)); then
    echo "[pin-lag] no external modules recorded; nothing to compare"
elif ((lagging == 0 && unknown == 0)); then
    echo "[pin-lag] every external module is at its newest upstream tag"
else
    if ((lagging > 0)); then
        echo "[pin-lag] ${lagging} of ${externals} external modules trail upstream. The pack carries none"
        echo "[pin-lag] of those newer releases, including any fixes they contain; a native install would."
    fi
    if ((unknown > 0)); then
        echo "[pin-lag] lag unknown for ${unknown} of ${externals} external modules: upstream tags could not be listed."
    fi
fi
exit 0
