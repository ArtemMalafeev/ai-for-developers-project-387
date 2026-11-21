#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/timeout" <<'FAKE_TIMEOUT'
#!/usr/bin/env bash
shift 3
exec "$@"
FAKE_TIMEOUT

cat > "$TMP/bin/opencode" <<'FAKE_OPENCODE'
#!/usr/bin/env bash
case "$FAKE_OPENCODE_CASE" in
  valid)
    printf '%s\n' '{"type":"text","part":{"text":"Подтверждённых дефектов нет."}}'
    ;;
  no_text)
    printf '%s\n' '{"type":"step_start","part":{}}'
    ;;
  whitespace)
    printf '%s\n' '{"type":"text","part":{"text":"   "}}'
    ;;
  invalid_json)
    printf '%s\n' 'not json'
    ;;
esac
FAKE_OPENCODE
chmod +x "$TMP/bin/timeout" "$TMP/bin/opencode"
printf 'Review this PR\n' > "$TMP/prompt.md"
printf 'Context\n' > "$TMP/context.md"

run_case() {
  local case_name="$1" expected_exit="$2" expected_reason="$3"
  local case_dir="$TMP/$case_name"
  mkdir -p "$case_dir"
  set +e
  PATH="$TMP/bin:$PATH" \
    FAKE_OPENCODE_CASE="$case_name" \
    RESULT_PATH="$case_dir/result.json" \
    REVIEW_PATH="$case_dir/review.md" \
    LOG_PATH="$case_dir/opencode.log" \
    PROMPT_FILE="$TMP/prompt.md" \
    CONTEXT_FILE="$TMP/context.md" \
    HEAD_SHA=0123456789abcdef0123456789abcdef01234567 \
    RUN_URL=https://example.test/actions/runs/1 \
    bash "$SCRIPT_DIR/run-review.sh" > "$case_dir/stdout" 2> "$case_dir/stderr"
  local actual_exit="$?"
  set -e

  [ "$actual_exit" -eq "$expected_exit" ] || {
    printf 'not ok - %s: expected exit %s, got %s\n' "$case_name" "$expected_exit" "$actual_exit" >&2
    exit 1
  }
  [ "$(jq -r .reason "$case_dir/result.json")" = "$expected_reason" ] || {
    printf 'not ok - %s: wrong result reason\n' "$case_name" >&2
    exit 1
  }
  printf 'ok - %s is %s\n' "$case_name" "$expected_reason"
}

run_case valid 0 success
grep -Fq 'Подтверждённых дефектов нет.' "$TMP/valid/review.md"
run_case no_text 1 agent_failed
grep -Fq 'step_start' "$TMP/no_text/opencode.log"
run_case whitespace 1 agent_failed
run_case invalid_json 1 agent_failed

printf 'All OpenCode review output checks passed\n'
