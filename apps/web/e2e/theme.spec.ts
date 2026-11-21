import { expect, test } from '@playwright/test'

declare global {
  interface Window {
    __themeAtDomReady?: Promise<boolean>
  }
}

const THEME_STORAGE_KEY = 'call-schedule-theme'

test('переключает тему на странице записи и сохраняет выбор после перезагрузки', async ({
  page,
}) => {
  await page.goto('/booking')
  await expect(page.getByRole('heading', { name: 'Запись на звонок' })).toBeVisible()

  const html = page.locator('html')
  await expect(html).not.toHaveClass(/dark/)
  const lightBackground = await page.evaluate(() => getComputedStyle(document.body).backgroundColor)

  const toggle = page.getByRole('button', { name: 'Включить тёмную тему' })
  await expect(toggle).toHaveAttribute('aria-pressed', 'false')
  await toggle.click()

  await expect(html).toHaveClass(/dark/)
  await expect(page.getByRole('button', { name: 'Включить светлую тему' })).toHaveAttribute(
    'aria-pressed',
    'true',
  )
  await expect
    .poll(() => page.evaluate((key) => localStorage.getItem(key), THEME_STORAGE_KEY))
    .toBe('dark')
  await expect
    .poll(() => page.evaluate(() => getComputedStyle(document.body).backgroundColor))
    .not.toBe(lightBackground)

  await page.reload()
  await expect(html).toHaveClass(/dark/)
  await expect(page.getByRole('button', { name: 'Включить светлую тему' })).toBeVisible()
  await expect
    .poll(() => page.evaluate((key) => localStorage.getItem(key), THEME_STORAGE_KEY))
    .toBe('dark')

  const reloadedToggle = page.getByRole('button', { name: 'Включить светлую тему' })
  await reloadedToggle.focus()
  await page.keyboard.press('Space')
  await expect(html).not.toHaveClass(/dark/)
  await expect(page.getByRole('button', { name: 'Включить тёмную тему' })).toBeVisible()

  await page.keyboard.press('Enter')
  await expect(html).toHaveClass(/dark/)
  await expect(page.getByRole('button', { name: 'Включить светлую тему' })).toBeVisible()
})

test('невалидное значение темы даёт светлую тему и очищает ключ', async ({ page }) => {
  await page.addInitScript((key) => {
    localStorage.setItem(key, 'auto')
  }, THEME_STORAGE_KEY)

  await page.goto('/booking')
  await expect(page.getByRole('heading', { name: 'Запись на звонок' })).toBeVisible()
  await expect(page.locator('html')).not.toHaveClass(/dark/)
  await expect
    .poll(() => page.evaluate((key) => localStorage.getItem(key), THEME_STORAGE_KEY))
    .toBeNull()
})

test('ошибка localStorage не ломает приложение', async ({ page }) => {
  await page.addInitScript((key) => {
    const storage = Object.getPrototypeOf(window.localStorage) as Storage
    const getItem = storage.getItem
    const setItem = storage.setItem
    Object.defineProperty(storage, 'getItem', {
      configurable: true,
      value(name: string) {
        if (name === key) throw new Error('storage blocked')
        return getItem.call(this, name)
      },
    })
    Object.defineProperty(storage, 'setItem', {
      configurable: true,
      value(name: string, value: string) {
        if (name === key) throw new Error('storage blocked')
        return setItem.call(this, name, value)
      },
    })
  }, THEME_STORAGE_KEY)

  await page.goto('/booking')
  await expect(page.getByRole('heading', { name: 'Запись на звонок' })).toBeVisible()

  const toggle = page.getByRole('button', { name: 'Включить тёмную тему' })
  await toggle.click()
  await expect(page.locator('html')).toHaveClass(/dark/)
  await expect(page.getByRole('button', { name: 'Включить светлую тему' })).toBeVisible()
})

test('сохранённая тёмная тема применяется до готовности документа', async ({ page }) => {
  await page.addInitScript((key) => {
    localStorage.setItem(key, 'dark')
    window.__themeAtDomReady = new Promise((resolve) => {
      document.addEventListener(
        'DOMContentLoaded',
        () => resolve(document.documentElement.classList.contains('dark')),
        { once: true },
      )
    })
  }, THEME_STORAGE_KEY)

  await page.goto('/booking')
  await expect(page.locator('html')).toHaveClass(/dark/)
  expect(await page.evaluate(() => window.__themeAtDomReady)).toBe(true)
  expect(await page.evaluate(() => getComputedStyle(document.documentElement).colorScheme)).toBe(
    'dark',
  )
})

test('админка целиком работает в тёмной теме', async ({ page, request }) => {
  const meetingTypeName = `Тёмная админка ${Date.now()}`
  const createdType = await request.post('/api/owner/meeting-types', {
    data: { name: meetingTypeName, durationMinutes: 30 },
  })
  expect(createdType.ok()).toBe(true)
  const meetingType = (await createdType.json()) as { id: string }

  const slotsResponse = await request.get(`/api/meeting-types/${meetingType.id}/slots`)
  expect(slotsResponse.ok()).toBe(true)
  const slots = (await slotsResponse.json()) as Array<{ startAt: string }>
  const firstSlot = slots[0]
  if (!firstSlot) throw new Error('Не найдены слоты для проверки админки')

  const bookingResponse = await request.post('/api/bookings', {
    data: {
      meetingTypeId: meetingType.id,
      startAt: firstSlot.startAt,
      guestName: 'Тёмный гость админки',
      guestEmail: 'dark-admin@example.com',
    },
    headers: { 'Idempotency-Key': `e2e-dark-admin-${Date.now()}` },
  })
  expect(bookingResponse.ok()).toBe(true)

  await page.addInitScript((key) => localStorage.setItem(key, 'dark'), THEME_STORAGE_KEY)
  await page.goto('/admin')
  await expect(page.getByRole('heading', { name: 'Рабочая панель' })).toBeVisible()
  await expect(page.getByRole('heading', { name: meetingTypeName })).toBeVisible()
  await expect(page.getByRole('table').getByText('dark-admin@example.com')).toBeVisible()

  const newTypeName = `Тёмный формат ${Date.now()}`
  await page.getByLabel('Название').fill(newTypeName)
  await page.getByLabel('Длительность, минут').fill('45')
  await page.getByRole('button', { name: 'Создать тип встречи' }).click()
  await expect(page.getByRole('heading', { name: newTypeName })).toBeVisible()

  const backgrounds = await page.evaluate(() =>
    ['.site-header', '.page-shell', '.admin-type-item', '.bookings-card', '[data-slot="card"]']
      .map((selector) => document.querySelector(selector))
      .filter((element): element is Element => element !== null)
      .map((element) => getComputedStyle(element).backgroundColor),
  )
  expect(backgrounds.length).toBeGreaterThan(0)
  for (const color of backgrounds) {
    const channels =
      color
        .match(/[\d.]+/g)
        ?.slice(0, 3)
        .map(Number) ?? []
    expect(Math.max(...channels)).toBeLessThan(90)
  }
})
