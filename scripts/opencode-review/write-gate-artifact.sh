#!/usr/bin/env bash
set -euo pipefail

: "${OUTPUT_PATH:?OUTPUT_PATH is required}"

pr_number="${PR_NUMBER:-}"
head_sha="${HEAD_SHA:-}"
admitted="${ADMITTED:-}"
reason="${REASON:-}"
used="${USED:-0}"
limit="${LIMIT:-3}"
run_url="${RUN_URL:-}"
run_id="${GITHUB_RUN_ID:-}"
run_attempt="${GITHUB_RUN_ATTEMPT:-}"
event_name="${GITHUB_EVENT_NAME:-}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

jq -n \
  --arg prNumber "$pr_number" \
  --arg headSha "$head_sha" \
  --arg admitted "$admitted" \
  --arg reason "$reason" \
  --arg used "$used" \
  --arg limit "$limit" \
  --arg runUrl "$run_url" \
  --arg runId "$run_id" \
  --arg runAttempt "$run_attempt" \
  --arg event "$event_name" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  '{
    schema: 1,
    prNumber: $prNumber,
    headSha: $headSha,
    admitted: $admitted,
    reason: $reason,
    used: $used,
    limit: $limit,
    runId: $runId,
    runAttempt: $runAttempt,
    event: $event,
    runUrl: $runUrl,
    generatedAt: $generatedAt
  }' > "$OUTPUT_PATH"

test -s "$OUTPUT_PATH"
printf 'Gate artifact written to %s (pr=%s admitted=%s reason=%s)\n' \
  "$OUTPUT_PATH" "${pr_number:-unknown}" "${admitted:-unknown}" "${reason:-unknown}"
