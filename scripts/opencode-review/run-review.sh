#!/usr/bin/env bash
set -uo pipefail

: "${RESULT_PATH:?RESULT_PATH is required}"
: "${REVIEW_PATH:?REVIEW_PATH is required}"
: "${LOG_PATH:?LOG_PATH is required}"
: "${PROMPT_FILE:?PROMPT_FILE is required}"
: "${CONTEXT_FILE:?CONTEXT_FILE is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
: "${RUN_URL:?RUN_URL is required}"

timeout_seconds="${TIMEOUT_SECONDS:-900}"
model="${OPENCODE_MODEL:-opencode/deepseek-v4.1-flash}"
output_dir="$(dirname "$RESULT_PATH")"
mkdir -p "$output_dir" "$(dirname "$LOG_PATH")" "$(dirname "$REVIEW_PATH")"

write_result() {
  local reason="$1"
  local exit_code="$2"
  jq -n \
    --arg reason "$reason" \
    --arg sha "$HEAD_SHA" \
    --arg runUrl "$RUN_URL" \
    --arg log "$LOG_PATH" \
    --arg review "$REVIEW_PATH" \
    --argjson exitCode "$exit_code" \
    '{reason: $reason, sha: $sha, runUrl: $runUrl, log: $log, review: $review, exitCode: $exitCode}' \
    > "$RESULT_PATH"
}

finish() {
  local reason="$1"
  local exit_code="$2"
  write_result "$reason" "$exit_code"
  printf 'OpenCode review finished with reason=%s exit=%s\n' "$reason" "$exit_code"
  if [ "$reason" != "success" ]; then
    exit 1
  fi
  cat "$REVIEW_PATH"
}

if ! command -v opencode >/dev/null 2>&1; then
  printf 'opencode CLI is not installed\n' >&2
  finish "infra" 127
fi

started_at="$(date -u +%FT%TZ)"
set +e
timeout --signal=TERM --kill-after=20s "$timeout_seconds" \
  opencode run --pure --format json \
  --model "$model" \
  --title "Авторевью PR (${HEAD_SHA:0:12})" \
  --file "$CONTEXT_FILE" \
  -- "$(cat "$PROMPT_FILE")" \
  > "$output_dir/opencode.json" 2> "$LOG_PATH"
exit_code=$?
set -e

printf 'OpenCode started at %s, exit=%s\n' "$started_at" "$exit_code" >> "$LOG_PATH"

if [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]; then
  finish "timeout" "$exit_code"
fi

if [ "$exit_code" -eq 126 ] || [ "$exit_code" -eq 127 ]; then
  finish "infra" "$exit_code"
fi

if [ "$exit_code" -ne 0 ]; then
  finish "agent_failed" "$exit_code"
fi

jq -rs '[.[] | select(.type == "text") | .part.text] | join("\n")' \
  "$output_dir/opencode.json" > "$REVIEW_PATH" 2>/dev/null || true

if [ ! -s "$REVIEW_PATH" ]; then
  finish "agent_failed" "$exit_code"
fi

finish "success" "$exit_code"
