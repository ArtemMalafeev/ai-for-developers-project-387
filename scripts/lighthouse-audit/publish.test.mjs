import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { chmod, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const publisher = fileURLToPath(new URL('./publish.mjs', import.meta.url))

test('publisher creates one training issue, reuses it, and journals a clean run', async (t) => {
  const workspace = await mkdtemp(join(tmpdir(), 'lighthouse-audit-test-'))
  t.after(() => rm(workspace, { recursive: true, force: true }))
  const reportDir = join(workspace, '.lighthouseci')
  const fakeBin = join(workspace, 'bin')
  await mkdir(reportDir)
  await mkdir(fakeBin)

  const ghPath = join(fakeBin, 'gh')
  const issuesPath = join(workspace, 'issues.json')
  const callsPath = join(workspace, 'calls.txt')
  await writeFile(
    ghPath,
    `#!/bin/sh
printf '%s\\n' "$*" >> "$MOCK_CALLS"
if [ "$1" = issue ] && [ "$2" = list ]; then
  cat "$MOCK_ISSUES"
elif [ "$1" = issue ] && [ "$2" = create ]; then
  printf '%s\\n' 'https://github.com/example/repo/issues/123'
elif [ "$1" = issue ] && [ "$2" = comment ]; then
  printf '%s\\n' 'https://github.com/example/repo/issues/51#issuecomment-1'
else
  exit 1
fi
`,
  )
  await chmod(ghPath, 0o755)
  await writeFile(issuesPath, '[]')
  await writeFile(callsPath, '')
  await writeFile(join(reportDir, 'training-finding.md'), 'УЧЕБНЫЙ ОТЧЁТ')
  await writeFile(
    join(reportDir, 'analysis.json'),
    JSON.stringify({
      mode: 'training',
      realReportSummary: 'Главная и /booking проверены; подтверждённых находок нет.',
      finding: {
        auditKey: 'training:booking:demo-lcp-image',
        page: '/booking',
        title: 'пример крупного изображения',
        problem: 'Условное изображение замедляет LCP.',
        action: 'Сжать условное изображение и повторить замер.',
        evidence: 'Учебный LCP 5,2 с; данные вымышлены.',
        newEvidence: false,
      },
    }),
  )

  const env = {
    ...process.env,
    PATH: `${fakeBin}:${process.env.PATH}`,
    MOCK_ISSUES: issuesPath,
    MOCK_CALLS: callsPath,
    GITHUB_REPOSITORY: 'example/repo',
    GITHUB_RUN_ID: '42',
    APP_URL: 'https://example.test',
    AUDIT_MODE: 'training',
    REPORT_ARTIFACT_URL: 'https://github.com/example/repo/actions/runs/42/artifacts/1',
  }
  const first = spawnSync(process.execPath, [publisher], { cwd: workspace, env, encoding: 'utf8' })
  assert.equal(first.status, 0, first.stderr)
  assert.match(await readFile(callsPath, 'utf8'), /issue create/)
  const body = await readFile(join(reportDir, 'finding-issue.md'), 'utf8')
  assert.match(body, /УЧЕБНАЯ НАХОДКА/)
  assert.match(body, /Audit key: training:booking:demo-lcp-image/)
  assert.match(body, /actions\/runs\/42/)
  assert.match(body, /actions\/runs\/42\/artifacts\/1/)

  await writeFile(
    issuesPath,
    JSON.stringify([
      {
        number: 123,
        title: '[Учебный Lighthouse] пример крупного изображения',
        body,
        url: 'https://github.com/example/repo/issues/123',
      },
    ]),
  )
  await writeFile(callsPath, '')
  const second = spawnSync(process.execPath, [publisher], { cwd: workspace, env, encoding: 'utf8' })
  assert.equal(second.status, 0, second.stderr)
  const secondCalls = await readFile(callsPath, 'utf8')
  assert.match(secondCalls, /issue list/)
  assert.doesNotMatch(secondCalls, /issue create|issue comment/)
  assert.match(await readFile(join(reportDir, 'audit-result.md'), 'utf8'), /issue #123/)

  await writeFile(
    join(reportDir, 'analysis.json'),
    JSON.stringify({
      mode: 'live',
      realReportSummary: 'Главная и /booking проверены; подтверждённых находок нет.',
      finding: null,
    }),
  )
  await writeFile(callsPath, '')
  const clean = spawnSync(process.execPath, [publisher], {
    cwd: workspace,
    env: { ...env, AUDIT_MODE: 'live' },
    encoding: 'utf8',
  })
  assert.equal(clean.status, 0, clean.stderr)
  assert.match(await readFile(callsPath, 'utf8'), /issue comment 51/)
  assert.match(await readFile(join(reportDir, 'journal-comment.md'), 'utf8'), /actions\/runs\/42\/artifacts\/1/)

  const sameProblem = {
    number: 48,
    title: 'Исправить контраст на странице записи',
    body: 'Та же проблема без ключа аудита.',
    url: 'https://github.com/example/repo/issues/48',
    comments: [],
  }
  const realFinding = {
    auditKey: 'real:/booking:color-contrast',
    page: '/booking',
    title: 'недостаточный контраст',
    problem: 'Контраст элемента не проходит проверку.',
    action: 'Исправить цвета элемента.',
    evidence: 'Аудит color-contrast получил score 0.',
    newEvidence: false,
    existingIssueNumber: 48,
  }
  await writeFile(issuesPath, JSON.stringify([sameProblem]))
  await writeFile(
    join(reportDir, 'analysis.json'),
    JSON.stringify({ mode: 'live', realReportSummary: 'Контраст на /booking не прошёл аудит.', finding: realFinding }),
  )
  await writeFile(callsPath, '')
  const linked = spawnSync(process.execPath, [publisher], {
    cwd: workspace,
    env: { ...env, AUDIT_MODE: 'live' },
    encoding: 'utf8',
  })
  assert.equal(linked.status, 0, linked.stderr)
  assert.match(await readFile(callsPath, 'utf8'), /issue comment 48/)
  const association = await readFile(join(reportDir, 'existing-issue-comment.md'), 'utf8')
  assert.match(association, /Audit key: real:\/booking:color-contrast/)

  await writeFile(issuesPath, JSON.stringify([{ ...sameProblem, comments: [{ body: association }] }]))
  await writeFile(callsPath, '')
  const reused = spawnSync(process.execPath, [publisher], {
    cwd: workspace,
    env: { ...env, AUDIT_MODE: 'live' },
    encoding: 'utf8',
  })
  assert.equal(reused.status, 0, reused.stderr)
  assert.doesNotMatch(await readFile(callsPath, 'utf8'), /issue create|issue comment/)
})
