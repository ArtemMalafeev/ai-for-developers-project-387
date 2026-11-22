# Календарь звонков

[![hexlet-check](https://github.com/ArtemMalafeev/ai-for-developers-project-387/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/ArtemMalafeev/ai-for-developers-project-387/actions)

Учебный сервис бронирования встреч: владелец создаёт типы встреч, гость выбирает свободный слот и оставляет свои данные, а владелец просматривает предстоящие записи.

Проект выполнен в рамках программы [Хекслета «AI for Developers»](https://ru.hexlet.io/programs/ai-for-developers). Описание исходного задания: [files.hexlet.app/a/2ipc5m](https://files.hexlet.app/a/2ipc5m).

Это продолжение проекта [ai-for-developers-project-386](https://github.com/ArtemMalafeev/ai-for-developers-project-386).

## Стек

- **Клиент:** Vue 3, TypeScript, Vue Router, Vite, Tailwind CSS и shadcn-vue.
- **API:** Fastify 5 и TypeScript.
- **Контракт:** TypeSpec → OpenAPI; по контракту генерируются Fetch SDK для клиента и типы обработчиков Fastify.
- **Проверки:** Oxlint, ESLint, TypeScript, Vitest и Playwright.
- **Пакетный менеджер:** pnpm workspace.

## Возможности

- создание типов встреч с названием, описанием и длительностью от 5 минут с шагом 5 минут;
- просмотр доступных слотов на ближайшие 14 календарных дней;
- запись гостя по имени и email;
- защита бронирования от повторной отправки с помощью `Idempotency-Key`;
- обработка конфликта, если выбранный слот уже занял другой гость;
- список ближайших записей в панели владельца.

В демо используется часовой пояс владельца `Europe/Moscow`. Рабочее расписание по умолчанию — с понедельника по пятницу, с 09:00 до 17:00. Шаг слотов равен длительности выбранного типа встречи.

## Требования

Версии инструментов зафиксированы в [`mise.toml`](mise.toml):

- Node.js `26.13.0`;
- pnpm `12.16.1`;
- hk `2.11.0`.

При использовании [mise](https://mise.jdx.dev/) версии можно установить командой:

```bash
mise install
```

## Установка и локальный запуск

```bash
git clone https://github.com/ArtemMalafeev/ai-for-developers-project-387.git
cd ai-for-developers-project-387
pnpm install
pnpm dev
```

Команда `pnpm dev` запускает клиент и API параллельно.

- Клиент: <http://127.0.0.1:5173>
- Панель владельца: <http://127.0.0.1:5173/admin>
- Страница записи гостя: <http://127.0.0.1:5173/booking>
- API: <http://127.0.0.1:3000>
- Проверка API: <http://127.0.0.1:3000/health>

В режиме разработки Vite проксирует запросы `/api` на Fastify. Переменные окружения для локального запуска не нужны.

## Основные команды

Все команды выполняются из корня репозитория.

```bash
# Линтеры всех workspace-пакетов
pnpm -r lint

# Проверка типов
pnpm -r type-check

# Модульные и компонентные тесты
pnpm --filter apps-api test
pnpm --filter apps-web test:run

# Сборка клиента и API
pnpm --filter apps-web build
pnpm --filter apps-api build

# Сквозная проверка запуска и основного сценария бронирования
node scripts/smoke.mjs

# Полный набор проверок из mise
mise run check
```

`node scripts/smoke.mjs` сам запускает оба dev-сервера. Перед запуском остановите вручную занятые процессы на портах `3000` и `5173`.

## Маршруты интерфейса

| Адрес | Назначение |
| --- | --- |
| `/` | Главная страница и описание сценариев |
| `/booking` | Выбор типа встречи, даты, слота и создание записи |
| `/admin` | Создание типов встреч и просмотр ближайших записей |

Авторизация в учебной версии не подключена: панель владельца доступна по прямой ссылке.

## API

Все прикладные маршруты начинаются с `/api`.

| Метод и путь | Назначение |
| --- | --- |
| `GET /api/meeting-types` | Получить типы встреч, доступные гостю |
| `GET /api/meeting-types/:meetingTypeId/slots` | Получить свободные слоты на 14 дней |
| `POST /api/bookings` | Забронировать слот; требует заголовок `Idempotency-Key` |
| `POST /api/owner/meeting-types` | Создать тип встречи |
| `GET /api/owner/bookings` | Получить предстоящие записи владельца |
| `GET /health` и `GET /api/health` | Проверить состояние сервера |

Источник контракта — [`packages/contracts/src/main.tsp`](packages/contracts/src/main.tsp). После его изменения выполните:

```bash
pnpm contracts:generate
pnpm contracts:check
```

Генерация обновляет [`packages/contracts/openapi/openapi.yaml`](packages/contracts/openapi/openapi.yaml), [`packages/api-client/src/generated/`](packages/api-client/src/generated/) и [`apps/backend/src/generated/`](apps/backend/src/generated/). Сгенерированные файлы не редактируйте вручную.

## Браузерный тест

Playwright проверяет полный сценарий: создание типа встречи, выбор даты и слота, подтверждение записи и её появление в панели владельца. Для первого запуска установите Chromium:

```bash
pnpm install
pnpm --filter apps-web exec playwright install chromium
```

Затем запустите тесты:

```bash
pnpm --filter apps-web test:e2e
pnpm --filter apps-web exec playwright test --headed
pnpm --filter apps-web exec playwright show-report
```

Первый вариант работает без окна браузера, `--headed` показывает действия теста, а `show-report` открывает отчёт последнего запуска. Playwright сам поднимает клиент и API; перед запуском остановите вручную работающие dev-серверы.

## Docker

Сборка выполняется на Node.js 26, затем Fastify раздаёт собранный Vue-клиент и API на одном порту:

```bash
docker build -t calendar-calls .
docker run --rm -p 3000:3000 -e PORT=3000 calendar-calls
```

В production-хостинге сервер слушает `0.0.0.0`. Параметры `PORT` и `HOST` можно передать через переменные окружения; по умолчанию используется порт `3000`. Данные календаря хранятся в памяти и сбрасываются после перезапуска процесса или контейнера.

## Деплой

Проект 387 опубликован как отдельный сервис на Railway:

**Публичная ссылка:** <https://ai-for-developers-project-387-production-776e1189.up.railway.app>

Локальная инструкция для Railway MCP находится в [`docs/agents/mcp-railway.md`](docs/agents/mcp-railway.md). OAuth-сессия и API-токены не хранятся в Git.

## Автоматические проверки Хекслета

Проверки запускаются на каждый коммит workflow [`.github/workflows/hexlet-check.yml`](.github/workflows/hexlet-check.yml). Не удаляйте и не переименовывайте этот файл и репозиторий.

## OpenCode в GitHub

В репозитории подключён OpenCode GitHub App. События комментариев и pull request разделены: `/oc` в обычном issue запускает агента [`.github/workflows/opencode.yml`](.github/workflows/opencode.yml), автоматическое ревью PR запускается отдельным workflow, а `/oc` в комментарии к PR проходит через отдельный workflow с бюджетом запросов.

### Установленные workflow

Авторевью, обработка команд в PR и финализатор находятся в `.github/workflows`. GitHub App не может изменять эту директорию; обновления workflow вносит владелец репозитория обычными правами. Перед изменением проверяйте `mise run actions`, а после публикации — фактические прогоны на PR.

### Команды в issue

- **Команды:** `/opencode` и `/oc` в комментарии к issue.
- **Авторы:** только участники с ролью `OWNER`, `MEMBER` или `COLLABORATOR`; комментарии ботов пропускаются.
- **Модель:** `opencode/deepseek-v4.1-flash`.
- **Доступ:** секрет `OPENCODE_API_KEY` и OIDC-токен для OpenCode GitHub App.
- **Публикация:** `share: false` — сессия не публикуется по внешней ссылке.
- **Ограничения:** тайм-аут 30 минут; для одного issue одновременно выполняется только один запуск.

Агент проверяет команду и роль автора, берёт код из ветки по умолчанию и устанавливает на раннер 27 стабильных скиллов [`mattpocock/skills`](https://github.com/mattpocock/skills) версии 1.3.2. Настройки трекера задач, меток triage и доменных документов агент читает из `docs/agents/`. Ответ и логи видны в [GitHub Actions](https://github.com/ArtemMalafeev/ai-for-developers-project-387/actions/workflows/opencode.yml).

### Авторевью pull request

[`.github/workflows/opencode-review.yml`](.github/workflows/opencode-review.yml) открытые и обновлённые PR проверяет независимый ревьюер через обычный OpenCode CLI.

- **События:** только `pull_request` (`opened`, `synchronize`, `reopened`, `ready_for_review`); комментарии и PR не смешиваются в одном запуске.
- **Допуск:** только PR из веток этого репозитория от `OWNER`, `MEMBER`, `COLLABORATOR` или конкретного бота `opencode-agent[bot]`. Fork и черновики пропускаются. Используется `pull_request`, а не `pull_request_target`, поэтому fork-запуски не получают секреты.
- **Доверенные инструкции:** ревьюер читает `REVIEW.md`, `AGENTS.md`, глоссарий и ADR из ветки по умолчанию. Описание PR, diff, issue и логи передаются как недоверенные данные; инструкции из них не выполняются.
- **Безопасность:** у ревьюера отключены shell, запись файлов, сеть, задачи и скиллы. Он читает только подготовленный `review-input.md`, не получает `GH_TOKEN` и не может изменить код.
- **Публикация:** отчёт публикуется отдельным заданием с правом `pull-requests: write`, только если head PR не изменился. Итог содержит причину, проверенный SHA и ссылку на логи/артефакты.
- **Итоги:** `success`, `timeout`, `infra`, `agent_failed`, `cancelled` и `stale` публикуются отдельно; частичный отчёт при ошибке не выдаётся за ревью.
- **Обновления:** для одного PR отменяется устаревший запуск (`cancel-in-progress: true`), тайм-аут задания 25 минут, запуск модели ограничен 20 минутами.
- **Браузерная проверка:** отдельное задание Playwright проверяет точный `head.sha` и запускает `playwright test --trace on`. Артефакт содержит trace, HTML-отчёт и `manifest.json` с фактическим `git rev-parse HEAD`, ожидаемым SHA и результатом теста.

Критерии ревью для календаря, записи на звонок и ручной тёмной темы #25 находятся в [`REVIEW.md`](REVIEW.md). Шаблон [`.github/pull_request_template.md`](.github/pull_request_template.md) требует ссылки на обращение и согласование, спецификацию и тикеты, команды и результаты проверок, ссылки на CI, проверенный SHA, риск по последствиям ошибки и способ отката.

### Ручные запросы /oc на pull request

[`.github/workflows/opencode-review-comments.yml`](.github/workflows/opencode-review-comments.yml) запросы `/oc` и `/opencode` в `issue_comment` и `pull_request_review_comment` на PR проходят отдельный gate, а затем запускают прежний агент `anomalyco/opencode/github`. Человек может попросить исправить код в общем комментарии или в построчном комментарии к diff.

- **Бюджет:** не более трёх допущенных запусков на один PR. Попытки считаются по истории GitHub Actions (`actions: read`) через явный `run-name` и результат задания `Gate request`, а не по комментарию PR, который токен GitHub App разработчика может переписать.
- **Учёт:** каждый `run_attempt`, включая Re-run, а также отмена и тайм-аут после допуска, расходует попытку. Четвёртый запрос блокируется до вызова модели.
- **Итоги gate:** `limit_exhausted` и `untrusted` публикует summary внутри workflow, при `limit_exhausted` модель не вызывается.
- **Аварийные итоги:** после завершения workflow отдельный trusted [`opencode-review-finalizer.yml`](.github/workflows/opencode-review-finalizer.yml) на `workflow_run` читает задание agent и gate-артефакт с PR/head. Без модели и без `OPENCODE_API_KEY` он публикует `timeout`, `cancelled`, `infra` и `agent_failed` с SHA и ссылкой на запуск. Успешный ответ агента и решения gate он не дублирует: публикация помечается `run_id` и `run_attempt`.
- **Preflight и классификация:** до запуска action проверяются допуск gate, head SHA, наличие `OPENCODE_API_KEY` и базовые команды. Сбой preflight или шагов подготовки до агента (checkout, skills, OIDC, git) даёт `infra`, а падение самого шага агента — `agent_failed`. Тайм-аут задания не превращается в `agent_failed`.
- **Полномочия и секрет:** gate читает PR и Actions без секретов; агент получает `OPENCODE_API_KEY` и OIDC в отдельном задании; итог публикует отдельное задание с правом на комментарии; finalizer не получает секрет модели.
- **Проверки:** `bash scripts/opencode-review/request-guard.test.sh` (`mise run gate`) и `bash scripts/opencode-review/finalizer.test.sh` (`mise run finalizer`).
- **Обход бюджета:** [`.github/workflows/opencode.yml`](.github/workflows/opencode.yml) запускает общий агент только в обычных issue; PR-комментарии принимает workflow с gate.

## Автотриаж новых обращений

Новые issue автоматически проходят предварительный разбор в workflow [`.github/workflows/opencode-triage.yml`](.github/workflows/opencode-triage.yml). Workflow запускается событием `issues` с типом `opened`; у этого события нет комментария с командой, поэтому инструкция агенту находится в `prompt` workflow.

- **Авторы:** только `OWNER`, `MEMBER` и `COLLABORATOR`; обращения ботов и остальных авторов пропускаются.
- **Пропуск готовых тикетов:** если у issue уже есть любая статусная метка из [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md) — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human` или `wontfix`, — повторный разбор не выполняется. Поэтому тикеты, созданные `to-tickets`, не триажатся заново.
- **Результат:** агент оставляет комментарий с пометкой `> *This was generated by AI during triage.*`. Если сведений не хватает, он задаёт конкретные вопросы и ставит `needs-info`; если сведений достаточно — ставит `needs-triage` и даёт краткий разбор. Метку категории (`bug` или `enhancement`) агент добавляет только когда она однозначна.
- **Ограничения:** агент не меняет код, не создаёт спецификацию и никогда не переводит issue в `ready-for-agent`.
- **Права и лимиты:** `contents: read`, `id-token: write` и `issues: write`; тайм-аут 15 минут; для одного issue одновременно выполняется только один запуск (`cancel-in-progress: false`).

## Регулярный Lighthouse-аудит

Workflow [`Lighthouse Audit`](.github/workflows/lighthouse-audit.yml) проверяет опубликованное приложение на главной странице и `/booking`. Адрес берётся из переменной репозитория `APP_URL`, секрет модели — из `OPENCODE_API_KEY`. Запуск запланирован ежедневно в 06:17 по Москве (`17 6 * * *`, `Europe/Moscow`); тот же workflow можно запустить вручную через **Actions → Lighthouse Audit → Run workflow** из ветки `main`. Запуски выполняются последовательно, тайм-аут задания — 30 минут.

Lighthouse сохраняет JSON- и HTML-отчёты в артефакте `lighthouse-audit-<run_id>` соответствующего прогона (срок хранения — 30 дней). Рабочий каталог `.lighthouseci/` игнорируется Git. OpenCode читает отчёты и публикует краткий вывод с указанием проверенной страницы и прямой ссылкой на артефакт: по новой находке — в отдельном issue, при отсутствии новых находок — в [журнале аудита #51](https://github.com/ArtemMalafeev/ai-for-developers-project-387/issues/51). Итог также доступен в сводке прогона и в артефакте `lighthouse-result-<run_id>`. Перед созданием задачи агент сравнивает проблему с существующими issues, а скрипт публикации ищет `Audit key` в их телах и комментариях; реализацию находки решает человек.

Для проверки создания задачи при отсутствии реальных проблем у ручного запуска есть параметр `training_finding`. Он добавляет отдельно обозначенный учебный отчёт; созданный issue получает метку `training` и не считается подтверждённым дефектом приложения. Запуск по расписанию всегда работает только с настоящими Lighthouse-отчётами. Агент использует `GITHUB_TOKEN` с правами `contents: read` и `issues: write`; права на изменение кода и создание PR ему не выдаются.

## Сценарий использования

1. **Владелец создаёт тип встречи.** На странице `/admin` он указывает название, описание и длительность, например «Совещание», 30 минут.
2. **Гость выбирает время.** На странице `/booking` гость выбирает тип встречи, дату в ближайших 14 днях и свободный слот, затем вводит имя и email.
3. **Приложение подтверждает запись.** Выбранный слот исчезает из списка доступных, а запись появляется в панели владельца.

## О Хекслете

[Хекслет](https://ru.hexlet.io/) — школа программирования с практикой, поддержкой наставников и проектами для портфолио. Этот репозиторий — один из учебных проектов программы.
