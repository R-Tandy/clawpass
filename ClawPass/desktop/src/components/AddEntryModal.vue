<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal">
      <header class="modal-header">
        <h2>Add New Entry</h2>
        <button class="close-btn" @click="$emit('close')"><IconX /></button>
      </header>
      
      <form @submit.prevent="handleSubmit">
        <div class="form-group">
          <label>Title</label>
          <input v-model="form.title" type="text" placeholder="e.g. Gmail" required />
        </div>
        
        <div class="form-group">
          <label>Username</label>
          <input v-model="form.username" type="text" placeholder="your@email.com" required />
        </div>
        
        <div class="form-group">
          <label>Password</label>
          <div class="password-field">
            <input
              v-model="form.password"
              :type="showPassword ? 'text' : 'password'"
              placeholder="••••••••"
              required
            />
            <button type="button" class="icon-btn" @click="showPassword = !showPassword">
              <IconEye v-if="!showPassword" />
              <IconEyeOff v-else />
            </button>
            
            <button type="button" class="generate-btn" @click="generatePassword">
              Generate
            </button>
          </div>
        </div>
        
        <div class="form-group">
          <label>Website URL</label>
          <input v-model="form.url" type="url" placeholder="https://..." />
        </div>
        
        <div class="form-group">
          <label>Notes</label>
          <textarea v-model="form.notes" rows="3" placeholder="Additional notes..."></textarea>
        </div>
        
        <div class="form-group checkbox">
          <label>
            <input v-model="form.is_favorite" type="checkbox" />
            <span>Add to favorites</span>
          </label>
        </div>
        
        <footer class="modal-footer">
          <button type="button" class="btn-secondary" @click="$emit('close')">Cancel</button>
          <button type="submit" class="btn-primary" :disabled="isSubmitting">
            {{ isSubmitting ? 'Saving...' : 'Save Entry' }}
          </button>
        </footer>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useVaultStore } from '../stores/vault'
import IconX from './icons/IconX.vue'
import IconEye from './icons/IconEye.vue'
import IconEyeOff from './icons/IconEyeOff.vue'

const emit = defineEmits(['close'])
const vault = useVaultStore()

const showPassword = ref(false)
const isSubmitting = ref(false)

const form = reactive({
  title: '',
  username: '',
  password: '',
  url: '',
  notes: '',
  is_favorite: false
})

async function generatePassword() {
  const password = await vault.generatePassword({
    length: 16,
    use_uppercase: true,
    use_lowercase: true,
    use_numbers: true,
    use_symbols: true
  })
  form.password = password
}

async function handleSubmit() {
  isSubmitting.value = true
  
  try {
    await vault.addEntry({
      title: form.title,
      username: form.username,
      password: form.password,
      url: form.url || undefined,
      notes: form.notes || undefined,
      is_favorite: form.is_favorite
    })
    emit('close')
  } catch (error) {
    console.error('Failed to add entry:', error)
  } finally {
    isSubmitting.value = false
  }
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
  width: 480px;
  max-height: 90vh;
  overflow-y: auto;
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

form {
  padding: 24px;
}

.form-group {
  margin-bottom: 20px;
}

.form-group.checkbox label {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
}

.form-group.checkbox input {
  width: auto;
}

label {
  display: block;
  margin-bottom: 6px;
  font-size: 14px;
  font-weight: 500;
  color: #94a3b8;
}

input, textarea {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid #374151;
  border-radius: 6px;
  background: #1f2937;
  color: #fff;
  font-size: 14px;
}

input:focus, textarea:focus {
  outline: none;
  border-color: #6366f1;
}

.password-field {
  display: flex;
  gap: 8px;
}

.password-field input {
  flex: 1;
}

.icon-btn {
  width: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #374151;
  border: none;
  border-radius: 6px;
  color: #94a3b8;
  cursor: pointer;
}

.generate-btn {
  padding: 0 12px;
  background: #6366f1;
  border: none;
  border-radius: 6px;
  color: #fff;
  font-size: 13px;
  cursor: pointer;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  padding-top: 20px;
  border-top: 1px solid #374151;
}

.btn-secondary {
  padding: 10px 16px;
  background: transparent;
  border: 1px solid #374151;
  border-radius: 6px;
  color: #94a3b8;
  font-size: 14px;
  cursor: pointer;
}

.btn-primary {
  padding: 10px 16px;
  background: #6366f1;
  border: none;
  border-radius: 6px;
  color: #fff;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
}

.btn-primary:disabled {
  background: #4b5563;
  cursor: not-allowed;
}
</style>
