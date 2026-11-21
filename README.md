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

В репозитории подключён OpenCode GitHub App, а сценарий работы описан в workflow [`.github/workflows/opencode.yml`](.github/workflows/opencode.yml). Агент запускается по событиям `issue_comment` и `pull_request_review_comment` с `types: [created]`.

- **Команды:** `/opencode` и `/oc` в комментарии.
- **Авторы:** только участники с ролью `OWNER`, `MEMBER` или `COLLABORATOR`; комментарии ботов пропускаются.
- **Модель:** `opencode/deepseek-v4.1-flash`.
- **Доступ:** секрет `OPENCODE_API_KEY` и OIDC-токен для OpenCode GitHub App.
- **Публикация:** `share: false` — сессия не публикуется по внешней ссылке.
- **Ограничения:** тайм-аут 30 минут; для одного issue или PR одновременно выполняется только один запуск.

Workflow проверяет команду и роль автора, берёт код из ветки по умолчанию и устанавливает на раннер 27 стабильных скиллов [`mattpocock/skills`](https://github.com/mattpocock/skills) версии 1.3.2. Настройки трекера задач, меток triage и доменных документов агент читает из `docs/agents/`.

Агент отвечает на запрос комментарием в issue или PR, а ход выполнения и логи видны в [GitHub Actions](https://github.com/ArtemMalafeev/ai-for-developers-project-387/actions/workflows/opencode.yml).

## Сценарий использования

1. **Владелец создаёт тип встречи.** На странице `/admin` он указывает название, описание и длительность, например «Совещание», 30 минут.
2. **Гость выбирает время.** На странице `/booking` гость выбирает тип встречи, дату в ближайших 14 днях и свободный слот, затем вводит имя и email.
3. **Приложение подтверждает запись.** Выбранный слот исчезает из списка доступных, а запись появляется в панели владельца.

## О Хекслете

[Хекслет](https://ru.hexlet.io/) — школа программирования с практикой, поддержкой наставников и проектами для портфолио. Этот репозиторий — один из учебных проектов программы.
