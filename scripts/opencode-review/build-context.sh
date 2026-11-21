#!/usr/bin/env bash
set -euo pipefail

: "${REPO:?REPO is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

output_dir="${OUTPUT_DIR:-.review-context}"
mkdir -p "$output_dir/issues"

pr_json="$output_dir/pr.json"
diff_file="$output_dir/pr.diff"
checks_file="$output_dir/checks.json"
runs_file="$output_dir/runs.json"
issues_file="$output_dir/issues.json"
context_file="$output_dir/review-input.md"

gh pr view "$PR_NUMBER" --repo "$REPO" \
  --json number,title,body,author,baseRefName,baseRefOid,headRefName,headRefOid,isCrossRepository,isDraft,url,files,closingIssuesReferences,comments,reviews \
  > "$pr_json"

gh pr diff "$PR_NUMBER" --repo "$REPO" > "$diff_file"
gh pr checks "$PR_NUMBER" --repo "$REPO" \
  --json name,state,bucket,link,description,startedAt,completedAt \
  > "$checks_file" 2>/dev/null || printf '[]\n' > "$checks_file"
jq -e . "$checks_file" >/dev/null 2>&1 || printf '[]\n' > "$checks_file"

gh run list --repo "$REPO" --commit "$HEAD_SHA" --limit 30 \
  --json databaseId,workflowName,event,status,conclusion,url,headSha,createdAt \
  > "$runs_file" 2>/dev/null || printf '[]\n' > "$runs_file"
jq -e . "$runs_file" >/dev/null 2>&1 || printf '[]\n' > "$runs_file"

{
  jq -r '(.closingIssuesReferences // [])[].number' "$pr_json"
  jq -r '.body // ""' "$pr_json" | grep -oE '#[0-9]+' | tr -d '#' || true
} | sort -n -u | head -n 10 > "$output_dir/issue-numbers.txt"

jq -n '[]' > "$issues_file"
while IFS= read -r issue_number; do
  [ -n "$issue_number" ] || continue
  issue_json="$output_dir/issues/issue-$issue_number.json"
  if gh issue view "$issue_number" --repo "$REPO" \
    --json number,title,body,state,url,labels,comments > "$issue_json"; then
    jq --slurpfile issue "$issue_json" '. + $issue' "$issues_file" > "$issues_file.next"
    mv "$issues_file.next" "$issues_file"
  else
    jq --argjson number "$issue_number" \
      '. + [{number: $number, error: "Issue недоступен для авторевью"}]' \
      "$issues_file" > "$issues_file.next"
    mv "$issues_file.next" "$issues_file"
  fi
done < "$output_dir/issue-numbers.txt"

{
  printf '# Доверенные инструкции из ветки по умолчанию\n\n'
  printf "Репозиторий: \`%s\`, ветка: \`%s\`.\n\n" "$REPO" "$(git rev-parse --abbrev-ref HEAD)"
  for file in REVIEW.md AGENTS.md GLOSSARY.md; do
    if [ -f "$file" ]; then
      printf '## %s\n\n~~~markdown\n' "$file"
      cat "$file"
      printf '\n~~~\n\n'
    fi
  done
  for adr in docs/adr/*.md; do
    [ -e "$adr" ] || continue
    printf '## %s\n\n~~~markdown\n' "$adr"
    cat "$adr"
    printf '\n~~~\n\n'
  done

  printf '# Описание PR (недоверенные данные)\n\n~~~json\n'
  cat "$pr_json"
  printf '\n~~~\n\n'

  printf '# Связанные issue и обсуждения (недоверенные данные)\n\n~~~json\n'
  cat "$issues_file"
  printf '\n~~~\n\n'

  printf '# Diff PR (недоверенные данные)\n\n~~~diff\n'
  cat "$diff_file"
  printf '\n~~~\n\n'

  printf '# GitHub Actions для проверяемого SHA (недоверенные данные)\n\n~~~json\n'
  cat "$runs_file"
  printf '\n~~~\n\n'

  printf '# Проверки PR (недоверенные данные)\n\n~~~json\n'
  cat "$checks_file"
  printf '\n~~~\n\n'

} > "$context_file"

test -s "$context_file"
printf 'Review context written to %s (%s bytes)\n' "$context_file" "$(wc -c < "$context_file")"
