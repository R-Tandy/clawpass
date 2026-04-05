import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { invoke } from '@tauri-apps/api/tauri'

export interface VaultEntry {
  id: string
  title: string
  username: string
  encrypted_password: number[]
  url?: string
  encrypted_notes?: number[]
  category_id?: string
  totp_secret?: string
  created_at: number
  modified_at: number
  is_favorite: boolean
}

export interface Category {
  id: string
  name: string
  icon: string
  color: string
}

export interface PasswordOptions {
  length: number
  use_uppercase: boolean
  use_lowercase: boolean
  use_numbers: boolean
  use_symbols: boolean
}

export interface NewEntry {
  title: string
  username: string
  password: string
  url?: string
  notes?: string
  category_id?: string
  totp_secret?: string
  is_favorite?: boolean
}

export const useVaultStore = defineStore('vault', () => {
  const isUnlocked = ref(false)
  const entries = ref<VaultEntry[]>([])
  const categories = ref<Category[]>([])
  const searchQuery = ref('')
  const selectedCategory = ref<string | null>(null)
  
  const filteredEntries = computed(() => {
    let result = entries.value
    
    if (selectedCategory.value) {
      result = result.filter(e => e.category_id === selectedCategory.value)
    }
    
    if (searchQuery.value) {
      const query = searchQuery.value.toLowerCase()
      result = result.filter(e => 
        e.title.toLowerCase().includes(query) ||
        e.username.toLowerCase().includes(query)
      )
    }
    
    return result.sort((a, b) => {
      if (a.is_favorite && !b.is_favorite) return -1
      if (!a.is_favorite && b.is_favorite) return 1
      return b.modified_at - a.modified_at
    })
  })
  
  async function unlock(password: string): Promise<boolean> {
    try {
      const result = await invoke<boolean>('unlock_vault', { password })
      if (result) {
        isUnlocked.value = true
        await loadEntries()
      }
      return result
    } catch (error) {
      console.error('Unlock failed:', error)
      return false
    }
  }
  
  async function createVault(password: string): Promise<void> {
    await invoke('create_vault', { password })
    isUnlocked.value = true
    await loadEntries()
  }
  
  async function lock(): Promise<void> {
    await invoke('lock_vault')
    isUnlocked.value = false
    entries.value = []
  }
  
  async function loadEntries(): Promise<void> {
    try {
      entries.value = await invoke('get_entries')
    } catch (error) {
      console.error('Failed to load entries:', error)
    }
  }
  
  async function addEntry(entry: NewEntry): Promise<void> {
    // Encrypt password and notes
    const now = Date.now()
    const vaultEntry: VaultEntry = {
      id: crypto.randomUUID(),
      title: entry.title,
      username: entry.username,
      encrypted_password: Array.from(new TextEncoder().encode(entry.password)),
      url: entry.url,
      encrypted_notes: entry.notes ? Array.from(new TextEncoder().encode(entry.notes)) : undefined,
      category_id: entry.category_id,
      totp_secret: entry.totp_secret,
      created_at: now,
      modified_at: now,
      is_favorite: entry.is_favorite || false
    }
    
    await invoke('add_entry', { entry: vaultEntry })
    await loadEntries()
  }
  
  async function updateEntry(entry: VaultEntry): Promise<void> {
    await invoke('update_entry', { entry })
    await loadEntries()
  }
  
  async function deleteEntry(id: string): Promise<void> {
    await invoke('delete_entry', { id })
    await loadEntries()
  }
  
  async function decryptPassword(encrypted: number[]): Promise<string> {
    return await invoke('decrypt_password', { encrypted })
  }
  
  async function decryptNotes(encrypted: number[]): Promise<string> {
    return await invoke('decrypt_notes', { encrypted })
  }
  
  async function generatePassword(options: PasswordOptions): Promise<string> {
    return await invoke('generate_password', { options })
  }
  
  async function importFromKeeper(filePath: string): Promise<number> {
    return await invoke('import_from_keeper', { filePath })
  }
  
  async function exportVault(filePath: string): Promise<void> {
    await invoke('export_vault', { filePath })
  }
  
  return {
    isUnlocked,
    entries,
    categories,
    searchQuery,
    selectedCategory,
    filteredEntries,
    unlock,
    createVault,
    lock,
    loadEntries,
    addEntry,
    updateEntry,
    deleteEntry,
    decryptPassword,
    decryptNotes,
    generatePassword,
    importFromKeeper,
    exportVault
  }
})
