import userEvent from '@testing-library/user-event'
import { render, screen } from '@testing-library/vue'

import App from '@/App.vue'
import router from '@/router'

const THEME_STORAGE_KEY = 'call-schedule-theme'

describe('переключатель темы в шапке', () => {
  beforeEach(async () => {
    localStorage.clear()
    document.documentElement.classList.remove('dark')
    document.documentElement.style.colorScheme = ''
    await router.push('/')
    await router.isReady()
  })

  afterEach(() => {
    localStorage.clear()
    document.documentElement.classList.remove('dark')
    document.documentElement.style.colorScheme = ''
  })

  it('доступен по Tab, объявляет имя и состояние, переключает тему Enter и Space', async () => {
    const user = userEvent.setup()
    const { unmount } = render(App, { global: { plugins: [router] } })

    const toggle = screen.getByRole('button', { name: 'Включить тёмную тему' })
    expect(toggle.tagName).toBe('BUTTON')
    expect(toggle.getAttribute('tabindex')).not.toBe('-1')
    expect(toggle.getAttribute('aria-pressed')).toBe('false')

    const tabStops = [
      screen.getByRole('link', { name: 'Запись на звонок — на главную' }),
      screen.getByRole('link', { name: 'Записаться' }),
      screen.getByRole('link', { name: 'Админка' }),
      toggle,
    ]

    for (const tabStop of tabStops) {
      await user.tab()
      expect(document.activeElement).toBe(tabStop)
    }

    await user.keyboard('{Enter}')

    expect(document.documentElement.classList.contains('dark')).toBe(true)
    expect(document.documentElement.style.colorScheme).toBe('dark')
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe('dark')
    expect(screen.getByRole('button', { name: 'Включить светлую тему' })).toBe(toggle)
    expect(toggle.getAttribute('aria-pressed')).toBe('true')
    expect(document.activeElement).toBe(toggle)

    await user.keyboard(' ')

    expect(document.documentElement.classList.contains('dark')).toBe(false)
    expect(document.documentElement.style.colorScheme).toBe('light')
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe('light')
    expect(screen.getByRole('button', { name: 'Включить тёмную тему' })).toBe(toggle)
    expect(toggle.getAttribute('aria-pressed')).toBe('false')
    expect(document.activeElement).toBe(toggle)

    unmount()
  })
})
