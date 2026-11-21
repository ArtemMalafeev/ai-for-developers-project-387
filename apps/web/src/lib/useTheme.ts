import { readonly, ref } from 'vue'

export const THEME_STORAGE_KEY = 'call-schedule-theme'

export type Theme = 'light' | 'dark'

const isDark = ref(false)
let initialized = false

const root = () => document.documentElement

const removeStoredTheme = () => {
  try {
    localStorage.removeItem(THEME_STORAGE_KEY)
  } catch {
    // Storage can be unavailable in restricted browser contexts.
  }
}

const readStoredTheme = (): Theme => {
  try {
    const stored = localStorage.getItem(THEME_STORAGE_KEY)
    if (stored === 'light' || stored === 'dark') return stored
    if (stored !== null) removeStoredTheme()
  } catch {
    // Fall back to the default light theme.
  }
  return 'light'
}

const applyTheme = (theme: Theme) => {
  isDark.value = theme === 'dark'
  root().classList.toggle('dark', isDark.value)
  root().style.colorScheme = theme
}

const persistTheme = (theme: Theme) => {
  try {
    localStorage.setItem(THEME_STORAGE_KEY, theme)
  } catch {
    // Keep the selected theme for the current session.
  }
}

const handleStorage = (event: StorageEvent) => {
  if (event.key !== THEME_STORAGE_KEY && event.key !== null) return
  if (event.key === null) {
    applyTheme('light')
    return
  }
  if (event.newValue === 'light' || event.newValue === 'dark') {
    applyTheme(event.newValue)
    return
  }
  applyTheme('light')
  removeStoredTheme()
}

const initialize = () => {
  if (initialized) return
  initialized = true
  applyTheme(readStoredTheme())
  window.addEventListener('storage', handleStorage)
}

export const useTheme = () => {
  initialize()

  const toggle = () => {
    const next: Theme = isDark.value ? 'light' : 'dark'
    applyTheme(next)
    persistTheme(next)
  }

  return { isDark: readonly(isDark), toggle }
}
