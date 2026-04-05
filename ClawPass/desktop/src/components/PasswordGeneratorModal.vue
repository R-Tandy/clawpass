<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal">
      <header class="modal-header">
        <h2>Password Generator</h2>
        <button class="close-btn" @click="$emit('close')"><IconX /></button>
      </header>
      
      <div class="modal-body">
        <div class="password-display">
          <pre>{{ generatedPassword }}</pre>
          <button class="copy-btn" @click="copyPassword">
            <IconCopy />
          </button>
        </div>
        
        <div class="length-control">
          <label>Length: {{ options.length }}</label>
          <input
            v-model.number="options.length"
            type="range"
            min="8"
            max="64"
          />
        </div>
        
        <div class="options">
          <label class="option">
            <input v-model="options.use_uppercase" type="checkbox" />
            <span>Uppercase (A-Z)</span>
          </label>
          
          <label class="option">
            <input v-model="options.use_lowercase" type="checkbox" />
            <span>Lowercase (a-z)</span>
          </label>
          
          <label class="option">
            <input v-model="options.use_numbers" type="checkbox" />
            <span>Numbers (0-9)</span>
          </label>
          
          <label class="option">
            <input v-model="options.use_symbols" type="checkbox" />
            <span>Symbols (!@#$%)</span>
          </label>
        </div>
        
        <button class="btn-primary" @click="regenerate">
          Regenerate
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { reactive, computed } from 'vue'
import { useVaultStore } from '../stores/vault'
import { writeText } from '@tauri-apps/api/clipboard'
import IconX from './icons/IconX.vue'
import IconCopy from './icons/IconCopy.vue'

const emit = defineEmits(['close'])
const vault = useVaultStore()

const options = reactive({
  length: 16,
  use_uppercase: true,
  use_lowercase: true,
  use_numbers: true,
  use_symbols: true
})

const generatedPassword = computed(() => {
  return vault.generatePassword({ ...options })
})

async function copyPassword() {
  await writeText(generatedPassword.value)
}

function regenerate() {
  // Force recompute
  options.length = options.length
}
</script>

<style scoped>
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.7);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
}

.modal {
  background: #252542;
  border-radius: 12px;
  width: 400px;
}

.modal-header {
  padding: 20px 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid #374151;
}

.modal-header h2 {
  font-size: 18px;
  font-weight: 600;
  color: #fff;
}

.close-btn {
  background: transparent;
  border: none;
  color: #94a3b8;
  cursor: pointer;
}

.modal-body {
  padding: 24px;
}

.password-display {
  display: flex;
  align-items: center;
  gap: 12px;
  background: #1f2937;
  padding: 16px;
  border-radius: 8px;
  margin-bottom: 24px;
}

.password-display pre {
  flex: 1;
  font-family: monospace;
  font-size: 16px;
  color: #fff;
  word-break: break-all;
}

.copy-btn {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #374151;
  border: none;
  border-radius: 6px;
  color: #94a3b8;
  cursor: pointer;
}

.length-control {
  margin-bottom: 20px;
}

.length-control label {
  display: block;
  margin-bottom: 8px;
  font-size: 14px;
  color: #94a3b8;
}

.length-control input {
  width: 100%;
}

.options {
  display: grid;
  gap: 12px;
  margin-bottom: 24px;
}

.option {
  display: flex;
  align-items: center;
  gap: 10px;
  cursor: pointer;
  font-size: 14px;
  color: #94a3b8;
}

.option input {
  width: 18px;
  height: 18px;
}

.btn-primary {
  width: 100%;
  padding: 12px;
  background: #6366f1;
  border: none;
  border-radius: 6px;
  color: #fff;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
}
</style>
