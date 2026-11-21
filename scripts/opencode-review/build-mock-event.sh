#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_EVENT_PATH:?GITHUB_EVENT_PATH is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request_review_comment" ]; then
  exit 0
fi

repo_owner="${GITHUB_REPOSITORY_OWNER:-${GITHUB_REPOSITORY%%/*}}"
repo_name="${GITHUB_REPOSITORY#*/}"

context="$(jq -cn \
  --slurpfile event "$GITHUB_EVENT_PATH" \
  --arg owner "$repo_owner" \
  --arg repo "$repo_name" \
  --arg actor "${GITHUB_ACTOR:-}" \
  --arg ref "${GITHUB_REF:-}" \
  --arg sha "${GITHUB_SHA:-}" \
  --arg workflow "${GITHUB_WORKFLOW:-}" \
  --arg job "${GITHUB_JOB:-}" \
  '{
    eventName: "pull_request_review_comment",
    payload: {
      action: "created",
      comment: ($event[0].comment | {
        id,
        body,
        path,
        diff_hunk,
        line,
        original_line,
        position,
        commit_id,
        original_commit_id
      }),
      pull_request: {number: $event[0].pull_request.number},
      issue: {
        number: $event[0].pull_request.number,
        pull_request: {number: $event[0].pull_request.number}
      }
    },
    repo: {owner: $owner, repo: $repo},
    actor: $actor,
    ref: $ref,
    sha: $sha,
    workflow: $workflow,
    job: $job
  }')"

printf 'context=%s\n' "$context" >> "$GITHUB_OUTPUT"
