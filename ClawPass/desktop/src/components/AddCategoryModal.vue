<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal">
      <header class="modal-header">
        <h2>Add Category</h2>
        <button class="close-btn" @click="$emit('close')"><IconX /></button>
      </header>
      
      <form @submit.prevent="handleSubmit">
        <div class="form-group">
          <label>Name</label>
          <input v-model="form.name" type="text" placeholder="e.g. Work, Personal" required />
        </div>
        
        <div class="form-group">
          <label>Icon</label>
          <div class="icon-grid">
            <button
              v-for="icon in availableIcons"
              :key="icon"
              type="button"
              class="icon-option"
              :class="{ selected: form.icon === icon }"
              @click="form.icon = icon"
            >
              {{ icon }}
            </button>
          </div>
        </div>
        
        <div class="form-group">
          <label>Color</label>
          <div class="color-grid">
            <button
              v-for="color in availableColors"
              :key="color"
              type="button"
              class="color-option"
              :class="{ selected: form.color === color }"
              :style="{ backgroundColor: color }"
              @click="form.color = color"
            />
          </div>
        </div>
        
        <footer class="modal-footer">
          <button type="button" class="btn-secondary" @click="$emit('close')">Cancel</button>
          <button type="submit" class="btn-primary" :disabled="isSubmitting">
            {{ isSubmitting ? 'Adding...' : 'Add Category' }}
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

const emit = defineEmits(['close', 'added'])
const vault = useVaultStore()

const isSubmitting = ref(false)

const availableIcons = ['🏢', '🏠', '💰', '🛒', '🎮', '🔒', '💻', '📱', '🌐', '📧']
const availableColors = ['#6366f1', '#ef4444', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6', '#ec4899', '#6b7280']

const form = reactive({
  name: '',
  icon: availableIcons[0],
  color: availableColors[0]
})

async function handleSubmit() {
  isSubmitting.value = true
  
  try {
    await vault.addCategory(form.name, form.icon, form.color)
    emit('added')
    emit('close')
  } catch (error) {
    console.error('Failed to add category:', error)
    alert('Failed to add category')
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
  overflow: hidden;
}

.modal-header {
  padding: 20px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid #374151;
}

.modal-header h2 {
  font-size: 18px;
  font-weight: 600;
}

.close-btn {
  background: transparent;
  border: none;
  color: #94a3b8;
  cursor: pointer;
}

.close-btn:hover {
  color: #fff;
}

form {
  padding: 20px;
  overflow-y: auto;
}

.form-group {
  margin-bottom: 16px;
}

.form-group label {
  display: block;
  margin-bottom: 8px;
  font-size: 14px;
  font-weight: 500;
  color: #94a3b8;
}

.form-group input {
  width: 100%;
  padding: 10px 12px;
  background: #1a1a2e;
  border: 1px solid #374151;
  border-radius: 6px;
  color: #fff;
  font-size: 14px;
}

.form-group input:focus {
  outline: none;
  border-color: #6366f1;
}

.icon-grid {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 8px;
}

.icon-option {
  padding: 12px;
  background: #1a1a2e;
  border: 1px solid #374151;
  border-radius: 6px;
  cursor: pointer;
  font-size: 20px;
  transition: all 0.2s;
}

.icon-option:hover,
.icon-option.selected {
  border-color: #6366f1;
  background: #2e2e52;
}

.color-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 8px;
}

.color-option {
  aspect-ratio: 1;
  border: 2px solid transparent;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.2s;
}

.color-option:hover {
  transform: scale(1.05);
}

.color-option.selected {
  border-color: #fff;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  margin-top: 24px;
  padding-top: 16px;
  border-top: 1px solid #374151;
}

.btn-secondary {
  padding: 10px 16px;
  background: transparent;
  border: 1px solid #374151;
  border-radius: 6px;
  color: #94a3b8;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-secondary:hover {
  background: #374151;
  color: #fff;
}

.btn-primary {
  padding: 10px 16px;
  background: #6366f1;
  border: none;
  border-radius: 6px;
  color: #fff;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.2s;
}

.btn-primary:hover {
  background: #4f46e5;
}

.btn-primary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
