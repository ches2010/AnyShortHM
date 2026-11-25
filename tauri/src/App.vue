<script setup lang="ts">
import { computed } from 'vue';
import { route, go } from './router';
import { t, i18nState, toggleLang } from './i18n';
import Home from './views/Home.vue';
import Search from './views/Search.vue';
import Library from './views/Library.vue';
import Detail from './views/Detail.vue';
import Player from './views/Player.vue';
import Login from './views/Login.vue';

const tab = computed(() => {
  if (route.name === 'home' || route.name === '') return 'home';
  if (route.name === 'search') return 'search';
  if (route.name === 'library') return 'library';
  return 'home';
});
const isPlayer = computed(() => route.name === 'player');
</script>

<template>
  <div class="app-shell">
    <Player v-if="isPlayer" />

    <template v-else>
      <header class="app-header">
        <div class="logo">Any<b>Short</b></div>
        <div class="tagline">{{ t('app_tagline') }}</div>
        <button class="icon-btn" @click="toggleLang">{{ i18nState.lang === 'zh-Hans' ? '中' : 'EN' }}</button>
      </header>

      <div class="page pad">
        <Detail v-if="route.name === 'detail'" />
        <Login v-else-if="route.name === 'login'" />
        <Search v-else-if="tab === 'search'" />
        <Library v-else-if="tab === 'library'" />
        <Home v-else />
      </div>

      <nav class="tabbar">
        <div class="tab" :class="{ active: tab === 'home' }" @click="go('/home')">
          <span class="glyph">⌂</span>{{ t('nav_home') }}
        </div>
        <div class="tab" :class="{ active: tab === 'search' }" @click="go('/search')">
          <span class="glyph">⌕</span>{{ t('nav_search') }}
        </div>
        <div class="tab" :class="{ active: tab === 'library' }" @click="go('/library')">
          <span class="glyph">☰</span>{{ t('nav_library') }}
        </div>
      </nav>
    </template>
  </div>
</template>
