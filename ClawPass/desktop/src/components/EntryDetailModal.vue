<template>
  <div class="modal-overlay" @click.self="$emit('close')">
    <div class="modal">
      <header class="modal-header">
        <h2>{{ entry.title }}</h2>
        <button class="close-btn" @click="$emit('close')"><IconX /></button>
      </header>
      
      <div class="modal-body">
        <div class="detail-group">
          <label>Username</label>
          <div class="copy-field">
            <span>{{ entry.username }}</span>
            <button @click="copyToClipboard(entry.username)">
              <IconCopy />
            </button>
          </div>
        </div>
        
        <div class="detail-group">
          <label>Password</label>
          <div class="copy-field">
            <span>{{ showPassword ? decryptedPassword : '••••••••' }}</span>
            <button @click="togglePassword">
              <IconEye v-if="!showPassword" />
              <IconEyeOff v-else />
            </button>
            <button @click="copyPassword">
              <IconCopy />
            </button>
          </div>
        </div>
        
        <div v-if="entry.url" class="detail-group">
          <label>Website</label>
          <a :href="entry.url" target="_blank" class="url-link">
            {{ entry.url }}
            <IconExternal />
          </a>
        </div>
        
        <div v-if="decryptedNotes" class="detail-group">
          <label>Notes</label>
          <div class="notes">{{ decryptedNotes }}</div>
        </div>
        
        <div class="detail-actions">
          <button class="btn-secondary" @click="$emit('close')">Close</button>
          <button class="btn-danger" @click="deleteEntry">Delete</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useVaultStore, type VaultEntry } from '../stores/vault'
import { writeText } from '@tauri-apps/api/clipboard'
import IconX from './icons/IconX.vue'
import IconCopy from './icons/IconCopy.vue'
import IconEye from './icons/IconEye.vue'
import IconEyeOff from './icons/IconEyeOff.vue'
import IconExternal from './icons/IconExternal.vue'

const props = defineProps<{
  entry: VaultEntry
}>()

const emit = defineEmits(['close', 'delete'])
const vault = useVaultStore()

const showPassword = ref(false)
const decryptedPassword = ref('')
const decryptedNotes = ref('')

onMounted(async () => {
  decryptedPassword.value = await vault.decryptPassword(props.entry.encrypted_password)
  if (props.entry.encrypted_notes) {
    decryptedNotes.value = await vault.decryptNotes(props.entry.encrypted_notes)
  }
})

function togglePassword() {
  showPassword.value = !showPassword.value
}

async function copyToClipboard(text: string) {
  await writeText(text)
}

async function copyPassword() {
  await copyToClipboard(decryptedPassword.value)
}

function deleteEntry() {
  if (confirm('Delete this entry? This cannot be undone.')) {
    vault.deleteEntry(props.entry.id)
    emit('close')
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

.detail-group {
  margin-bottom: 20px;
}

.detail-group label {
  display: block;
  margin-bottom: 6px;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: #64748b;
}

.copy-field {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px;
  background: #1f2937;
  border-radius: 6px;
}

.copy-field span {
  flex: 1;
  color: #fff;
  font-family: monospace;
}

.copy-field button {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #374151;
  border: none;
  border-radius: 4px;
  color: #94a3b8;
  cursor: pointer;
}

.url-link {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px;
  background: #1f2937;
  border-radius: 6px;
  color: #6366f1;
  text-decoration: none;
}

.notes {
  padding: 12px;
  background: #1f2937;
  border-radius: 6px;
  color: #94a3b8;
  white-space: pre-wrap;
}

.detail-actions {
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

.btn-danger {
  padding: 10px 16px;
  background: #ef4444;
  border: none;
  border-radius: 6px;
  color: #fff;
  font-size: 14px;
  cursor: pointer;
}
</style>
