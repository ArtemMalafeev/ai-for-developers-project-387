#!/usr/bin/env bash
set -euo pipefail

: "${OUTPUT_PATH:?OUTPUT_PATH is required}"
: "${EXPECTED_SHA:?EXPECTED_SHA is required}"

actual_sha="$(git rev-parse HEAD)"
test_outcome="${TEST_OUTCOME:-unknown}"
test_conclusion="${TEST_CONCLUSION:-unknown}"
job_status="${JOB_STATUS:-unknown}"
test_command="${TEST_COMMAND:-unknown}"
run_url="${RUN_URL:-}"
run_id="${GITHUB_RUN_ID:-}"
run_attempt="${GITHUB_RUN_ATTEMPT:-}"
workflow="${GITHUB_WORKFLOW:-}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

jq -n \
  --arg sha "$actual_sha" \
  --arg expectedSha "$EXPECTED_SHA" \
  --arg testOutcome "$test_outcome" \
  --arg testConclusion "$test_conclusion" \
  --arg jobStatus "$job_status" \
  --arg command "$test_command" \
  --arg runUrl "$run_url" \
  --arg runId "$run_id" \
  --arg runAttempt "$run_attempt" \
  --arg workflow "$workflow" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  '{
    schema: 1,
    sha: $sha,
    expectedSha: $expectedSha,
    shaMatches: ($sha == $expectedSha),
    testResult: {
      outcome: $testOutcome,
      conclusion: $testConclusion,
      jobStatus: $jobStatus
    },
    command: $command,
    workflow: $workflow,
    runId: $runId,
    runAttempt: $runAttempt,
    runUrl: $runUrl,
    generatedAt: $generatedAt
  }' > "$OUTPUT_PATH"

test -s "$OUTPUT_PATH"
printf 'Playwright manifest written to %s (sha=%s, test=%s)\n' \
  "$OUTPUT_PATH" "$actual_sha" "$test_outcome"
