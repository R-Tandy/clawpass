<template>
  <div class="setup-view">
    <div class="setup-card">
      <div class="logo">
        <IconLock class="logo-icon" />
        <h1>Create Vault</h1>
      </div>
      
      <p class="subtitle">Set up your secure password vault</p>
      
      <form @submit.prevent="handleSetup">
        <div class="input-group">
          <input
            v-model="password"
            type="password"
            placeholder="Master Password"
            class="password-input"
          />
        </div>
        
        <div class="input-group">
          <input
            v-model="confirmPassword"
            type="password"
            placeholder="Confirm Password"
            class="password-input"
          />
        </div>
        
        <div class="strength-meter">
          <div class="strength-bar" :style="{ width: strength + '%', background: strengthColor }"></div>
        </div>
        <p class="strength-text" :style="{ color: strengthColor }">{{ strengthText }}</p>
        
        <button
          type="submit"
          class="setup-btn"
          :disabled="!canSubmit || isLoading"
        >
          <span v-if="isLoading">Creating...</span>
          <span v-else>Create Vault</span>
        </button>
      </form>
      
      <p v-if="error" class="error">{{ error }}</p>
      
      <button class="back-link" @click="goBack">
        Already have a vault?
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useVaultStore } from '../stores/vault'
import IconLock from '../components/icons/IconLock.vue'

const router = useRouter()
const vault = useVaultStore()

const password = ref('')
const confirmPassword = ref('')
const isLoading = ref(false)
const error = ref('')

const strength = computed(() => {
  if (!password.value) return 0
  let score = 0
  if (password.value.length >= 8) score += 20
  if (password.value.length >= 12) score += 20
  if (/[A-Z]/.test(password.value)) score += 20
  if (/[0-9]/.test(password.value)) score += 20
  if (/[^A-Za-z0-9]/.test(password.value)) score += 20
  return score
})

const strengthColor = computed(() => {
  if (strength.value < 40) return '#ef4444'
  if (strength.value < 80) return '#f59e0b'
  return '#22c55e'
})

const strengthText = computed(() => {
  if (!password.value) return ''
  if (strength.value < 40) return 'Weak'
  if (strength.value < 80) return 'Fair'
  if (strength.value < 100) return 'Good'
  return 'Strong'
})

const canSubmit = computed(() => {
  return password.value && password.value === confirmPassword.value && strength.value >= 60
})

async function handleSetup() {
  if (password.value !== confirmPassword.value) {
    error.value = 'Passwords do not match'
    return
  }
  
  if (strength.value < 60) {
    error.value = 'Password is too weak'
    return
  }
  
  isLoading.value = true
  error.value = ''
  
  try {
    await vault.createVault(password.value)
    router.push('/vault')
  } catch (e) {
    error.value = 'Failed to create vault'
  } finally {
    isLoading.value = false
  }
}

function goBack() {
  router.push('/')
}
</script>

<style scoped>
.setup-view {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
}

.setup-card {
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
  margin-bottom: 12px;
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

.strength-meter {
  height: 4px;
  background: #374151;
  border-radius: 2px;
  margin-top: 16px;
  overflow: hidden;
}

.strength-bar {
  height: 100%;
  transition: all 0.3s;
}

.strength-text {
  margin-top: 8px;
  font-size: 14px;
  font-weight: 500;
}

.setup-btn {
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
  margin-top: 24px;
}

.setup-btn:hover:not(:disabled) {
  background: #4f46e5;
}

.setup-btn:disabled {
  background: #4b5563;
  cursor: not-allowed;
}

.error {
  color: #ef4444;
  margin-top: 12px;
  font-size: 14px;
}

.back-link {
  margin-top: 24px;
  background: none;
  border: none;
  color: #6366f1;
  font-size: 14px;
  cursor: pointer;
  text-decoration: underline;
}
</style>
