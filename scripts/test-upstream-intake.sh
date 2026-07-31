#!/usr/bin/env bash
# Scenario tests for scripts/upstream-intake.sh. Self-contained: all
# data sources come through the script's test seams, DRY_RUN=1
# throughout, no network calls and no mutations. Run from anywhere:
#
#   bash scripts/test-upstream-intake.sh
#
# CI runs this via .github/workflows/intake-tests.yml.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/upstream-intake.sh"
DIR="$(mktemp -d -t intake-test-XXXXXX)"
trap 'rm -rf "$DIR"' EXIT
cd "$DIR"

NOW=1753900000  # fixed clock
h() { python3 -c "import datetime;print(datetime.datetime.fromtimestamp($NOW-$1*3600,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))"; }

reset_fixtures() {
    # upstream: v6.11.0 young, v6.11.1 and v6.11.2 old, plus a
    # prerelease and a non-version tag that must be filtered out.
    cat > upstream.json <<EOF
[
 {"tag_name":"v6.11.2","published_at":"$(h 200)","draft":false,"prerelease":false},
 {"tag_name":"v6.11.1","published_at":"$(h 100)","draft":false,"prerelease":false},
 {"tag_name":"v6.11.0","published_at":"$(h 1)","draft":false,"prerelease":false},
 {"tag_name":"v6.12.0-rc.1","published_at":"$(h 5)","draft":false,"prerelease":true},
 {"tag_name":"web-bundles-v1.0.0","published_at":"$(h 500)","draft":false,"prerelease":false},
 {"tag_name":"v6.10.0","published_at":"$(h 600)","draft":false,"prerelease":false},
 {"tag_name":"v6.3.0","published_at":"$(h 2000)","draft":false,"prerelease":false}
]
EOF
    cat > local.json <<'EOF'
[
 {"tag_name":"bmad-v6.10.0","draft":false},
 {"tag_name":"bmad-v6.9.0","draft":false},
 {"tag_name":"bmad-v6.8.0","draft":false},
 {"tag_name":"bmad-v6.7.1","draft":false},
 {"tag_name":"bmad-v6.7.0","draft":false},
 {"tag_name":"bmad-v6.6.0","draft":false},
 {"tag_name":"bmad-v6.5.0","draft":false},
 {"tag_name":"bmad-v6.4.0","draft":false},
 {"tag_name":"bmad-v6.3.0","draft":false}
]
EOF
    cat > shas.json <<'EOF'
{"v6.11.0":"aaa1111111111111","v6.11.1":"bbb2222222222222","v6.11.2":"ccc3333333333333"}
EOF
    echo '[]' > issues.json
    echo '{}' > obs.json
    # wide validated bracket so the dispatch path is reachable
    cat > registry-wide.yaml <<'EOF'
validated:
  - min: 6.3.0
    max: 6.99.0
EOF
    # narrow bracket mirroring the real register's ceiling
    cat > registry-narrow.yaml <<'EOF'
validated:
  - min: 6.3.0
    max: 6.10.0
EOF
}

run_intake() { # extra env assignments as args
    env DRY_RUN=1 NOW_EPOCH=$NOW \
        UPSTREAM_RELEASES_FILE="$DIR/upstream.json" \
        LOCAL_RELEASES_FILE="$DIR/local.json" \
        SHA_FILE="$DIR/shas.json" \
        ISSUES_FILE="$DIR/issues.json" \
        OBS_FILE="$DIR/obs.json" \
        REGISTRY_FILE="$DIR/registry-wide.yaml" \
        CURRENT_LATEST=bmad-v6.10.0 \
        "$@" bash "$SCRIPT"
}

PASS=0; FAIL=0
check() { # name output-file pattern
    if grep -qE "$3" "$2"; then PASS=$((PASS+1)); echo "PASS: $1"
    else FAIL=$((FAIL+1)); echo "FAIL: $1  (missing: $3)"; sed 's/^/    /' "$2"; fi
}
check_absent() {
    if grep -qE "$3" "$2"; then FAIL=$((FAIL+1)); echo "FAIL: $1  (unexpected: $3)"; sed 's/^/    /' "$2"
    else PASS=$((PASS+1)); echo "PASS: $1"; fi
}

echo "=== T1: fresh observations, nothing dispatched ==="
reset_fixtures
run_intake > t1.out 2>&1
check "T1 6.11.0 first-observed"      t1.out '6\.11\.0: first observation'
check "T1 6.11.1 first-observed"      t1.out '6\.11\.1: first observation'
check "T1 prerelease filtered"        t1.out '^\[intake\] unpackaged versions.*6\.11\.0 6\.11\.1 6\.11\.2'
check_absent "T1 no rc leaked"        t1.out '6\.12\.0'
check_absent "T1 nothing dispatched"  t1.out 'dispatch build-pack'
check "T1 obs save (dry)"             t1.out 'DRY-RUN: would save observations'
check "T1 marker ok"                  t1.out 'Latest marker OK \(bmad-v6\.10\.0\)'

echo "=== T2: soaked + stable SHA dispatches with rung composition + expected_sha ==="
reset_fixtures
cat > obs.json <<EOF
{"6.11.0":{"sha":"aaa1111111111111","first_seen":"$(h 1)"},
 "6.11.1":{"sha":"bbb2222222222222","first_seen":"$(h 30)"},
 "6.11.2":{"sha":"ccc3333333333333","first_seen":"$(h 30)"}}
EOF
run_intake > t2.out 2>&1
check "T2 young version soaks"        t2.out '6\.11\.0: soaking \(published 1h/72h'
check "T2 6.11.1 dispatched"          t2.out 'would dispatch build-pack\.yml: pack=bmad version=6\.11\.1 modules=bmm,cis,gds,tea,bmb,wds pins=auto sign=true publish=true expected_sha=bbb2222222222222'
check "T2 6.11.2 dispatched"          t2.out 'would dispatch build-pack\.yml: pack=bmad version=6\.11\.2 .*expected_sha=ccc3333333333333'
check "T2 summary"                    t2.out 'done: dispatched=2 dropped=0'

echo "=== T3: outside validated bracket -> revalidation issue, no dispatch ==="
reset_fixtures
cat > obs.json <<EOF
{"6.11.1":{"sha":"bbb2222222222222","first_seen":"$(h 30)"}}
EOF
run_intake REGISTRY_FILE="$DIR/registry-narrow.yaml" > t3.out 2>&1
check "T3 bracket refusal"            t3.out '6\.11\.1: soaked \+ sha stable, but outside the validated support bracket'
check "T3 revalidation issue"         t3.out 'would open issue: upstream-intake: bmad 6\.11\.1 is outside the validated support bracket'
check_absent "T3 nothing dispatched"  t3.out 'dispatch build-pack'

echo "=== T4: SHA drift during soak -> refused + quarantine issue ==="
reset_fixtures
cat > obs.json <<EOF
{"6.11.1":{"sha":"OLD9999999999999","first_seen":"$(h 30)"}}
EOF
run_intake > t4.out 2>&1
check "T4 refused"                    t4.out '6\.11\.1: REFUSED, tag SHA changed during soak \(OLD999999999 -> bbb222222222\)'
check "T4 drift issue"                t4.out 'would open issue: upstream-intake: bmad v6\.11\.1 tag SHA changed during soak'
check_absent "T4 not dispatched"      t4.out 'dispatch build-pack\.yml: pack=bmad version=6\.11\.1'

echo "=== T5: per-run cap enforced + dropped logged ==="
reset_fixtures
python3 - <<PY
import json
u=json.load(open('upstream.json'))
for r in u:
    if r['tag_name']=='v6.11.0': r['published_at']="$(h 90)"
json.dump(u,open('upstream.json','w'))
PY
cat > obs.json <<EOF
{"6.11.0":{"sha":"aaa1111111111111","first_seen":"$(h 90)"},
 "6.11.1":{"sha":"bbb2222222222222","first_seen":"$(h 30)"},
 "6.11.2":{"sha":"ccc3333333333333","first_seen":"$(h 30)"}}
EOF
run_intake MAX_DISPATCH=1 > t5.out 2>&1
check "T5 one dispatched"             t5.out 'done: dispatched=1 dropped=2'
check "T5 drop logged"                t5.out 'cap 1 reached: 2 eligible version\(s\) NOT dispatched'

echo "=== T6: stale observation pruned + marker drift fixed ==="
reset_fixtures
cat > obs.json <<EOF
{"6.10.0":{"sha":"stale","first_seen":"$(h 400)"},
 "6.11.0":{"sha":"aaa1111111111111","first_seen":"$(h 90)"}}
EOF
run_intake CURRENT_LATEST=bmad-v6.3.0 > t6.out 2>&1
check "T6 pruned save excludes packaged" t6.out 'would save observations: \{"6\.11\.[012]'
check_absent "T6 6.10.0 pruned"       t6.out 'would save observations: .*"6\.10\.0"'
check "T6 marker drift fixed"         t6.out 'would fix Latest marker: bmad-v6\.3\.0 -> bmad-v6\.10\.0'

echo "=== T7: open drift issue quarantines even after a clean re-soak ==="
reset_fixtures
cat > obs.json <<EOF
{"6.11.1":{"sha":"bbb2222222222222","first_seen":"$(h 30)"},
 "6.11.2":{"sha":"ccc3333333333333","first_seen":"$(h 30)"}}
EOF
cat > issues.json <<'EOF'
[{"number":7,"title":"upstream-intake: bmad v6.11.1 tag SHA changed during soak","body":"quarantine"}]
EOF
run_intake > t7.out 2>&1
check "T7 quarantined"                t7.out '6\.11\.1: quarantined, drift issue still open'
check_absent "T7 quarantined not dispatched" t7.out 'dispatch build-pack\.yml: pack=bmad version=6\.11\.1'
check "T7 unquarantined sibling dispatches"  t7.out 'would dispatch build-pack\.yml: pack=bmad version=6\.11\.2'

echo "=== T8: non-numeric settings rejected before any arithmetic ==="
reset_fixtures
run_intake SOAK_HOURS='arr[$(echo pwned)]' > t8.out 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then PASS=$((PASS+1)); echo "PASS: T8 nonzero exit"; else FAIL=$((FAIL+1)); echo "FAIL: T8 nonzero exit"; fi
check "T8 rejection message"          t8.out 'SOAK_HOURS must be a non-negative integer'
# the payload must survive as literal text (echoed back unevaluated),
# never as command output on its own line
check "T8 payload preserved literal"  t8.out 'got: arr\[\$\(echo pwned\)\]'
check_absent "T8 payload not executed" t8.out '^pwned$'

echo "=== T9: unresolvable SHA warns and skips instead of dying ==="
reset_fixtures
cat > shas.json <<'EOF'
{"v6.11.0":"aaa1111111111111","v6.11.1":"bbb2222222222222"}
EOF
run_intake > t9.out 2>&1
check "T9 warn"                       t9.out 'WARN: cannot resolve SHA for v6\.11\.2'
check "T9 others proceed"             t9.out '6\.11\.1: first observation'
check "T9 run completes"              t9.out 'done: dispatched=0'

echo "=== T10: observations load from the ledger issue body ==="
reset_fixtures
rm obs.json   # no OBS_FILE seam: force the ledger path
cat > issues.json <<EOF
[{"number":12,"title":"upstream-intake: observation ledger (machine state)","body":"Machine-maintained. Do not hand-edit.\n\n\`\`\`json\n{\"6.11.1\":{\"sha\":\"bbb2222222222222\",\"first_seen\":\"$(h 30)\"}}\n\`\`\`\n"}]
EOF
env DRY_RUN=1 NOW_EPOCH=$NOW \
    UPSTREAM_RELEASES_FILE="$DIR/upstream.json" \
    LOCAL_RELEASES_FILE="$DIR/local.json" \
    SHA_FILE="$DIR/shas.json" \
    ISSUES_FILE="$DIR/issues.json" \
    REGISTRY_FILE="$DIR/registry-wide.yaml" \
    CURRENT_LATEST=bmad-v6.10.0 \
    bash "$SCRIPT" > t10.out 2>&1
check "T10 ledger obs honored"        t10.out 'would dispatch build-pack\.yml: pack=bmad version=6\.11\.1'
check "T10 save targets ledger (dry)" t10.out 'DRY-RUN: would save observations'

echo
echo "=== RESULT: $PASS passed, $FAIL failed ==="
exit $((FAIL > 0))
