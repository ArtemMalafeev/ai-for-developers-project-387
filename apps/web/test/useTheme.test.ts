const THEME_STORAGE_KEY = 'call-schedule-theme'

const loadThemeModule = async () => {
  vi.resetModules()
  return import('@/lib/useTheme')
}

const root = () => document.documentElement

describe('useTheme', () => {
  beforeEach(() => {
    localStorage.clear()
    root().classList.remove('dark')
    root().style.colorScheme = ''
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    localStorage.clear()
    root().classList.remove('dark')
    root().style.colorScheme = ''
  })

  it('по умолчанию включает светлую тему', async () => {
    const { useTheme } = await loadThemeModule()
    const { isDark } = useTheme()

    expect(isDark.value).toBe(false)
    expect(root().classList.contains('dark')).toBe(false)
    expect(root().style.colorScheme).toBe('light')
  })

  it('применяет сохранённую тёмную тему', async () => {
    localStorage.setItem(THEME_STORAGE_KEY, 'dark')
    const { useTheme } = await loadThemeModule()
    const { isDark } = useTheme()

    expect(isDark.value).toBe(true)
    expect(root().classList.contains('dark')).toBe(true)
    expect(root().style.colorScheme).toBe('dark')
  })

  it('переключает класс и значение в хранилище в обе стороны', async () => {
    const { useTheme } = await loadThemeModule()
    const { isDark, toggle } = useTheme()

    toggle()
    expect(isDark.value).toBe(true)
    expect(root().classList.contains('dark')).toBe(true)
    expect(root().style.colorScheme).toBe('dark')
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe('dark')

    toggle()
    expect(isDark.value).toBe(false)
    expect(root().classList.contains('dark')).toBe(false)
    expect(root().style.colorScheme).toBe('light')
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe('light')
  })

  it.each(['auto', '', 'system', 'DARK'])(
    'трактует невалидное значение %j как светлую тему и очищает ключ',
    async (value) => {
      localStorage.setItem(THEME_STORAGE_KEY, value)
      const { useTheme } = await loadThemeModule()
      const { isDark } = useTheme()

      expect(isDark.value).toBe(false)
      expect(root().classList.contains('dark')).toBe(false)
      expect(localStorage.getItem(THEME_STORAGE_KEY)).toBeNull()
    },
  )

  it('работает в светлой теме, если чтение хранилища недоступно', async () => {
    vi.stubGlobal('localStorage', {
      getItem: () => {
        throw new Error('storage blocked')
      },
      setItem: () => {},
      removeItem: () => {},
    })
    const { useTheme } = await loadThemeModule()

    expect(() => useTheme()).not.toThrow()
    expect(useTheme().isDark.value).toBe(false)
    expect(root().classList.contains('dark')).toBe(false)
    expect(root().style.colorScheme).toBe('light')
  })

  it('переключает тему в текущей сессии, если запись в хранилище недоступна', async () => {
    vi.stubGlobal('localStorage', {
      getItem: () => null,
      setItem: () => {
        throw new Error('storage blocked')
      },
      removeItem: () => {},
    })
    const { useTheme } = await loadThemeModule()
    const { isDark, toggle } = useTheme()

    expect(() => toggle()).not.toThrow()
    expect(isDark.value).toBe(true)
    expect(root().classList.contains('dark')).toBe(true)
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBeNull()
  })

  it('после неудачной записи повторная инициализация даёт светлую тему', async () => {
    vi.stubGlobal('localStorage', {
      getItem: () => null,
      setItem: () => {
        throw new Error('storage blocked')
      },
      removeItem: () => {},
    })
    const first = await loadThemeModule()
    first.useTheme().toggle()
    expect(root().classList.contains('dark')).toBe(true)

    vi.unstubAllGlobals()
    localStorage.clear()
    const second = await loadThemeModule()
    expect(second.useTheme().isDark.value).toBe(false)
    expect(root().classList.contains('dark')).toBe(false)
  })

  describe('событие storage из другой вкладки', () => {
    const dispatchStorage = (newValue: string | null, key: string | null = THEME_STORAGE_KEY) =>
      window.dispatchEvent(
        new StorageEvent('storage', {
          key,
          newValue,
          storageArea: localStorage,
        }),
      )

    it.each(['dark', 'light'] as const)('применяет тему %s', async (value) => {
      const { useTheme } = await loadThemeModule()
      const { isDark } = useTheme()
      if (value === 'light') useTheme().toggle()

      dispatchStorage(value, THEME_STORAGE_KEY)

      expect(isDark.value).toBe(value === 'dark')
      expect(root().classList.contains('dark')).toBe(value === 'dark')
    })

    it.each(['auto', '', 'garbage'])(
      'невалидное значение %j даёт светлую тему и очищает ключ',
      async (value) => {
        localStorage.setItem(THEME_STORAGE_KEY, 'dark')
        const { useTheme } = await loadThemeModule()
        const { isDark } = useTheme()
        expect(isDark.value).toBe(true)

        dispatchStorage(value)

        expect(isDark.value).toBe(false)
        expect(root().classList.contains('dark')).toBe(false)
        expect(localStorage.getItem(THEME_STORAGE_KEY)).toBeNull()
      },
    )

    it('удаление ключа переводит вкладку в светлую тему', async () => {
      localStorage.setItem(THEME_STORAGE_KEY, 'dark')
      const { useTheme } = await loadThemeModule()
      const { isDark } = useTheme()
      expect(isDark.value).toBe(true)

      dispatchStorage(null)

      expect(isDark.value).toBe(false)
      expect(root().classList.contains('dark')).toBe(false)
    })

    it('удалённое значение ключа переводит вкладку в светлую тему', async () => {
      localStorage.setItem(THEME_STORAGE_KEY, 'dark')
      const { useTheme } = await loadThemeModule()
      const { isDark } = useTheme()
      expect(isDark.value).toBe(true)

      dispatchStorage(null, THEME_STORAGE_KEY)

      expect(isDark.value).toBe(false)
      expect(root().classList.contains('dark')).toBe(false)
      expect(localStorage.getItem(THEME_STORAGE_KEY)).toBeNull()
    })
  })
})
