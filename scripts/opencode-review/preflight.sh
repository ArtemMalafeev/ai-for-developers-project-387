#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Agent preflight failed: %s\n' "$1" >&2
  exit 1
}

[ "${GATE_ADMITTED:-}" = "true" ] || fail "gate did not admit this request"
[ -n "${HEAD_SHA:-}" ] || fail "gate did not provide a head SHA"
[ -n "${OPENCODE_API_KEY:-}" ] || fail "secret OPENCODE_API_KEY is missing or empty"

for command in curl git jq; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is missing: $command"
done

printf 'Agent preflight passed for head %s\n' "$HEAD_SHA"
