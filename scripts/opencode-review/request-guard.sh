#!/usr/bin/env bash
set -euo pipefail

: "${REPO:?REPO is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

MAX_REQUESTS="${MAX_REQUESTS:-3}"
EVENT_NAME="${GITHUB_EVENT_NAME:-unknown}"
RUN_ID="${GITHUB_RUN_ID:-local}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

WORKFLOW_FILE="${WORKFLOW_FILE:-}"
if [ -z "$WORKFLOW_FILE" ] && [ -n "${GITHUB_WORKFLOW_REF:-}" ]; then
  WORKFLOW_FILE="${GITHUB_WORKFLOW_REF%%@*}"
  WORKFLOW_FILE="${WORKFLOW_FILE##*/}"
fi
WORKFLOW_FILE="${WORKFLOW_FILE:-opencode-review-comments.yml}"
GATE_JOB_NAME="${GATE_JOB_NAME:-Gate request}"
RUN_TITLE_PREFIX="${RUN_TITLE_PREFIX:-OpenCode request gate PR #$PR_NUMBER }"

case "$MAX_REQUESTS" in
  ''|*[!0-9]*) MAX_REQUESTS=3 ;;
esac
case "$RUN_ATTEMPT" in
  ''|*[!0-9]*) RUN_ATTEMPT=1 ;;
esac

emit() {
  printf '%s=%s\n' "$1" "$2" >> "$OUTPUT"
}

deny() {
  local reason="$1"
  local used="$2"
  emit "admitted" "false"
  emit "reason" "$reason"
  emit "used" "$used"
  case "$reason" in
    limit_exhausted)
      printf 'Лимит запросов /oc для PR #%s исчерпан: %s из %s. Модель не вызывается.\n' \
        "$PR_NUMBER" "$used" "$MAX_REQUESTS"
      ;;
    untrusted)
      printf 'PR #%s не прошёл проверку доверия. Модель не вызывается.\n' "$PR_NUMBER"
      ;;
    *)
      printf 'Проверка бюджета /oc для PR #%s не удалась (%s). Модель не вызывается.\n' \
        "$PR_NUMBER" "$reason"
      ;;
  esac
  exit 0
}

runs_error() {
  printf 'Не удалось прочитать историю Actions для PR #%s: %s\n' "$PR_NUMBER" "$1" >&2
  deny "infra" "0"
}

pr_json="$(gh api "repos/$REPO/pulls/$PR_NUMBER")" \
  || deny "infra" "0"
head_sha="$(printf '%s' "$pr_json" | jq -r '.head.sha // empty')"
emit "head_sha" "$head_sha"

if [ -z "$head_sha" ]; then
  deny "untrusted" "0"
fi

head_repository="$(printf '%s' "$pr_json" | jq -r '.head.repo.full_name // empty')"
head_branch="$(printf '%s' "$pr_json" | jq -r '.head.ref // empty')"
author_login="$(printf '%s' "$pr_json" | jq -r '.user.login // empty')"
author_association="$(printf '%s' "$pr_json" | jq -r '.author_association // empty')"

trusted_author=false
case "$author_association" in
  OWNER|MEMBER|COLLABORATOR) trusted_author=true ;;
esac
if [ "$author_login" = "opencode-agent[bot]" ]; then
  trusted_author=true
fi

if [ "$head_repository" != "$REPO" ]; then
  deny "untrusted" "0"
fi

if [ -z "$head_branch" ]; then
  deny "infra" "0"
fi

if [ "$trusted_author" != "true" ]; then
  deny "untrusted" "0"
fi

if ! runs_raw="$(gh api --paginate \
  "repos/$REPO/actions/workflows/$WORKFLOW_FILE/runs?per_page=100")"; then
  runs_error "список запусков"
fi

if ! runs_json="$(printf '%s' "$runs_raw" | jq -s '[.[].workflow_runs[]]')"; then
  runs_error "разбор списка запусков"
fi

gate_admitted() {
  local run_id="$1"
  local attempt="$2"
  local jobs_json conclusion

  if ! jobs_json="$(gh api \
    "repos/$REPO/actions/runs/$run_id/attempts/$attempt/jobs?per_page=100")"; then
    return 2
  fi
  if ! conclusion="$(printf '%s' "$jobs_json" | jq -r --arg name "$GATE_JOB_NAME" \
    '[.jobs[] | select(.name == $name)][0].conclusion // empty')"; then
    return 2
  fi
  [ "$conclusion" = "success" ]
}

count=0

if [ "$RUN_ID" != "local" ] && [ "$RUN_ATTEMPT" -gt 1 ]; then
  for ((attempt = 1; attempt < RUN_ATTEMPT; attempt++)); do
    rc=0
    gate_admitted "$RUN_ID" "$attempt" || rc=$?
    case "$rc" in
      0) count=$((count + 1)) ;;
      1) ;;
      *) runs_error "задание gate для текущего run_attempt $attempt" ;;
    esac
    if [ "$count" -ge "$MAX_REQUESTS" ]; then
      deny "limit_exhausted" "$count"
    fi
  done
fi

# The first admitted request for PR #43 ran before run-name was quoted in YAML.
# Its title has no PR number, so the normal title filter cannot find it. Count
# its immutable Actions run while this PR is open; fail closed if history is lost.
legacy_run_id=44954978888
if [ "$PR_NUMBER" = "43" ] && [ "$RUN_ID" != "$legacy_run_id" ]; then
  legacy_attempts="$(printf '%s' "$runs_json" | jq -r --argjson id "$legacy_run_id" \
    '[.[] | select(.id == $id)][0].run_attempt // empty')"
  case "$legacy_attempts" in
    ''|*[!0-9]*) runs_error "старый запуск $legacy_run_id отсутствует в истории" ;;
  esac
  for ((attempt = 1; attempt <= legacy_attempts; attempt++)); do
    rc=0
    gate_admitted "$legacy_run_id" "$attempt" || rc=$?
    case "$rc" in
      0) count=$((count + 1)) ;;
      1) [ "$attempt" -ne 1 ] || runs_error "не удалось подтвердить первый допущенный запрос" ;;
      *) runs_error "задание gate для старого запуска $legacy_run_id попытки $attempt" ;;
    esac
    if [ "$count" -ge "$MAX_REQUESTS" ]; then
      deny "limit_exhausted" "$count"
    fi
  done
fi

while IFS=$'\t' read -r run_id run_attempt; do
  [ -n "$run_id" ] || continue
  if [ "$run_id" = "$RUN_ID" ]; then
    continue
  fi
  case "$run_attempt" in
    ''|*[!0-9]*) run_attempt=1 ;;
  esac
  for ((attempt = 1; attempt <= run_attempt; attempt++)); do
    rc=0
    gate_admitted "$run_id" "$attempt" || rc=$?
    case "$rc" in
      0) count=$((count + 1)) ;;
      1) ;;
      *) runs_error "задание gate для run $run_id попытки $attempt" ;;
    esac
    if [ "$count" -ge "$MAX_REQUESTS" ]; then
      deny "limit_exhausted" "$count"
    fi
  done
done < <(printf '%s' "$runs_json" | jq -r \
  --arg prefix "$RUN_TITLE_PREFIX" --arg headBranch "$head_branch" '
  .[]
  | select(.event == "issue_comment" or .event == "pull_request_review_comment")
  | select(
      ((.display_title // "") | startswith($prefix)) or
      (
        .event == "pull_request_review_comment" and
        .head_branch == $headBranch and
        .display_title == "OpenCode request gate PR"
      )
    )
  | [.id, (.run_attempt // 1)]
  | @tsv
')

new_count=$((count + 1))

emit "admitted" "true"
emit "reason" "admitted"
emit "used" "$new_count"
printf 'Запрос /oc для PR #%s допущен: %s из %s (run %s, attempt %s, event %s).\n' \
  "$PR_NUMBER" "$new_count" "$MAX_REQUESTS" "$RUN_ID" "$RUN_ATTEMPT" "$EVENT_NAME"
