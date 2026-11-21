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
