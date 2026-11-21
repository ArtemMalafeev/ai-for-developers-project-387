#!/usr/bin/env bash
set -euo pipefail

: "${REPO:?REPO is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

MAX_REQUESTS="${MAX_REQUESTS:-3}"
EVENT_NAME="${GITHUB_EVENT_NAME:-unknown}"
RUN_ID="${GITHUB_RUN_ID:-local}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
REQUEST_ID="${RUN_ID}-${RUN_ATTEMPT}"
OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"
MARKER='<!-- opencode-review-budget'

emit() {
  printf '%s=%s\n' "$1" "$2" >> "$OUTPUT"
}

pr_json="$(gh pr view "$PR_NUMBER" --repo "$REPO" \
  --json number,headRefOid,isCrossRepository,headRepository,author,authorAssociation,isDraft,url)"
head_sha="$(printf '%s' "$pr_json" | jq -r '.headRefOid // empty')"
emit "head_sha" "$head_sha"

if [ -z "$head_sha" ]; then
  emit "admitted" "false"
  emit "reason" "untrusted"
  emit "used" "0"
  printf 'Не удалось определить head SHA PR #%s.\n' "$PR_NUMBER"
  exit 0
fi

is_cross_repository="$(printf '%s' "$pr_json" | jq -r '.isCrossRepository')"
head_repository="$(printf '%s' "$pr_json" | jq -r '.headRepository.nameWithOwner // empty')"
author_login="$(printf '%s' "$pr_json" | jq -r '.author.login // empty')"
author_association="$(printf '%s' "$pr_json" | jq -r '.authorAssociation // empty')"

trusted_author=false
case "$author_association" in
  OWNER|MEMBER|COLLABORATOR) trusted_author=true ;;
esac
if [ "$author_login" = "opencode-agent[bot]" ]; then
  trusted_author=true
fi

if [ "$is_cross_repository" != "false" ] || [ "$head_repository" != "$REPO" ]; then
  emit "admitted" "false"
  emit "reason" "untrusted"
  emit "used" "0"
  printf 'PR #%s пришёл не из этого репозитория.\n' "$PR_NUMBER"
  exit 0
fi

if [ "$trusted_author" != "true" ]; then
  emit "admitted" "false"
  emit "reason" "untrusted"
  emit "used" "0"
  printf 'Автор PR #%s не входит в доверенный круг.\n' "$PR_NUMBER"
  exit 0
fi

comments_json="$(gh api --paginate "repos/$REPO/issues/$PR_NUMBER/comments?per_page=100" | jq -s 'add // []')"
comment_id="$(printf '%s' "$comments_json" | jq -r --arg marker "$MARKER" \
  '[.[] | select((.body // "") | contains($marker))][0].id // empty')"

count=0
requests='[]'
if [ -n "$comment_id" ]; then
  comment_body="$(printf '%s' "$comments_json" | jq -r --argjson id "$comment_id" \
    '.[] | select(.id == $id) | .body')"
  payload="$(printf '%s\n' "$comment_body" | sed -n '/<!-- opencode-review-budget/,/-->/p' | sed '1d;$d')"
  if [ -n "$payload" ]; then
    count="$(printf '%s' "$payload" | jq -r '.count // 0' 2>/dev/null || printf '0')"
    requests="$(printf '%s' "$payload" | jq -c '.requests // []' 2>/dev/null || printf '[]')"
  fi
fi

case "$count" in
  ''|*[!0-9]*) count=0 ;;
esac

if [ "$count" -ge "$MAX_REQUESTS" ]; then
  emit "admitted" "false"
  emit "reason" "limit_exhausted"
  emit "used" "$count"
  printf 'Лимит запросов /oc для PR #%s исчерпан: %s из %s.\n' "$PR_NUMBER" "$count" "$MAX_REQUESTS"
  exit 0
fi

new_count=$((count + 1))
new_requests="$(jq -c \
  --arg id "$REQUEST_ID" \
  --arg event "$EVENT_NAME" \
  --arg at "$(date -u +%FT%TZ)" \
  '. + [{id: $id, event: $event, createdAt: $at}] | .[-50:]' <<< "$requests")"
new_payload="$(jq -cn \
  --argjson limit "$MAX_REQUESTS" \
  --argjson count "$new_count" \
  --argjson requests "$new_requests" \
  '{schema: 1, limit: $limit, count: $count, requests: $requests}')"
new_body="$(printf '%s\n%s\n%s\n\nАвторевью: израсходовано %s из %s запросов.\n' \
  "$MARKER" "$new_payload" '-->' "$new_count" "$MAX_REQUESTS")"

if [ -n "$comment_id" ]; then
  gh api --method PATCH "repos/$REPO/issues/comments/$comment_id" -f body="$new_body" >/dev/null
else
  gh api --method POST "repos/$REPO/issues/$PR_NUMBER/comments" -f body="$new_body" >/dev/null
fi

emit "admitted" "true"
emit "reason" "admitted"
emit "used" "$new_count"
printf 'Запрос /oc для PR #%s допущен: %s из %s.\n' "$PR_NUMBER" "$new_count" "$MAX_REQUESTS"
