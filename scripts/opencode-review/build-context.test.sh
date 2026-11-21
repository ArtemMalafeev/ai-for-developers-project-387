#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "pr view")
    cat "$FAKE_GH_ROOT/pr.json"
    ;;
  "pr diff")
    printf 'diff --git a/file b/file\n+change\n'
    ;;
  "pr checks"|"run list")
    printf '[]\n'
    ;;
  "issue view")
    case "$3" in
      25|27) cat "$FAKE_GH_ROOT/issue-$3.json" ;;
      *) exit 1 ;;
    esac
    ;;
  *)
    printf 'unexpected gh command: %s\n' "$*" >&2
    exit 1
    ;;
esac
FAKE_GH
chmod +x "$TMP/bin/gh"

cat > "$TMP/pr.json" <<'PR_JSON'
{
  "number": 43,
  "body": "Closes #27. Спецификация #25: https://example.test/issues/25#issuecomment-111. Согласование: https://example.test/issues/25#issuecomment-222. См. #30.",
  "closingIssuesReferences": [{"number": 27}],
  "comments": []
}
PR_JSON

cat > "$TMP/issue-25.json" <<'ISSUE_25'
{
  "number": 25,
  "title": "Спецификация",
  "body": "Исходное обращение",
  "comments": [
    {"url": "https://example.test/issues/25#issuecomment-111", "body": "Согласованная спецификация"},
    {"url": "https://example.test/issues/25#issuecomment-222", "body": "Подтверждение человека"},
    {"url": "https://example.test/issues/25#issuecomment-333", "body": "Длинное обсуждение без ссылки из PR"}
  ]
}
ISSUE_25

cat > "$TMP/issue-27.json" <<'ISSUE_27'
{
  "number": 27,
  "title": "Тикет",
  "body": "Критерии задачи",
  "comments": [{"url": "https://example.test/issues/27#issuecomment-444", "body": "Нерелевантный ответ"}]
}
ISSUE_27

PATH="$TMP/bin:$PATH" \
FAKE_GH_ROOT="$TMP" \
REPO=owner/repo \
PR_NUMBER=43 \
HEAD_SHA=0123456789abcdef0123456789abcdef01234567 \
GH_TOKEN=dummy \
OUTPUT_DIR="$TMP/context" \
bash "$SCRIPT_DIR/build-context.sh" > "$TMP/stdout" 2> "$TMP/stderr"

issues="$TMP/context/issues.json"
review="$TMP/context/review-input.md"
[ "$(jq -r 'length' "$issues")" = "3" ]
[ "$(jq -r '[.[] | select(.number == 25) | .comments[]] | length' "$issues")" = "2" ]
[ "$(jq -r '[.[] | select(.number == 27) | .comments[]] | length' "$issues")" = "0" ]
[ "$(jq -r '[.[] | select(.number == 30 and .error)] | length' "$issues")" = "1" ]
grep -Fq 'Согласованная спецификация' "$review"
grep -Fq 'Подтверждение человека' "$review"
grep -Fq 'Критерии задачи' "$review"
if grep -Fq 'Длинное обсуждение без ссылки из PR' "$review"; then
  printf 'Unreferenced discussion leaked into review context\n' >&2
  exit 1
fi
printf 'Review context includes linked specification, approval and ticket\n'
