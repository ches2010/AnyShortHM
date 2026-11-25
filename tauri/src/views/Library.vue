<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { api, type TitleItem } from '../api';
import { t } from '../i18n';
import { go } from '../router';
import { appState } from '../store';
import PosterCard from '../components/PosterCard.vue';

const seg = ref<'history' | 'favorites'>('history');
const loading = ref(false);
const errMsg = ref('');
const history = ref<{ title_id?: number; episode_no?: number; name?: string; cover_url?: string }[]>([]);
const favorites = ref<TitleItem[]>([]);

async function loadHistory(): Promise<void> {
  loading.value = true;
  errMsg.value = '';
  try {
    const page = await api.history();
    history.value = page.data ?? [];
  } catch (e) {
    errMsg.value = (e as Error).message;
  } finally {
    loading.value = false;
  }
}

async function loadFavorites(): Promise<void> {
  loading.value = true;
  errMsg.value = '';
  try {
    const page = await api.favorites();
    favorites.value = page.data ?? [];
  } catch (e) {
    errMsg.value = (e as Error).message;
  } finally {
    loading.value = false;
  }
}

function switchSeg(s: 'history' | 'favorites'): void {
  seg.value = s;
  if (s === 'history') void loadHistory();
  else void loadFavorites();
}

function open(id?: number): void {
  if (id) go(`/detail/${id}`);
}

onMounted(() => void loadHistory());
</script>

<template>
  <div>
    <div class="section-title"><h3>{{ t('nav_library') }}</h3></div>

    <div class="rail" style="padding-bottom:12px">
      <button class="chip" :class="{ active: seg === 'history' }" @click="switchSeg('history')">{{ t('history') }}</button>
      <button class="chip" :class="{ active: seg === 'favorites' }" @click="switchSeg('favorites')">{{ t('favorites') }}</button>
      <span style="flex:1"></span>
      <button v-if="!appState.user" class="chip" @click="go('/login')">{{ t('login') }} ›</button>
    </div>

    <div v-if="errMsg" class="hint">{{ errMsg }}</div>
    <div v-else-if="loading" class="hint">{{ t('loading') }}</div>

    <template v-else>
      <template v-if="seg === 'history'">
        <div v-if="!history.length" class="hint">{{ t('empty') }}</div>
        <div v-else style="padding:0 14px">
          <div
            v-for="(h, i) in history"
            :key="i"
            style="display:flex;gap:12px;padding:10px 0;border-bottom:1px solid var(--divider);align-items:center"
            @click="open(h.title_id)"
          >
            <img :src="h.cover_url" style="width:56px;height:78px;border-radius:8px;object-fit:cover;background:var(--bg-card)" />
            <div style="min-width:0">
              <div style="font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">{{ h.name }}</div>
              <div class="meta" style="margin-top:6px">{{ h.episode_no ? '看到第 ' + h.episode_no + ' 集' : '' }}</div>
            </div>
          </div>
        </div>
      </template>

      <template v-else>
        <div v-if="!appState.user" class="hint">
          <div>{{ t('login_required') }}</div>
          <button class="btn primary" style="margin-top:14px" @click="go('/login')">{{ t('login') }}</button>
        </div>
        <div v-else-if="!favorites.length" class="hint">{{ t('empty') }}</div>
        <div v-else class="grid">
          <PosterCard v-for="item in favorites" :key="item.title_id" :item="item" @open="(x) => open(x.title_id)" />
        </div>
      </template>
    </template>
  </div>
</template>
