<template>
  <div class="app">
    <router-view />
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { listen } from '@tauri-apps/api/event'

onMounted(() => {
  listen('show_preferences', () => {
    // Handle preferences menu
  })
  
  listen('generate_password', () => {
    // Handle generate password menu
  })
})
</script>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: #1a1a2e;
  color: #eee;
}

.app {
  height: 100vh;
  display: flex;
  flex-direction: column;
}
</style>
