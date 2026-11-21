<script setup lang="ts">
import { Moon, Sun } from '@lucide/vue'

import { Button } from '@/components/ui/button'
import { useTheme } from '@/lib/useTheme'

const { isDark, toggle } = useTheme()
</script>

<template>
  <Button
    type="button"
    class="theme-toggle"
    variant="ghost"
    size="icon-sm"
    :aria-label="isDark ? 'Включить светлую тему' : 'Включить тёмную тему'"
    :aria-pressed="isDark"
    :title="isDark ? 'Включить светлую тему' : 'Включить тёмную тему'"
    @click="toggle"
  >
    <Sun v-if="isDark" :size="18" aria-hidden="true" />
    <Moon v-else :size="18" aria-hidden="true" />
  </Button>
</template>
