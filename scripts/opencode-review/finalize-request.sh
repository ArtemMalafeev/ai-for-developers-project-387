#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${RUN_ID:?RUN_ID is required}"
: "${RUN_URL:?RUN_URL is required}"
: "${RUN_CONCLUSION:?RUN_CONCLUSION is required}"

: "${ARTIFACT_DIR:?ARTIFACT_DIR is required}"
: "${OUTPUT_PATH:?OUTPUT_PATH is required}"

RUN_ATTEMPT="${RUN_ATTEMPT:-1}"
LIMIT="${LIMIT:-3}"
AGENT_JOB_NAME="${AGENT_JOB_NAME:-Agent request}"
AGENT_STEP_NAME="${AGENT_STEP_NAME:-Run OpenCode developer agent}"
AGENT_TIMEOUT_MINUTES="${AGENT_TIMEOUT_MINUTES:-30}"
DISPLAY_TITLE="${DISPLAY_TITLE:-}"

case "$AGENT_TIMEOUT_MINUTES" in
  ''|*[!0-9]*) AGENT_TIMEOUT_MINUTES=30 ;;
esac
timeout_threshold=$((AGENT_TIMEOUT_MINUTES * 60 - 60))

gate_file="$ARTIFACT_DIR/gate.json"
admitted=""
reason=""
pr_number="${PR_NUMBER:-}"
head_sha=""
used="0"
limit="$LIMIT"

if [ -s "$gate_file" ]; then
  admitted="$(jq -r '.admitted // empty' "$gate_file")"
  reason="$(jq -r '.reason // empty' "$gate_file")"
  pr_number="$(jq -r '.prNumber // empty' "$gate_file")"
  head_sha="$(jq -r '.headSha // empty' "$gate_file")"
  used="$(jq -r '.used // "0"' "$gate_file")"
  limit="$(jq -r --arg fallback "$LIMIT" '.limit // $fallback' "$gate_file")"
fi

if [ -z "$pr_number" ] && [ -n "$DISPLAY_TITLE" ]; then
  pr_number="$(printf '%s' "$DISPLAY_TITLE" | sed -nE 's/.*PR #([0-9]+).*/\1/p')"
fi

skip() {
  printf 'Finalizer skipped: %s\n' "$1"
  exit 0
}

# Only abnormal runs of admitted requests belong to the finalizer. A denied
# gate is published by the in-workflow summary, and a successful agent response
# is posted by the agent itself.
if [ -s "$gate_file" ] && [ "$admitted" = "false" ]; then
  skip "gate denied this request (reason=${reason:-unknown}); the workflow summary owns it"
fi

if [ "$RUN_CONCLUSION" = "success" ]; then
  skip "workflow completed successfully; the agent response is authoritative"
fi

[ -n "$pr_number" ] || skip "could not resolve the pull request number"

marker="<!-- opencode-review-request:run=$RUN_ID attempt=$RUN_ATTEMPT -->"
existing_comments="$(gh pr view "$pr_number" --repo "$REPO" --json comments \
  --jq '.comments[].body' 2>/dev/null || true)"
if printf '%s\n' "$existing_comments" | grep -Fq -- "$marker"; then
  skip "a result for this run attempt was already published"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
jobs_path="${JOBS_PATH:-$tmp_dir/jobs.json}"
jobs_available=true

if [ -z "${JOBS_PATH:-}" ]; then
  if ! gh api "repos/$REPO/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT/jobs?per_page=100" > "$jobs_path"; then
    jobs_available=false
  fi
fi

classify_reason() {
  local job_conclusion agent_step_conclusion failed_steps job_duration

  if [ "$RUN_CONCLUSION" = "timed_out" ]; then
    printf 'timeout\n'
    return 0
  fi

  job_conclusion="$(jq -r --arg name "$AGENT_JOB_NAME" \
    '[.jobs[] | select(.name == $name)][0].conclusion // empty' "$jobs_path")"
  agent_step_conclusion="$(jq -r --arg job "$AGENT_JOB_NAME" --arg step "$AGENT_STEP_NAME" \
    '[.jobs[] | select(.name == $job)][0].steps // [] | map(select(.name == $step))[0].conclusion // empty' \
    "$jobs_path")"
  job_duration="$(jq -r --arg name "$AGENT_JOB_NAME" '
    [.jobs[] | select(.name == $name)][0]
    | if (.started_at // empty) != "" and (.completed_at // empty) != "" then
        ((.completed_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) -
         (.started_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601))
      else 0 end' "$jobs_path" 2>/dev/null || printf '0')"
  if ! [[ "$job_duration" =~ ^[0-9]+$ ]]; then
    job_duration=0
  fi

  case "$job_conclusion" in
    timed_out)
      printf 'timeout\n'
      return 0
      ;;
    success)
      printf 'success\n'
      return 0
      ;;
    cancelled)
      # A job that reaches timeout-minutes is cancelled with the running step
      # marked as cancelled. A manual cancellation is usually much shorter.
      if [ "$job_duration" -ge "$timeout_threshold" ]; then
        printf 'timeout\n'
      else
        printf 'cancelled\n'
      fi
      return 0
      ;;
    failure)
      ;;
    *)
      if [ "$RUN_CONCLUSION" = "cancelled" ]; then
        printf 'cancelled\n'
      else
        printf 'infra\n'
      fi
      return 0
      ;;
  esac

  if [ "$job_duration" -ge "$timeout_threshold" ]; then
    printf 'timeout\n'
    return 0
  fi

  if [ "$agent_step_conclusion" = "failure" ]; then
    printf 'agent_failed\n'
    return 0
  fi

  if [ "$agent_step_conclusion" = "cancelled" ]; then
    printf 'timeout\n'
    return 0
  fi

  failed_steps="$(jq -r --arg job "$AGENT_JOB_NAME" --arg step "$AGENT_STEP_NAME" '
    [.jobs[] | select(.name == $job)][0].steps[]?
    | select(.conclusion == "failure")
    | .name' "$jobs_path" 2>/dev/null || true)"

  if printf '%s\n' "$failed_steps" | grep -Fxq -- "$AGENT_STEP_NAME"; then
    printf 'agent_failed\n'
  else
    printf 'infra\n'
  fi
}

if [ "$jobs_available" = "true" ] && reason="$(classify_reason 2>/dev/null)"; then
  :
else
  reason=infra
fi

if [ "$reason" = "success" ]; then
  skip "agent job succeeded; the agent response is authoritative"
fi

if [ -z "$head_sha" ]; then
  head_sha="$(gh pr view "$pr_number" --repo "$REPO" --json headRefOid \
    --jq .headRefOid 2>/dev/null || true)"
fi
head_sha="${head_sha:-unknown}"

REASON="$reason" \
HEAD_SHA="$head_sha" \
RUN_URL="$RUN_URL" \
REVIEW_PATH="" \
USED="$used" \
LIMIT="$limit" \
RUN_ID="$RUN_ID" \
RUN_ATTEMPT="$RUN_ATTEMPT" \
OUTPUT_PATH="$OUTPUT_PATH" \
  bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/publish-result.sh"

gh pr comment "$pr_number" --repo "$REPO" --body-file "$OUTPUT_PATH"
printf 'Finalizer published %s for PR #%s (head=%s, run=%s)\n' \
  "$reason" "$pr_number" "$head_sha" "$RUN_ID"
