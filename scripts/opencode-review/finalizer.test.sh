#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINALIZER="$SCRIPT_DIR/finalize-request.sh"
PREFLIGHT="$SCRIPT_DIR/preflight.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKE_ROOT="$TMP/fixtures"
WORK="$TMP/work"
mkdir -p "$FAKE_ROOT" "$WORK/artifact" "$TMP/bin"

SHA="0123456789abcdef0123456789abcdef01234567"
RUN_URL="https://github.com/owner/repo/actions/runs/900"

cat > "$TMP/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  pr)
    subcommand="${2:-}"
    case "$subcommand" in
      view)
        shift 2
        json=""
        jq_filter="."
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --repo) shift 2 ;;
            --json) json="$2"; shift 2 ;;
            --jq) jq_filter="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        case "$json" in
          comments)
            if [ -s "$FAKE_GH_ROOT/comments.json" ]; then
              jq -r "$jq_filter" "$FAKE_GH_ROOT/comments.json"
            fi
            ;;
          headRefOid)
            printf '%s\n' "${FAKE_GH_HEAD_SHA:-}"
            ;;
          *)
            printf 'unexpected gh pr view --json %s\n' "$json" >&2
            exit 1
            ;;
        esac
        ;;
      comment)
        shift 2
        body_file=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --repo) shift 2 ;;
            --body-file) body_file="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        [ -n "$body_file" ] || { printf 'missing --body-file\n' >&2; exit 1; }
        cat "$body_file" >> "$FAKE_GH_ROOT/published.md"
        printf '\n---comment---\n' >> "$FAKE_GH_ROOT/published.md"
        ;;
      *)
        printf 'unexpected gh pr subcommand: %s\n' "$subcommand" >&2
        exit 1
        ;;
    esac
    ;;
  api)
    if [ "${2:-}" = "--method" ]; then
      printf 'unexpected write through gh api: %s\n' "$*" >&2
      exit 99
    fi
    endpoint="${2:-}"
    if [ "${FAKE_GH_FAIL_JOBS:-0}" = "1" ]; then
      printf 'jobs API unavailable\n' >&2
      exit 1
    fi
    if ! printf '%s' "$endpoint" | grep -Eq '/runs/[0-9]+/attempts/[0-9]+/jobs'; then
      printf 'unexpected jobs endpoint: %s\n' "$endpoint" >&2
      exit 1
    fi
    run_id="$(printf '%s' "$endpoint" | sed -E 's#.*/runs/([0-9]+)/attempts/([0-9]+)/jobs.*#\1#')"
    attempt="$(printf '%s' "$endpoint" | sed -E 's#.*/runs/([0-9]+)/attempts/([0-9]+)/jobs.*#\2#')"
    if [ -f "$FAKE_GH_ROOT/jobs-$run_id-$attempt.json" ]; then
      cat "$FAKE_GH_ROOT/jobs-$run_id-$attempt.json"
    else
      printf '{"total_count":0,"jobs":[]}\n'
    fi
    ;;
  *)
    printf 'unexpected gh arguments: %s\n' "$*" >&2
    exit 1
    ;;
esac
FAKE_GH
chmod +x "$TMP/bin/gh"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label: expected [$expected], got [$actual]"; fi
}
assert_contains() {
  local expected="$1" file="$2" label="$3"
  if grep -Fq -- "$expected" "$file"; then pass "$label"; else fail "$label: missing [$expected]"; fi
}
assert_not_contains() {
  local unexpected="$1" file="$2" label="$3"
  if grep -Fq -- "$unexpected" "$file"; then fail "$label: found [$unexpected]"; else pass "$label"; fi
}

reset_case() {
  rm -rf "$FAKE_ROOT" "$WORK"
  mkdir -p "$FAKE_ROOT" "$WORK/artifact"
}

write_gate() {
  local admitted="$1" reason="$2" head_sha="${3:-$SHA}"
  jq -n \
    --arg admitted "$admitted" \
    --arg reason "$reason" \
    --arg headSha "$head_sha" \
    '{
      schema: 1,
      prNumber: "40",
      headSha: $headSha,
      admitted: $admitted,
      reason: $reason,
      used: "1",
      limit: "3",
      runId: "900",
      runAttempt: "1",
      runUrl: "https://github.com/owner/repo/actions/runs/900"
    }' > "$WORK/artifact/gate.json"
}

write_jobs() {
  local job_conclusion="$1" agent_step_conclusion="$2" failing_setup_step="${3:-}"
  local started_at="${4:-}" completed_at="${5:-}"
  jq -n \
    --arg jobConclusion "$job_conclusion" \
    --arg agentStepConclusion "$agent_step_conclusion" \
    --arg failingSetupStep "$failing_setup_step" \
    --arg startedAt "$started_at" \
    --arg completedAt "$completed_at" \
    '{
      total_count: 1,
      jobs: [{
        name: "Agent request",
        conclusion: $jobConclusion,
        steps: ([
          {name: "Preflight agent request", conclusion: "success"},
          {name: "Checkout trusted default branch", conclusion: "success"},
          {name: "Checkout agent skills", conclusion: "success"},
          {name: "Make agent skills available", conclusion: "success"},
          {name: "Build normalized event for inline comment", conclusion: "success"},
          {name: "Run OpenCode developer agent", conclusion: $agentStepConclusion},
          {name: "Remove temporary git credentials", conclusion: "success"}
        ] | map(if $failingSetupStep != "" and .name == $failingSetupStep then .conclusion = "failure" else . end))
      }]
    }
    | .jobs[0] |= (if $startedAt != "" then .started_at = $startedAt | .completed_at = $completedAt else . end)' \
    > "$FAKE_ROOT/jobs-900-1.json"
}

write_existing_comments() {
  local body="$1"
  jq -n --arg body "$body" '{comments: [{body: $body}]}' > "$FAKE_ROOT/comments.json"
}

run_finalizer() {
  local conclusion="$1" attempt="${2:-1}"
  : > "$FAKE_ROOT/published.md"
  set +e
  PATH="$TMP/bin:$PATH" \
  FAKE_GH_ROOT="$FAKE_ROOT" \
  FAKE_GH_HEAD_SHA="$SHA" \
  FAKE_GH_FAIL_JOBS="${FAKE_GH_FAIL_JOBS:-0}" \
  GH_TOKEN=dummy \
  REPO=owner/repo \
  RUN_ID=900 \
  RUN_ATTEMPT="$attempt" \
  RUN_CONCLUSION="$conclusion" \
  RUN_URL="$RUN_URL" \
  DISPLAY_TITLE="OpenCode request gate PR #40 attempt $attempt" \
  ARTIFACT_DIR="$WORK/artifact" \
  OUTPUT_PATH="$WORK/comment.md" \
  LIMIT=3 \
  bash "$FINALIZER" > "$TMP/stdout" 2> "$TMP/stderr"
  FINALIZER_RC=$?
  set -e
}

assert_published() {
  local reason="$1" label="$2"
  assert_eq "0" "$FINALIZER_RC" "$label: finalizer exits cleanly"
  if [ -s "$FAKE_ROOT/published.md" ]; then pass "$label: comment published"; else fail "$label: comment not published"; fi
  assert_contains "Итог: \`$reason\`" "$FAKE_ROOT/published.md" "$label: reason is $reason"
  assert_contains "$SHA" "$FAKE_ROOT/published.md" "$label: head SHA is included"
  assert_contains "$RUN_URL" "$FAKE_ROOT/published.md" "$label: run URL is included"
  assert_contains "<!-- opencode-review-request:run=900 attempt=1 -->" "$FAKE_ROOT/published.md" "$label: dedupe marker is included"
}

assert_not_published() {
  local label="$1"
  assert_eq "0" "$FINALIZER_RC" "$label: finalizer exits cleanly"
  if [ -s "$FAKE_ROOT/published.md" ]; then fail "$label: comment was published"; else pass "$label: comment is not published"; fi
}

reset_case
write_gate true admitted
write_jobs failure success
run_finalizer success
assert_not_published "successful run is not duplicated"

reset_case
write_gate false limit_exhausted
write_jobs failure success
run_finalizer failure
assert_not_published "limit_exhausted gate decision is not duplicated"

reset_case
write_gate true admitted
write_jobs failure failure
run_finalizer failure
assert_published agent_failed "agent step failure"

reset_case
write_gate true admitted
write_jobs failure failure "" "2026-11-21T20:00:00Z" "2026-11-21T20:30:00Z"
run_finalizer failure
assert_published timeout "job timeout is not reported as agent failure"

reset_case
write_gate true admitted
write_jobs failure success "Make agent skills available"
run_finalizer failure
assert_published infra "action setup failure"

reset_case
write_gate true admitted
write_jobs failure success "Preflight agent request"
run_finalizer failure
assert_published infra "missing API key preflight failure"

reset_case
write_gate true admitted
write_jobs cancelled success
run_finalizer cancelled
assert_published cancelled "cancelled run"

reset_case
write_gate true admitted
write_jobs cancelled cancelled "" "2026-11-21T20:00:00Z" "2026-11-21T20:30:00Z"
run_finalizer cancelled
assert_published timeout "job timeout reported as cancelled by GitHub"

reset_case
write_gate true admitted
write_jobs cancelled cancelled "" "2026-11-21T20:00:00Z" "2026-11-21T20:05:00Z"
run_finalizer cancelled
assert_published cancelled "short cancelled run stays cancelled"

reset_case
write_gate true admitted
write_jobs timed_out cancelled
run_finalizer timed_out
assert_published timeout "workflow timeout"

reset_case
write_gate true admitted
write_jobs timed_out cancelled
run_finalizer failure
assert_published timeout "job timeout reported as failed run"

reset_case
write_gate true admitted
write_jobs failure cancelled
run_finalizer failure
assert_published timeout "timed-out agent step reported as cancelled"

reset_case
write_gate true admitted
write_jobs failure failure
write_existing_comments "<!-- opencode-review-request:run=900 attempt=1 -->"
run_finalizer failure
assert_not_published "existing result for the same attempt is not duplicated"

reset_case
write_gate true admitted
write_jobs failure success "Make agent skills available"
write_existing_comments "<!-- opencode-review-request:run=899 attempt=1 -->"
run_finalizer failure
assert_published infra "other attempts do not block publication"

reset_case
write_jobs failure success "Make agent skills available"
run_finalizer failure
assert_published infra "missing gate artifact still classifies setup failure"
assert_contains "Проверенный head: \`$SHA\`" "$FAKE_ROOT/published.md" "missing gate artifact falls back to PR head"

reset_case
write_gate "" "" "$SHA"
write_jobs cancelled success
run_finalizer cancelled
assert_published cancelled "artifact without an admission decision still gets an abnormal result"

reset_case
write_gate true admitted
write_jobs failure failure
FAKE_GH_FAIL_JOBS=1 run_finalizer failure
assert_published infra "unreadable jobs fail closed as infra"

run_preflight() {
  set +e
  GATE_ADMITTED="${1:-true}" HEAD_SHA="${2:-$SHA}" OPENCODE_API_KEY="${3-secret}" \
    bash "$PREFLIGHT" > "$TMP/preflight.out" 2> "$TMP/preflight.err"
  PREFLIGHT_RC=$?
  set -e
}

run_preflight true "$SHA" ""
assert_eq "1" "$PREFLIGHT_RC" "missing OPENCODE_API_KEY fails preflight"
assert_contains "OPENCODE_API_KEY" "$TMP/preflight.err" "preflight names the missing secret"
run_preflight true "$SHA" "secret-value"
assert_eq "0" "$PREFLIGHT_RC" "present OPENCODE_API_KEY passes preflight"
assert_not_contains "secret-value" "$TMP/preflight.out" "preflight does not print the secret"
run_preflight false "$SHA" "secret-value"
assert_eq "1" "$PREFLIGHT_RC" "preflight rejects a request the gate did not admit"

OUTPUT_PATH="$TMP/gate-artifact.json" \
PR_NUMBER=40 \
HEAD_SHA="$SHA" \
ADMITTED=true \
REASON=admitted \
USED=1 \
LIMIT=3 \
RUN_URL="$RUN_URL" \
GITHUB_RUN_ID=900 \
GITHUB_RUN_ATTEMPT=2 \
GITHUB_EVENT_NAME=issue_comment \
  bash "$SCRIPT_DIR/write-gate-artifact.sh" > /dev/null
assert_eq "40" "$(jq -r .prNumber "$TMP/gate-artifact.json")" "gate artifact keeps the PR number"
assert_eq "$SHA" "$(jq -r .headSha "$TMP/gate-artifact.json")" "gate artifact keeps the head SHA"
assert_eq "true" "$(jq -r .admitted "$TMP/gate-artifact.json")" "gate artifact keeps the admission decision"
assert_eq "2" "$(jq -r .runAttempt "$TMP/gate-artifact.json")" "gate artifact keeps the run attempt"

if grep -q 'finalize-request.sh' "$SCRIPT_DIR/../../.github/opencode-review-finalizer.yml.pending" &&
  grep -q 'workflow_run:' "$SCRIPT_DIR/../../.github/opencode-review-finalizer.yml.pending" &&
  ! grep -q 'secrets.OPENCODE_API_KEY' "$SCRIPT_DIR/../../.github/opencode-review-finalizer.yml.pending"; then
  pass "finalizer runs on workflow_run without the model secret"
else
  fail "finalizer workflow is missing workflow_run or receives OPENCODE_API_KEY"
fi
if grep -q 'write-gate-artifact.sh' "$SCRIPT_DIR/../../.github/opencode-review-comments.yml.pending" &&
  grep -q 'preflight.sh' "$SCRIPT_DIR/../../.github/opencode-review-comments.yml.pending"; then
  pass "request workflow uploads gate data and runs preflight"
else
  fail "request workflow is missing the gate artifact or preflight"
fi
if ! grep -q 'AGENT_RESULT' "$SCRIPT_DIR/../../.github/opencode-review-comments.yml.pending" &&
  ! grep -q 'reason=agent_failed' "$SCRIPT_DIR/../../.github/opencode-review-comments.yml.pending"; then
  pass "in-workflow summary does not guess agent failures from needs"
else
  fail "in-workflow summary still classifies agent results"
fi

if [ "$failures" -ne 0 ]; then
  printf '%s finalizer checks failed\n' "$failures" >&2
  exit 1
fi
printf 'All finalizer checks passed\n'
