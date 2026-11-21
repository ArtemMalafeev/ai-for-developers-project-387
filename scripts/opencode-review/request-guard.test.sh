#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$SCRIPT_DIR/request-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKE_ROOT="$TMP/fixtures"
mkdir -p "$FAKE_ROOT" "$TMP/bin"

cat > "$TMP/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  pr)
    echo "unexpected gh pr view: use the REST pull request fields" >&2
    exit 1
    ;;
  api)
    if [ "${2:-}" = "--method" ]; then
      echo "unexpected write through gh api: $*" >&2
      exit 99
    fi
    if [ "${2:-}" = "--paginate" ]; then
      if [ "${FAKE_GH_FAIL_RUNS:-0}" = "1" ]; then
        echo "actions history unavailable" >&2
        exit 1
      fi
      cat "$FAKE_GH_ROOT/runs.json"
      exit 0
    fi
    endpoint="${2:-}"
    if [ "$endpoint" = "repos/owner/repo/pulls/${PR_NUMBER:-40}" ]; then
      cat "$FAKE_GH_ROOT/pr.json"
      exit 0
    fi
    run_id="$(printf '%s' "$endpoint" | sed -E 's#.*/runs/([0-9]+)/attempts/([0-9]+)/jobs.*#\1#')"
    attempt="$(printf '%s' "$endpoint" | sed -E 's#.*/runs/([0-9]+)/attempts/([0-9]+)/jobs.*#\2#')"
    file="$FAKE_GH_ROOT/jobs-$run_id-$attempt.json"
    if [ -f "$file" ]; then
      cat "$file"
    else
      printf '{"total_count":0,"jobs":[]}\n'
    fi
    ;;
  *)
    echo "unexpected gh arguments: $*" >&2
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

write_pr() {
  local association="${1:-OWNER}" head_repo="${2:-owner/repo}"
  jq -n \
    --arg association "$association" \
    --arg headRepo "$head_repo" \
    '{
      number: 40,
      head: {sha: "0123456789abcdef0123456789abcdef01234567", repo: {full_name: $headRepo}},
      user: {login: "artem"},
      author_association: $association,
      draft: false,
      html_url: "https://github.com/owner/repo/pull/40"
    }' > "$FAKE_ROOT/pr.json"
}

write_runs() {
  local json="$1"
  printf '%s\n' "$json" > "$FAKE_ROOT/runs.json"
}

write_jobs() {
  local run_id="$1" attempt="$2" conclusion="$3"
  jq -n --arg conclusion "$conclusion" \
    '{total_count: 1, jobs: [{name: "Gate request", conclusion: $conclusion}]}' \
    > "$FAKE_ROOT/jobs-$run_id-$attempt.json"
}

run_guard() {
  local run_id="${RUN_ID:-900}" run_attempt="${RUN_ATTEMPT:-1}"
  OUTPUT_FILE="$TMP/output"
  : > "$OUTPUT_FILE"
  set +e
  GITHUB_OUTPUT="$OUTPUT_FILE" \
  GITHUB_RUN_ID="$run_id" \
  GITHUB_RUN_ATTEMPT="$run_attempt" \
  GITHUB_EVENT_NAME=issue_comment \
  GITHUB_WORKFLOW_REF="owner/repo/.github/workflows/opencode-review-comments.yml@refs/heads/main" \
  MAX_REQUESTS=3 \
  REPO=owner/repo \
  PR_NUMBER="${PR_NUMBER:-40}" \
  GH_TOKEN=dummy \
  FAKE_GH_ROOT="$FAKE_ROOT" \
  FAKE_GH_FAIL_RUNS="${FAKE_GH_FAIL_RUNS:-0}" \
  PATH="$TMP/bin:$PATH" \
  bash "$GUARD" > "$TMP/stdout" 2> "$TMP/stderr"
  RUN_RC=$?
  set -e
}

output_value() {
  sed -n "s/^$1=//p" "$TMP/output" | tail -n 1
}

assert_decision() {
  local admitted="$1" reason="$2" used="$3" label="$4"
  assert_eq "0" "$RUN_RC" "$label: guard exits cleanly"
  assert_eq "$admitted" "$(output_value admitted)" "$label: admitted"
  assert_eq "$reason" "$(output_value reason)" "$label: reason"
  assert_eq "$used" "$(output_value used)" "$label: used"
}

write_pr OWNER
write_runs '{"total_count":0,"workflow_runs":[]}'
run_guard
assert_decision true admitted 1 "first request is admitted"

write_runs '{"total_count":1,"workflow_runs":[
  {"id":44954978888,"event":"issue_comment","run_attempt":1,"display_title":"OpenCode request gate PR","conclusion":"success"}
]}'
write_jobs 44954978888 1 success
PR_NUMBER=43 run_guard
assert_decision true admitted 2 "PR #43 counts the admitted legacy request"

write_runs '{"total_count":3,"workflow_runs":[
  {"id":44954978888,"event":"issue_comment","run_attempt":1,"display_title":"OpenCode request gate PR","conclusion":"success"},
  {"id":501,"event":"pull_request_review_comment","run_attempt":1,"display_title":"OpenCode request gate PR #43 attempt 1","conclusion":"success"},
  {"id":502,"event":"issue_comment","run_attempt":1,"display_title":"OpenCode request gate PR #43 attempt 1","conclusion":"success"}
]}'
write_jobs 501 1 success
write_jobs 502 1 success
PR_NUMBER=43 run_guard
assert_decision false limit_exhausted 3 "PR #43 blocks after legacy and two current requests"

write_runs '{"total_count":0,"workflow_runs":[]}'
PR_NUMBER=43 run_guard
assert_decision false infra 0 "PR #43 fails closed if the legacy run disappears"

write_runs '{"total_count":2,"workflow_runs":[
  {"id":101,"event":"issue_comment","run_attempt":1,"display_title":"OpenCode request gate PR #40 attempt 1","conclusion":"success"},
  {"id":102,"event":"pull_request_review_comment","run_attempt":2,"display_title":"OpenCode request gate PR #40 attempt 2","conclusion":"failure"}
]}'
write_jobs 101 1 success
write_jobs 102 1 success
write_jobs 102 2 success
run_guard
assert_decision false limit_exhausted 3 "fourth request is blocked before the model"

write_runs '{"total_count":3,"workflow_runs":[
  {"id":201,"event":"issue_comment","run_attempt":1,"display_title":"OpenCode request gate PR #40 attempt 1","conclusion":"cancelled"},
  {"id":202,"event":"issue_comment","run_attempt":1,"display_title":"OpenCode request gate PR #40 attempt 1","conclusion":"timed_out"},
  {"id":203,"event":"pull_request_review_comment","run_attempt":1,"display_title":"OpenCode request gate PR #40 attempt 1","conclusion":"success"}
]}'
write_jobs 201 1 success
write_jobs 202 1 success
write_jobs 203 1 success
run_guard
assert_decision false limit_exhausted 3 "cancelled and timed-out admitted attempts still count"

write_runs '{"total_count":2,"workflow_runs":[
  {"id":900,"event":"issue_comment","run_attempt":3,"display_title":"OpenCode request gate PR #40 attempt 3","conclusion":"in_progress"},
  {"id":301,"event":"pull_request_review_comment","run_attempt":1,"display_title":"OpenCode request gate PR #40 attempt 1","conclusion":"success"}
]}'
write_jobs 900 1 success
write_jobs 900 2 success
write_jobs 301 1 success
RUN_ID=900 RUN_ATTEMPT=3 run_guard
assert_decision false limit_exhausted 3 "Re-run attempts of the current run are counted"

write_runs '{"total_count":1,"workflow_runs":[
  {"id":401,"event":"pull_request","run_attempt":1,"display_title":"OpenCode request gate PR #40 attempt 1","conclusion":"success"}
]}'
write_jobs 401 1 success
run_guard
assert_decision true admitted 1 "non-comment runs with a matching title are ignored"

write_pr NONE
write_runs '{"total_count":0,"workflow_runs":[]}'
run_guard
assert_decision false untrusted 0 "untrusted PR is rejected without reading history"

write_pr OWNER fork/repo
run_guard
assert_decision false untrusted 0 "fork PR is rejected without reading history"

write_pr OWNER
write_runs '{"total_count":0,"workflow_runs":[]}'
FAKE_GH_FAIL_RUNS=1 run_guard
assert_decision false infra 0 "unreadable Actions history fails closed"

if grep -q 'uses: anomalyco/opencode/github@' "$ROOT/.github/workflows/opencode-review-comments.yml"; then
  pass "PR comment workflow calls the developer agent"
else
  fail "PR comment workflow does not call the developer agent"
fi
if grep -q 'actions: read' "$ROOT/.github/workflows/opencode-review-comments.yml"; then
  pass "gate has actions: read"
else
  fail "gate is missing actions: read"
fi
if grep -q 'name: Gate request' "$ROOT/.github/workflows/opencode-review-comments.yml" &&
  grep -Fq 'run-name: "OpenCode request gate PR #' "$ROOT/.github/workflows/opencode-review-comments.yml"; then
  pass "gate has an explicit run-name and job name"
else
  fail "gate run-name or job name is missing"
fi
if grep -Fq "needs.gate.outputs.admitted == 'true'" "$ROOT/.github/workflows/opencode-review-comments.yml"; then
  pass "developer agent starts only after an admitted gate"
else
  fail "developer agent is not gated on the admission output"
fi
if grep -q 'build-mock-event.sh' "$ROOT/.github/workflows/opencode-review-comments.yml" &&
  grep -q 'MOCK_EVENT:' "$ROOT/.github/workflows/opencode-review-comments.yml"; then
  pass "inline comments are normalized for the developer agent"
else
  fail "inline comment normalization is missing"
fi

cat > "$TMP/review-event.json" <<'REVIEW_EVENT'
{
  "action": "created",
  "comment": {
    "id": 123,
    "body": "/oc Исправь это место",
    "path": "src/file.ts",
    "diff_hunk": "@@ -1 +1 @@",
    "line": 1,
    "original_line": 1,
    "position": 1,
    "commit_id": "0123456789abcdef0123456789abcdef01234567",
    "original_commit_id": "0123456789abcdef0123456789abcdef01234567"
  },
  "pull_request": {"number": 40},
  "repository": {"full_name": "owner/repo"}
}
REVIEW_EVENT
: > "$TMP/mock-output"
GITHUB_EVENT_PATH="$TMP/review-event.json" \
GITHUB_EVENT_NAME=pull_request_review_comment \
GITHUB_OUTPUT="$TMP/mock-output" \
GITHUB_REPOSITORY=owner/repo \
GITHUB_REPOSITORY_OWNER=owner \
GITHUB_ACTOR=artem \
GITHUB_REF=refs/heads/main \
GITHUB_SHA=0123456789abcdef0123456789abcdef01234567 \
GITHUB_WORKFLOW="OpenCode Review Request" \
GITHUB_JOB=agent \
bash "$SCRIPT_DIR/build-mock-event.sh"
mock_context="$(sed -n 's/^context=//p' "$TMP/mock-output")"
assert_eq "pull_request_review_comment" "$(printf '%s' "$mock_context" | jq -r .eventName)" "inline event name"
assert_eq "40" "$(printf '%s' "$mock_context" | jq -r .payload.issue.number)" "inline event PR number"
assert_eq "src/file.ts" "$(printf '%s' "$mock_context" | jq -r .payload.comment.path)" "inline event keeps diff context"
assert_eq "owner" "$(printf '%s' "$mock_context" | jq -r .repo.owner)" "inline event repo owner"
if grep -q 'run-review.sh' "$ROOT/.github/workflows/opencode-review-comments.yml"; then
  fail "PR comment workflow still runs the read-only reviewer"
else
  pass "PR comment workflow does not run the read-only reviewer"
fi
if grep -q 'run-review.sh' "$ROOT/.github/workflows/opencode-review.yml"; then
  pass "independent reviewer stays on pull_request"
else
  fail "independent reviewer is missing from the pull_request workflow"
fi
if grep -q 'write-playwright-manifest.sh' "$ROOT/.github/workflows/opencode-review.yml" &&
  grep -q 'git rev-parse HEAD' "$ROOT/scripts/opencode-review/write-playwright-manifest.sh"; then
  pass "Playwright artifact includes an actual SHA manifest"
else
  fail "Playwright manifest is missing"
fi
if grep -q 'opencode run --pure' "$ROOT/scripts/opencode-review/run-review.sh" &&
  grep -Fq -- "-- \"\$(cat \"\$PROMPT_FILE\")\"" "$ROOT/scripts/opencode-review/run-review.sh"; then
  pass "auto-review uses the real --pure flag and a delimited prompt"
else
  fail "auto-review invocation is missing --pure or the prompt delimiter"
fi

if [ "$failures" -ne 0 ]; then
  printf '%s gate checks failed\n' "$failures" >&2
  exit 1
fi
printf 'All gate checks passed\n'
