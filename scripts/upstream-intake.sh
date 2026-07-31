#!/usr/bin/env bash
# upstream-intake.sh: detect new upstream releases, soak them, verify
# tag-SHA stability across the soak window, then dispatch
# build-pack.yml per eligible version. bd: aae-orc-4t1k.
#
# Deliberately does NOT follow upstream closely. A release younger
# than SOAK_HOURS is only observed (its tag SHA is recorded), never
# packaged. A later run re-resolves the SHA; if it moved during the
# window, the version is refused and a quarantine issue is opened.
# The version stays quarantined while that issue is open; closing the
# issue is the human acknowledgment that lets the (restarted) soak
# proceed. This is the retag-or-yank guard: a delay only helps if
# something checks whether anything changed during it.
#
# Versions outside the validated bracket in
# registry/<pack>-pack-support.yaml are never dispatched (the build
# would fail check-support.sh anyway). They get a revalidation issue
# pointing at the llm_runbook; once the bracket is extended, the next
# run dispatches them.
#
# Dispatches carry expected_sha, which build-bmad.sh verifies against
# the npm package's gitHead before running the installer, binding the
# soaked git tag to the artifact actually consumed.
#
# State: a machine-maintained ledger issue on this repo (title in
# LEDGER_TITLE below) whose body carries a fenced JSON block:
# {"<version>": {"sha": "...", "first_seen": "<iso8601>"}}. Entries
# are pruned once their version is packaged. Issues were chosen over
# repo Actions variables because GITHUB_TOKEN's `issues: write` is a
# documented grant for issue create/edit, while the variables
# endpoints want a separate Variables permission that GITHUB_TOKEN
# cannot be granted.
#
# Environment:
#   DRY_RUN        0|1 (default 0). 1 = report every action, change nothing.
#   SOAK_HOURS     hours a release must age before packaging (default 72)
#   MIN_OBS_HOURS  minimum hours between first observation and packaging,
#                  so the SHA check always has two data points even when
#                  a version is first seen already older than the soak
#                  window (default 20, i.e. one daily-cron cycle)
#   MAX_DISPATCH   per-run dispatch cap; the dropped count is logged so a
#                  truncated backfill does not read as full coverage
#                  (default 3)
#   REPO           this repo (default ArcavenAE/sideshow-packs)
#   UPSTREAM       upstream repo (default bmad-code-org/BMAD-METHOD)
#   PACK           pack name (default bmad)
#
# Test seams (paths to JSON fixtures; unset = live gh calls):
#   UPSTREAM_RELEASES_FILE  [{tag_name, published_at, draft, prerelease}]
#   LOCAL_RELEASES_FILE     [{tag_name, draft}]
#   SHA_FILE                {"<tag>": "<commit sha>"}
#   ISSUES_FILE             [{number, title, body}] open issues (also
#                           carries the ledger issue when present)
#   OBS_FILE                observations JSON, read+write (takes
#                           precedence over the ledger issue)
#   REGISTRY_FILE           pack-support register override
#   CURRENT_LATEST          tag currently carrying the Latest marker
#   NOW_EPOCH               fixed clock

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
SOAK_HOURS="${SOAK_HOURS:-72}"
MIN_OBS_HOURS="${MIN_OBS_HOURS:-20}"
MAX_DISPATCH="${MAX_DISPATCH:-3}"
REPO="${REPO:-ArcavenAE/sideshow-packs}"
UPSTREAM="${UPSTREAM:-bmad-code-org/BMAD-METHOD}"
PACK="${PACK:-bmad}"
LEDGER_TITLE="upstream-intake: observation ledger (machine state)"

# Numeric settings reach bash arithmetic contexts, which evaluate
# array subscripts and therefore command substitutions. Reject
# anything that is not a plain non-negative integer before first use.
require_uint() {
    [[ "$2" =~ ^[0-9]+$ ]] || { echo "error: $1 must be a non-negative integer (got: $2)"; exit 1; }
}
require_uint SOAK_HOURS "${SOAK_HOURS}"
require_uint MIN_OBS_HOURS "${MIN_OBS_HOURS}"
require_uint MAX_DISPATCH "${MAX_DISPATCH}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_FILE="${REGISTRY_FILE:-${ROOT}/registry/${PACK}-pack-support.yaml}"

command -v gh >/dev/null || { echo "error: gh required"; exit 1; }
command -v jq >/dev/null || { echo "error: jq required"; exit 1; }
command -v yq >/dev/null || { echo "error: yq required"; exit 1; }
command -v python3 >/dev/null || { echo "error: python3 required"; exit 1; }

log() { echo "[intake] $*"; }
dryrun_prefix() { [[ "${DRY_RUN}" == "1" ]] && echo "DRY-RUN: would " || echo ""; }

iso_to_epoch() {
    python3 -c "import sys,datetime; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).timestamp()))" "$1"
}

epoch_to_iso() {
    python3 -c "import sys,datetime; print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"
}

NOW="${NOW_EPOCH:-$(date -u +%s)}"

# $1 >= $2 under semver ordering
semver_ge() {
    [[ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}

# --- Data sources ------------------------------------------------------

upstream_releases_json() {
    if [[ -n "${UPSTREAM_RELEASES_FILE:-}" ]]; then
        cat "${UPSTREAM_RELEASES_FILE}"
    else
        gh api --paginate "repos/${UPSTREAM}/releases?per_page=100" | jq -s 'add'
    fi
}

local_releases_json() {
    if [[ -n "${LOCAL_RELEASES_FILE:-}" ]]; then
        cat "${LOCAL_RELEASES_FILE}"
    else
        gh api --paginate "repos/${REPO}/releases?per_page=100" | jq -s 'add'
    fi
}

resolve_sha() { # upstream tag -> commit sha (empty + nonzero on failure)
    local tag="$1" out
    if [[ -n "${SHA_FILE:-}" ]]; then
        jq -r --arg t "$tag" '.[$t] // empty' "${SHA_FILE}"
    else
        # On HTTP errors gh api prints the error body to stdout; discard
        # captured output on failure so it cannot masquerade as a SHA.
        if ! out="$(gh api "repos/${UPSTREAM}/commits/${tag}" --jq .sha 2>/dev/null)"; then
            return 1
        fi
        echo "${out}"
    fi
}

# --- Open issues: quarantine checks + the observation ledger -----------

open_issues_json() {
    if [[ -n "${ISSUES_FILE:-}" ]]; then
        [[ -f "${ISSUES_FILE}" ]] && cat "${ISSUES_FILE}" || echo '[]'
    else
        gh issue list -R "${REPO}" --state open --limit 100 --json number,title,body
    fi
}
ISSUES_JSON="$(open_issues_json)"
jq -e 'type == "array"' <<< "${ISSUES_JSON}" >/dev/null 2>&1 || ISSUES_JSON='[]'

issue_open() { # title -> 0 if an open issue carries it
    jq -e --arg t "$1" 'any(.[]; .title == $t)' <<< "${ISSUES_JSON}" >/dev/null
}

ensure_issue() { # title body
    local title="$1" body="$2"
    if issue_open "${title}"; then
        log "issue already open: ${title}"
        return 0
    fi
    if [[ "${DRY_RUN}" == "1" || -n "${ISSUES_FILE:-}" ]]; then
        log "$(dryrun_prefix)open issue: ${title}"
    else
        gh issue create -R "${REPO}" --title "${title}" --body "${body}" >/dev/null
        log "opened issue: ${title}"
    fi
    # Keep the in-run view consistent so a later step sees it as open.
    ISSUES_JSON="$(jq -c --arg t "$title" '. + [{title: $t}]' <<< "${ISSUES_JSON}")"
}

drift_title() { # version
    echo "upstream-intake: ${PACK} v${1} tag SHA changed during soak"
}

LEDGER_NUMBER="$(jq -r --arg t "${LEDGER_TITLE}" \
    'first(.[] | select(.title == $t)) | .number // empty' <<< "${ISSUES_JSON}")"

load_obs() {
    local body
    if [[ -n "${OBS_FILE:-}" ]]; then
        [[ -f "${OBS_FILE}" ]] && cat "${OBS_FILE}" || echo '{}'
        return 0
    fi
    body="$(jq -r --arg t "${LEDGER_TITLE}" \
        'first(.[] | select(.title == $t)) | .body // empty' <<< "${ISSUES_JSON}")"
    # Extract the fenced JSON block; tolerate CRLF from web edits.
    printf '%s\n' "${body}" | tr -d '\r' | awk '/^```json$/{f=1;next} /^```/{f=0} f'
}

ledger_body() { # obs-json
    printf 'Machine-maintained by `.github/workflows/upstream-intake.yml` (bd `aae-orc-4t1k`). Records the first-observed tag SHA per unpackaged upstream version so a later run can detect retags during the soak window. Do not hand-edit; closing this issue resets all observations.\n\n```json\n%s\n```\n' "$1"
}

save_obs() { # json
    local json="$1"
    if [[ "${DRY_RUN}" == "1" ]]; then
        log "DRY-RUN: would save observations: ${json}"
        return 0
    fi
    if [[ -n "${OBS_FILE:-}" ]]; then
        printf '%s' "${json}" > "${OBS_FILE}"
        return 0
    fi
    if [[ -n "${LEDGER_NUMBER}" ]]; then
        gh issue edit "${LEDGER_NUMBER}" -R "${REPO}" --body "$(ledger_body "${json}")" >/dev/null
    else
        gh issue create -R "${REPO}" --title "${LEDGER_TITLE}" \
            --body "$(ledger_body "${json}")" >/dev/null
        log "created ledger issue"
    fi
}

# --- Composition policy ------------------------------------------------
# Per-rung module composition, matching the 2026-07-12 expanded
# re-issue (commit b4cfe32): bmb enters at 6.4.0, wds at 6.7.0.
# When the pack-support schema grows version_scheme/composition blocks
# (aae-orc-zb12), this moves into the register.
modules_for() {
    local v="$1"
    if semver_ge "$v" "6.7.0"; then echo "bmm,cis,gds,tea,bmb,wds"
    elif semver_ge "$v" "6.4.0"; then echo "bmm,cis,gds,tea,bmb"
    else echo "bmm,cis,gds,tea"; fi
}

# --- Support bracket ---------------------------------------------------

BRACKETS_JSON="$(yq -o json '.validated' "${REGISTRY_FILE}")"
FLOOR="$(jq -r '[.[].min] | sort_by(split(".") | map(tonumber)) | first' <<< "${BRACKETS_JSON}")"

in_bracket() { # version -> 0/1 exit
    local v="$1" min max n i
    n="$(jq 'length' <<< "${BRACKETS_JSON}")"
    for ((i=0; i<n; i++)); do
        min="$(jq -r ".[$i].min" <<< "${BRACKETS_JSON}")"
        max="$(jq -r ".[$i].max" <<< "${BRACKETS_JSON}")"
        if semver_ge "$v" "$min" && semver_ge "$max" "$v"; then
            return 0
        fi
    done
    return 1
}

# --- Gather ------------------------------------------------------------

UPSTREAM_JSON="$(upstream_releases_json | jq '[.[]
    | select(.draft == false and .prerelease == false)
    | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    | {tag_name, published_at}]')"

LOCAL_JSON="$(local_releases_json)"

# Bare-semver lists for the set difference. Any local release (draft
# included) counts as "have": a draft means a build already ran and a
# human publish is pending; re-dispatching would duplicate it.
UP_VERSIONS="$(jq -r '.[].tag_name | ltrimstr("v")' <<< "${UPSTREAM_JSON}")"
HAVE_VERSIONS="$(jq -r --arg p "${PACK}-v" \
    '.[].tag_name | select(startswith($p)) | ltrimstr($p)' <<< "${LOCAL_JSON}")"

# comm needs LC_ALL=C sort; sort -V output is rejected by comm
# (finding-041 gotcha). Re-sort with sort -V only for processing order.
MISSING="$(comm -23 \
    <(printf '%s\n' "${UP_VERSIONS}" | LC_ALL=C sort -u) \
    <(printf '%s\n' "${HAVE_VERSIONS}" | LC_ALL=C sort -u) \
    | while read -r v; do
        [[ -n "$v" ]] && semver_ge "$v" "${FLOOR}" && echo "$v" || true
      done | sort -V)"

if [[ -z "${MISSING}" ]]; then
    log "no unpackaged upstream versions at or above floor ${FLOOR}"
else
    log "unpackaged versions at or above floor ${FLOOR}: $(tr '\n' ' ' <<< "${MISSING}")"
fi

# --- Soak + SHA stability + dispatch -----------------------------------

OBS="$(load_obs)"
jq -e 'type == "object"' <<< "${OBS}" >/dev/null 2>&1 || OBS='{}'
DISPATCHED=0
DROPPED=0
OBS_CHANGED=0

for ver in ${MISSING}; do
    tag="v${ver}"
    published_at="$(jq -r --arg t "$tag" '.[] | select(.tag_name == $t) | .published_at' <<< "${UPSTREAM_JSON}")"
    published_epoch="$(iso_to_epoch "${published_at}")"
    published_age_h=$(( (NOW - published_epoch) / 3600 ))

    if ! sha_now="$(resolve_sha "$tag")" || [[ -z "${sha_now}" ]]; then
        log "WARN: cannot resolve SHA for ${tag} (deleted tag, API error, or permissions); skipping"
        continue
    fi

    obs_sha="$(jq -r --arg v "$ver" '.[$v].sha // empty' <<< "${OBS}")"
    obs_seen="$(jq -r --arg v "$ver" '.[$v].first_seen // empty' <<< "${OBS}")"

    if [[ -z "${obs_sha}" ]]; then
        OBS="$(jq -c --arg v "$ver" --arg s "$sha_now" --arg t "$(epoch_to_iso "${NOW}")" \
            '. + {($v): {sha: $s, first_seen: $t}}' <<< "${OBS}")"
        OBS_CHANGED=1
        log "${ver}: first observation (published ${published_age_h}h ago, sha ${sha_now:0:12}); soaking"
        continue
    fi

    if [[ "${obs_sha}" != "${sha_now}" ]]; then
        log "${ver}: REFUSED, tag SHA changed during soak (${obs_sha:0:12} -> ${sha_now:0:12})"
        ensure_issue \
            "$(drift_title "${ver}")" \
            "The upstream tag \`${tag}\` on ${UPSTREAM} resolved to \`${obs_sha}\` when first observed (${obs_seen}) and now resolves to \`${sha_now}\`. This looks like a retag or force-push. Packaging is refused and the version stays quarantined while this issue is open; the soak restarts against the new SHA. If the retag is legitimate, close this issue; the next scheduled run after the restarted window packages it. bd: aae-orc-4t1k."
        OBS="$(jq -c --arg v "$ver" --arg s "$sha_now" --arg t "$(epoch_to_iso "${NOW}")" \
            '. + {($v): {sha: $s, first_seen: $t}}' <<< "${OBS}")"
        OBS_CHANGED=1
        continue
    fi

    obs_epoch="$(iso_to_epoch "${obs_seen}")"
    obs_age_h=$(( (NOW - obs_epoch) / 3600 ))

    if (( published_age_h < SOAK_HOURS )) || (( obs_age_h < MIN_OBS_HOURS )); then
        log "${ver}: soaking (published ${published_age_h}h/${SOAK_HOURS}h, observed ${obs_age_h}h/${MIN_OBS_HOURS}h, sha stable)"
        continue
    fi

    # A past SHA drift quarantines the version until a human closes the
    # drift issue, even after the soak restarts and completes.
    if issue_open "$(drift_title "${ver}")"; then
        log "${ver}: quarantined, drift issue still open; close it to accept the current SHA"
        continue
    fi

    if ! in_bracket "${ver}"; then
        log "${ver}: soaked + sha stable, but outside the validated support bracket"
        ensure_issue \
            "upstream-intake: ${PACK} ${ver} is outside the validated support bracket" \
            "Upstream ${UPSTREAM} published \`${tag}\` (${published_at}); it has soaked ${published_age_h}h with a stable SHA (\`${sha_now}\`) and is ready to package, but it falls outside every validated bracket in \`registry/${PACK}-pack-support.yaml\`. Follow \`registry/pack-support-revalidation-runbook.md\` to re-verify the pipeline assumptions and extend the bracket; the next scheduled run will then dispatch the build. bd: aae-orc-4t1k."
        continue
    fi

    if (( DISPATCHED >= MAX_DISPATCH )); then
        DROPPED=$((DROPPED + 1))
        continue
    fi

    mods="$(modules_for "${ver}")"
    log "$(dryrun_prefix)dispatch build-pack.yml: pack=${PACK} version=${ver} modules=${mods} pins=auto sign=true publish=true expected_sha=${sha_now}"
    if [[ "${DRY_RUN}" != "1" ]]; then
        gh workflow run build-pack.yml -R "${REPO}" \
            -f pack="${PACK}" \
            -f version="${ver}" \
            -f modules="${mods}" \
            -f pins=auto \
            -f sign=true \
            -f publish=true \
            -f expected_sha="${sha_now}"
    fi
    DISPATCHED=$((DISPATCHED + 1))
done

if (( DROPPED > 0 )); then
    log "cap ${MAX_DISPATCH} reached: ${DROPPED} eligible version(s) NOT dispatched this run (they remain queued for the next run)"
fi

# Prune observations for versions that are now packaged.
PRUNED="$(jq -c --argjson missing "$(printf '%s\n' "${MISSING:-}" | jq -R . | jq -s .)" \
    'with_entries(select(.key as $k | $missing | index($k)))' <<< "${OBS}")"
if [[ "${PRUNED}" != "${OBS}" ]]; then
    OBS="${PRUNED}"
    OBS_CHANGED=1
fi
if (( OBS_CHANGED )); then
    save_obs "${OBS}"
fi

# --- Latest marker enforcement (aae-orc-l7t7) --------------------------
# The repo-wide Latest marker must track the highest PUBLISHED (non
# draft) release of this pack. GitHub's default assignment follows
# publish order, which is wrong for batch backfills.

HIGHEST_PUBLISHED="$(jq -r --arg p "${PACK}-v" \
    '[.[] | select(.draft == false) | .tag_name | select(startswith($p)) | ltrimstr($p)] | .[]' \
    <<< "${LOCAL_JSON}" | sort -V | tail -1)"

if [[ -n "${HIGHEST_PUBLISHED}" ]]; then
    if [[ -n "${CURRENT_LATEST:-}" ]]; then
        latest_tag="${CURRENT_LATEST}"
    else
        latest_tag="$(gh api "repos/${REPO}/releases/latest" --jq .tag_name 2>/dev/null || echo '')"
    fi
    want_tag="${PACK}-v${HIGHEST_PUBLISHED}"
    if [[ "${latest_tag}" != "${want_tag}" ]]; then
        log "$(dryrun_prefix)fix Latest marker: ${latest_tag:-<none>} -> ${want_tag}"
        if [[ "${DRY_RUN}" != "1" ]]; then
            gh release edit "${want_tag}" -R "${REPO}" --latest
        fi
    else
        log "Latest marker OK (${want_tag})"
    fi
fi

log "done: dispatched=${DISPATCHED} dropped=${DROPPED} dry_run=${DRY_RUN}"
