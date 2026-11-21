import { expect, type Page } from '@playwright/test'

export const THEME_STORAGE_KEY = 'call-schedule-theme'

export const expectDarkBackgrounds = async (page: Page, selectors: string[]) => {
  const backgrounds = await page.evaluate(
    (targets) =>
      targets
        .map((selector) => document.querySelector(selector))
        .filter((element): element is Element => element !== null)
        .map((element) => getComputedStyle(element).backgroundColor),
    selectors,
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
}
