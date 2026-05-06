import { createRouter, createWebHistory } from 'vue-router'
import { useVaultStore } from '../stores/vault'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      name: 'unlock',
      component: () => import('../views/UnlockView.vue'),
      meta: { guest: true }
    },
    {
      path: '/setup',
      name: 'setup',
      component: () => import('../views/SetupView.vue'),
      meta: { guest: true }
    },
    {
      path: '/vault',
      name: 'vault',
      component: () => import('../views/VaultView.vue'),
      meta: { requiresAuth: true }
    }
  ]
})

router.beforeEach((to, from, next) => {
  const vault = useVaultStore()
  
  if (to.meta.requiresAuth && !vault.isUnlocked) {
    next('/')
  } else if (to.meta.guest && vault.isUnlocked) {
    next('/vault')
  } else {
    next()
  }
})

export default router
