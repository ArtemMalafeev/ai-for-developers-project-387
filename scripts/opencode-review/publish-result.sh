#!/usr/bin/env bash
set -euo pipefail

: "${REASON:?REASON is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
: "${RUN_URL:?RUN_URL is required}"
: "${OUTPUT_PATH:?OUTPUT_PATH is required}"

REVIEW_PATH="${REVIEW_PATH:-}"
BROWSER_RESULT="${BROWSER_RESULT:-}"
USED="${USED:-}"
LIMIT="${LIMIT:-3}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

{
  printf '<!-- opencode-review-result -->\n'
  printf '## Автоматическое ревью OpenCode\n\n'
  printf "Проверенный head: \`%s\`\n\n" "$HEAD_SHA"
  printf "Итог: \`%s\`\n\n" "$REASON"

  case "$REASON" in
    success)
      if [ -n "$REVIEW_PATH" ] && [ -s "$REVIEW_PATH" ]; then
        cat "$REVIEW_PATH"
      else
        printf 'Подтверждённых дефектов не найдено: модель не вернула дополнительный текст.\n'
      fi
      ;;
    limit_exhausted)
      printf "Лимит запросов \`/oc\` для этого PR исчерпан: \`%s\` из \`%s\`. Модель не вызывалась.\n" "${USED:-3}" "$LIMIT"
      ;;
    untrusted)
      printf "PR пропущен: он должен быть создан из этого репозитория доверенным автором или ботом \`opencode-agent[bot]\`. Модель не вызывалась.\n"
      ;;
    timeout)
      printf 'Ревьюер не уложился в отведённое время. Запуск модели остановлен, частичный отчёт не публикуется.\n'
      ;;
    infra)
      printf 'Инфраструктурная ошибка: не удалось подготовить контекст, установить OpenCode CLI или запустить ревьюера. Отчёт модели отсутствует.\n'
      ;;
    agent_failed)
      printf 'Модель завершилась с ошибкой или вернула пустой отчёт. Подтверждённых замечаний публиковать нельзя.\n'
      ;;
    cancelled)
      printf 'Запуск отменён или превысил тайм-аут. Модель не публикует частичный отчёт, попытка уже учтена в бюджете.\n'
      ;;
    stale)
      printf 'Head PR изменился во время ревью. Отчёт относится к указанному SHA и может быть устаревшим.\n'
      ;;
    *)
      printf "Запуск завершился без отчёта. Причина: \`%s\`.\n" "$REASON"
      ;;
  esac

  if [ -n "$BROWSER_RESULT" ]; then
    printf "\nНезависимая браузерная проверка: \`%s\`. Trace, HTML-отчёт и manifest.json с фактическим git rev-parse HEAD приложены к прогону.\n" "$BROWSER_RESULT"
  fi

  printf '\n---\n\n'
  printf 'Логи и артефакты: %s\n' "$RUN_URL"
} > "$OUTPUT_PATH"

test -s "$OUTPUT_PATH"
