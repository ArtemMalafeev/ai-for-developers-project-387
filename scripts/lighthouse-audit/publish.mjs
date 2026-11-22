import { execFileSync } from 'node:child_process'
import { readFile, writeFile, access } from 'node:fs/promises'
import { join } from 'node:path'

const reportDir = '.lighthouseci'
const repository = process.env.GITHUB_REPOSITORY
const runId = process.env.GITHUB_RUN_ID
const appUrl = process.env.APP_URL
const expectedMode = process.env.AUDIT_MODE
const artifactUrl = process.env.REPORT_ARTIFACT_URL
const journalIssue = '51'

if (!repository || !runId || !appUrl || !artifactUrl || !['live', 'training'].includes(expectedMode)) {
  throw new Error('Missing GITHUB_REPOSITORY, GITHUB_RUN_ID, APP_URL, REPORT_ARTIFACT_URL or AUDIT_MODE')
}

const runUrl = `https://github.com/${repository}/actions/runs/${runId}`
const artifactName = `lighthouse-audit-${runId}`
const checkedPages = [new URL('/', appUrl).href, new URL('/booking', appUrl).href]
const analysis = JSON.parse(await readFile(join(reportDir, 'analysis.json'), 'utf8'))

function requiredText(value, name) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new Error(`Missing ${name} in analysis.json`)
  }
  return value.trim()
}

function gh(...args) {
  return execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }).trim()
}

const mode = requiredText(analysis.mode, 'mode')
if (mode !== expectedMode) {
  throw new Error(`Analysis mode ${mode} differs from workflow mode ${expectedMode}`)
}

const realReportSummary = requiredText(analysis.realReportSummary, 'realReportSummary')
const finding = analysis.finding
let outcome

if (mode === 'training') {
  await access(join(reportDir, 'training-finding.md'))
  if (!finding || finding.auditKey !== 'training:booking:demo-lcp-image') {
    throw new Error('Training mode requires the prepared training finding and its exact Audit key')
  }
}

if (finding === null) {
  if (mode !== 'live') {
    throw new Error('Training mode requires a finding')
  }
  const comment = [
    '## Lighthouse-аудит: новых находок нет',
    '',
    `Проверены: ${checkedPages.join(', ')}.`,
    '',
    realReportSummary,
    '',
    `Прогон: ${runUrl}`,
    `[Отчёт Lighthouse](${artifactUrl}), артефакт \`${artifactName}\` (30 дней).`,
  ].join('\n')
  const commentPath = join(reportDir, 'journal-comment.md')
  await writeFile(commentPath, `${comment}\n`)
  gh('issue', 'comment', journalIssue, '--repo', repository, '--body-file', commentPath)
  outcome = `Новых находок нет; вывод опубликован в [журнале #${journalIssue}](https://github.com/${repository}/issues/${journalIssue}).`
} else {
  if (typeof finding !== 'object' || Array.isArray(finding)) {
    throw new Error('finding must be null or an object')
  }
  const auditKey = requiredText(finding.auditKey, 'finding.auditKey')
  const page = requiredText(finding.page, 'finding.page')
  const title = requiredText(finding.title, 'finding.title')
  const problem = requiredText(finding.problem, 'finding.problem')
  const action = requiredText(finding.action, 'finding.action')
  const evidence = requiredText(finding.evidence, 'finding.evidence')
  const existingIssueNumber = finding.existingIssueNumber
  if (existingIssueNumber !== undefined && (!Number.isInteger(existingIssueNumber) || existingIssueNumber <= 0)) {
    throw new Error('finding.existingIssueNumber must be a positive issue number')
  }
  if (mode === 'live' && !/^real:\/(?:booking)?:[a-z0-9-]+$/.test(auditKey)) {
    throw new Error('Live Audit key must be real:/:<audit-id> or real:/booking:<audit-id>')
  }
  if (!['/', '/booking'].includes(page)) {
    throw new Error('Finding page must be / or /booking')
  }
  if (mode === 'training' && page !== '/booking') {
    throw new Error('Training finding must refer to /booking')
  }

  const existingIssues = JSON.parse(
    gh('issue', 'list', '--repo', repository, '--state', 'all', '--limit', '1000', '--json', 'number,title,body,url,comments'),
  )
  const marker = `Audit key: ${auditKey}`
  const hasMarker = (body) => body?.split('\n').some((line) => line.trim() === marker)
  const existing = existingIssues.find((issue) =>
    hasMarker(issue.body) || issue.comments?.some((comment) => hasMarker(comment.body)),
  )
  const semanticallySame =
    existingIssueNumber === undefined
      ? undefined
      : existingIssues.find((issue) => issue.number === existingIssueNumber)
  if (existingIssueNumber !== undefined && !semanticallySame) {
    throw new Error(`Existing issue #${existingIssueNumber} was not found`)
  }
  const reportReference = `Прогон: ${runUrl}\n[Отчёт Lighthouse](${artifactUrl}), артефакт \`${artifactName}\` (30 дней).`

  if (existing) {
    if (mode === 'live' && finding.newEvidence === true) {
      const commentPath = join(reportDir, 'existing-issue-comment.md')
      await writeFile(commentPath, `Новые существенные сведения по ${auditKey}:\n\n${evidence}\n\n${reportReference}\n`)
      gh('issue', 'comment', String(existing.number), '--repo', repository, '--body-file', commentPath)
    }
    outcome = `Повтор находки: использован существующий [issue #${existing.number}](${existing.url}); новый issue не создан.`
  } else if (semanticallySame) {
    const commentPath = join(reportDir, 'existing-issue-comment.md')
    await writeFile(
      commentPath,
      `Связь с Lighthouse-аудитом: та же проблема уже описана в этой задаче.\n\n${marker}\n\n${evidence}\n\n${reportReference}\n`,
    )
    gh('issue', 'comment', String(semanticallySame.number), '--repo', repository, '--body-file', commentPath)
    outcome = `Найден существующий [issue #${semanticallySame.number}](${semanticallySame.url}) по той же проблеме; новый issue не создан.`
  } else {
    const banner =
      mode === 'training'
        ? '> **УЧЕБНАЯ НАХОДКА. Не подтверждённый дефект приложения; реализация не запрошена.**\n\n'
        : ''
    const issueBody = [
      `${banner}Приложение: календарь звонков (${appUrl})`,
      `Страница: ${page}`,
      `Audit key: ${auditKey}`,
      '',
      '## Проблема',
      problem,
      '',
      '## Данные отчёта',
      evidence,
      '',
      '## Предлагаемое действие',
      action,
      '',
      reportReference,
      '',
      'Это входящее обращение; решение о реализации принимает человек.',
    ].join('\n')
    const bodyPath = join(reportDir, 'finding-issue.md')
    await writeFile(bodyPath, `${issueBody}\n`)
    const issueTitle = `${mode === 'training' ? '[Учебный Lighthouse]' : '[Lighthouse]'} ${title}`
    const createArgs = ['issue', 'create', '--repo', repository, '--title', issueTitle, '--body-file', bodyPath]
    if (mode === 'training') createArgs.push('--label', 'training')
    const issueUrl = gh(...createArgs)
    outcome = `Создан [issue по находке](${issueUrl}).`
  }
}

const result = [
  '# Результат Lighthouse-аудита',
  '',
  `Режим: ${mode === 'training' ? 'учебная находка + реальный аудит' : 'реальный аудит'}.`,
  `Проверены: ${checkedPages.join(', ')}.`,
  '',
  realReportSummary,
  '',
  outcome,
  `[Прогон GitHub Actions](${runUrl}); [отчёт Lighthouse](${artifactUrl}) (30 дней).`,
].join('\n')

await writeFile(join(reportDir, 'audit-result.md'), `${result}\n`)
console.log(outcome)
