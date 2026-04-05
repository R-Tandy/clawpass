<template>
  <div class="unlock-view">
    <div class="unlock-card">
      <div class="logo">
        <IconLock class="logo-icon" />
        <h1>ClawPass</h1>
      </div>
      
      <p class="subtitle">Enter your master password to unlock</p>
      
      <form @submit.prevent="handleUnlock">
        <div class="input-group">
          <input
            v-model="password"
            type="password"
            placeholder="Master Password"
            class="password-input"
            autofocus
          />
        </div>
        
        <button
          type="submit"
          class="unlock-btn"
          :disabled="!password || isLoading"
        >
          <span v-if="isLoading">Unlocking...</span>
          <span v-else>Unlock</span>
        </button>
      </form>
      
      <p v-if="error" class="error">{{ error }}</p>
      
      <button class="setup-link" @click="goToSetup">
        Create new vault
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useVaultStore } from '../stores/vault'
import IconLock from '../components/icons/IconLock.vue'

const router = useRouter()
const vault = useVaultStore()

const password = ref('')
const isLoading = ref(false)
const error = ref('')

async function handleUnlock() {
  if (!password.value) return
  
  isLoading.value = true
  error.value = ''
  
  try {
    const success = await vault.unlock(password.value)
    if (success) {
      router.push('/vault')
    } else {
      error.value = 'Invalid password'
    }
  } catch (e) {
    error.value = 'Unlock failed'
  } finally {
    isLoading.value = false
  }
}

function goToSetup() {
  router.push('/setup')
}
</script>

<style scoped>
.unlock-view {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
}

.unlock-card {
  background: #252542;
  padding: 48px;
  border-radius: 16px;
  width: 400px;
  text-align: center;
  box-shadow: 0 20px 60px rgba(0,0,0,0.4);
}

.logo {
  margin-bottom: 24px;
}

.logo-icon {
  width: 64px;
  height: 64px;
  color: #6366f1;
  margin-bottom: 16px;
}

h1 {
  font-size: 28px;
  font-weight: 700;
  color: #fff;
}

.subtitle {
  color: #94a3b8;
  margin-bottom: 24px;
}

.input-group {
  margin-bottom: 16px;
}

.password-input {
  width: 100%;
  padding: 14px 16px;
  border: 2px solid #374151;
  border-radius: 8px;
  background: #1f2937;
  color: #fff;
  font-size: 16px;
  transition: border-color 0.2s;
}

.password-input:focus {
  outline: none;
  border-color: #6366f1;
}

.unlock-btn {
  width: 100%;
  padding: 14px;
  border: none;
  border-radius: 8px;
  background: #6366f1;
  color: #fff;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.2s;
}

.unlock-btn:hover:not(:disabled) {
  background: #4f46e5;
}

.unlock-btn:disabled {
  background: #4b5563;
  cursor: not-allowed;
}

.error {
  color: #ef4444;
  margin-top: 12px;
  font-size: 14px;
}

.setup-link {
  margin-top: 24px;
  background: none;
  border: none;
  color: #6366f1;
  font-size: 14px;
  cursor: pointer;
  text-decoration: underline;
}

.setup-link:hover {
  color: #818cf8;
}
</style>
