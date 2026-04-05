<template>
  <div class="vault-view">
    <header class="vault-header">
      <div class="search-box">
        <IconSearch class="search-icon" />
        <input
          v-model="vault.searchQuery"
          type="text"
          placeholder="Search passwords..."
          class="search-input"
        />
      </div>
      
      <div class="header-actions">
        <button class="icon-btn" @click="showGenerator = true" title="Generate Password">
          <IconWand />
        </button>
        
        <button class="icon-btn" @click="importFromKeeper" title="Import from Keeper">
          <IconImport />
        </button>
        
        <button class="icon-btn" @click="exportVault" title="Export Vault">
          <IconExport />
        </button>
        
        <button class="icon-btn" @click="lock" title="Lock Vault">
          <IconLock />
        </button>
      </div>
    </header>
    
    <div class="vault-content">
      <aside class="sidebar">
        <div class="sidebar-header">
          <h2>Categories</h2>
        </div>
        
        <nav class="category-list">
          <button
            class="category-btn"
            :class="{ active: !vault.selectedCategory }"
            @click="vault.selectedCategory = null"
          >
            <IconFolder />
            <span>All Items</span>
            <span class="count">{{ vault.entries.length }}</span>
          </button>
        </nav>
        
        <div class="sync-section">
          <button class="sync-btn" @click="startSync">
            <IconSync />
            <span>Sync</span>
          </button>
        </div>
      </aside>
      
      <main class="main-content">
        <div class="entries-header">
          <h2>{{ vault.selectedCategory || 'All Items' }}</h2>
          
          <button class="add-btn" @click="showAddEntry = true">
            <IconPlus />
            <span>Add Entry</span>
          </button>
        </div>
        
        <div class="entries-list">
          <div
            v-for="entry in vault.filteredEntries"
            :key="entry.id"
            class="entry-item"
            :class="{ favorite: entry.is_favorite }"
            @click="selectEntry(entry)"
          >
            <div class="entry-icon">
              <IconKey />
            </div>
            
            <div class="entry-info">
              <h3>{{ entry.title }}</h3>
              <p>{{ entry.username }}</p>
            </div>
            
            <div class="entry-actions" @click.stop>
              <button
                class="action-btn"
                @click="copyToClipboard(entry.username, 'username')"
                title="Copy Username"
              >
                <IconUser />
              </button>
              
              <button
                class="action-btn"
                @click="copyPassword(entry)"
                title="Copy Password"
              >
                <IconCopy />
              </button>
              
              <button
                class="action-btn favorite-btn"
                :class="{ active: entry.is_favorite }"
                @click="toggleFavorite(entry)"
                title="Toggle Favorite"
              >
                <IconStar />
              </button>
            </div>
          </div>
          
          <div v-if="vault.filteredEntries.length === 0" class="empty-state">
            <IconEmpty />
            <p>No entries found</p>
          </div>
        </div>
      </main>
    </div>
    
    <AddEntryModal v-if="showAddEntry" @close="showAddEntry = false" />
    
    <PasswordGeneratorModal v-if="showGenerator" @close="showGenerator = false" />
    
    <EntryDetailModal
      v-if="selectedEntry"
      :entry="selectedEntry"
      @close="selectedEntry = null"
    />
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useVaultStore, type VaultEntry } from '../stores/vault'
import { writeText } from '@tauri-apps/api/clipboard'
import IconSearch from '../components/icons/IconSearch.vue'
import IconWand from '../components/icons/IconWand.vue'
import IconImport from '../components/icons/IconImport.vue'
import IconExport from '../components/icons/IconExport.vue'
import IconLock from '../components/icons/IconLock.vue'
import IconFolder from '../components/icons/IconFolder.vue'
import IconSync from '../components/icons/IconSync.vue'
import IconPlus from '../components/icons/IconPlus.vue'
import IconKey from '../components/icons/IconKey.vue'
import IconUser from '../components/icons/IconUser.vue'
import IconCopy from '../components/icons/IconCopy.vue'
import IconStar from '../components/icons/IconStar.vue'
import IconEmpty from '../components/icons/IconEmpty.vue'
import AddEntryModal from '../components/AddEntryModal.vue'
import PasswordGeneratorModal from '../components/PasswordGeneratorModal.vue'
import EntryDetailModal from '../components/EntryDetailModal.vue'

const router = useRouter()
const vault = useVaultStore()

const showAddEntry = ref(false)
const showGenerator = ref(false)
const selectedEntry = ref<VaultEntry | null>(null)
const clipboardTimeout = ref<NodeJS.Timeout | null>(null)

function selectEntry(entry: VaultEntry) {
  selectedEntry.value = entry
}

async function copyToClipboard(text: string, type: string) {
  await writeText(text)
  
  // Clear after 30 seconds
  if (clipboardTimeout.value) {
    clearTimeout(clipboardTimeout.value)
  }
  clipboardTimeout.value = setTimeout(() => {
    writeText('')
  }, 30000)
}

async function copyPassword(entry: VaultEntry) {
  const password = await vault.decryptPassword(entry.encrypted_password)
  await copyToClipboard(password, 'password')
}

function toggleFavorite(entry: VaultEntry) {
  const updated = { ...entry, is_favorite: !entry.is_favorite }
  vault.updateEntry(updated)
}

function lock() {
  vault.lock()
  router.push('/')
}

function importFromKeeper() {
  // Open file dialog and import
}

function exportVault() {
  // Open save dialog and export
}

function startSync() {
  // Start sync listener
}
</script>

<style scoped>
.vault-view {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background: #1a1a2e;
}

.vault-header {
  height: 64px;
  padding: 0 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #252542;
  border-bottom: 1px solid #374151;
}

.search-box {
  display: flex;
  align-items: center;
  gap: 12px;
  flex: 1;
  max-width: 400px;
}

.search-icon {
  width: 20px;
  height: 20px;
  color: #94a3b8;
}

.search-input {
  flex: 1;
  background: transparent;
  border: none;
  color: #fff;
  font-size: 15px;
  outline: none;
}

.search-input::placeholder {
  color: #64748b;
}

.header-actions {
  display: flex;
  gap: 8px;
}

.icon-btn {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: none;
  border-radius: 8px;
  color: #94a3b8;
  cursor: pointer;
  transition: all 0.2s;
}

.icon-btn:hover {
  background: #374151;
  color: #fff;
}

.vault-content {
  flex: 1;
  display: flex;
  overflow: hidden;
}

.sidebar {
  width: 240px;
  background: #252542;
  border-right: 1px solid #374151;
  display: flex;
  flex-direction: column;
}

.sidebar-header {
  padding: 16px;
  border-bottom: 1px solid #374151;
}

.sidebar-header h2 {
  font-size: 14px;
  font-weight: 600;
  color: #94a3b8;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.category-list {
  flex: 1;
  padding: 8px;
}

.category-btn {
  width: 100%;
  padding: 10px 12px;
  display: flex;
  align-items: center;
  gap: 12px;
  background: transparent;
  border: none;
  border-radius: 6px;
  color: #94a3b8;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.2s;
}

.category-btn:hover,
.category-btn.active {
  background: #6366f1;
  color: #fff;
}

.category-btn .count {
  margin-left: auto;
  font-size: 12px;
  background: #374151;
  padding: 2px 8px;
  border-radius: 10px;
}

.sync-section {
  padding: 16px;
  border-top: 1px solid #374151;
}

.sync-btn {
  width: 100%;
  padding: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  background: #374151;
  border: none;
  border-radius: 6px;
  color: #fff;
  font-size: 14px;
  cursor: pointer;
  transition: background 0.2s;
}

.sync-btn:hover {
  background: #4b5563;
}

.main-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.entries-header {
  padding: 16px 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid #374151;
}

.entries-header h2 {
  font-size: 20px;
  font-weight: 600;
  color: #fff;
}

.add-btn {
  padding: 10px 16px;
  display: flex;
  align-items: center;
  gap: 8px;
  background: #6366f1;
  border: none;
  border-radius: 6px;
  color: #fff;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.2s;
}

.add-btn:hover {
  background: #4f46e5;
}

.entries-list {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
}

.entry-item {
  padding: 16px;
  display: flex;
  align-items: center;
  gap: 16px;
  background: #252542;
  border-radius: 8px;
  margin-bottom: 8px;
  cursor: pointer;
  transition: all 0.2s;
}

.entry-item:hover {
  background: #2e2e52;
}

.entry-item.favorite {
  border-left: 3px solid #fbbf24;
}

.entry-icon {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #374151;
  border-radius: 8px;
  color: #6366f1;
}

.entry-info {
  flex: 1;
}

.entry-info h3 {
  font-size: 15px;
  font-weight: 500;
  color: #fff;
  margin-bottom: 4px;
}

.entry-info p {
  font-size: 13px;
  color: #94a3b8;
}

.entry-actions {
  display: flex;
  gap: 8px;
  opacity: 0;
  transition: opacity 0.2s;
}

.entry-item:hover .entry-actions {
  opacity: 1;
}

.action-btn {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #374151;
  border: none;
  border-radius: 6px;
  color: #94a3b8;
  cursor: pointer;
  transition: all 0.2s;
}

.action-btn:hover {
  background: #4b5563;
  color: #fff;
}

.action-btn.active {
  color: #fbbf24;
}

.empty-state {
  padding: 64px;
  text-align: center;
  color: #64748b;
}

.empty-state p {
  margin-top: 16px;
  font-size: 14px;
}
</style>
