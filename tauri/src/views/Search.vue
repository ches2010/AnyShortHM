<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { api, type TitleItem } from '../api';
import { t } from '../i18n';
import { go } from '../router';
import PosterCard from '../components/PosterCard.vue';

const query = ref('');
const results = ref<TitleItem[]>([]);
const loading = ref(false);
const searched = ref(false);
const hasMore = ref(false);
const errMsg = ref('');
let cursor = '';
let timer: number | undefined;

async function doSearch(reset: boolean): Promise<void> {
  const q = query.value.trim();
  if (!q) {
    results.value = [];
    searched.value = false;
    hasMore.value = false;
    return;
  }
  loading.value = true;
  errMsg.value = '';
  searched.value = true;
  try {
    const page = await api.search(q, reset ? '' : cursor);
    const items = page.data ?? [];
    results.value = reset ? items : results.value.concat(items);
    cursor = page.page?.next ?? '';
    hasMore.value = !!cursor;
  } catch (e) {
    errMsg.value = (e as Error).message;
  } finally {
    loading.value = false;
  }
}

function onInput(): void {
  if (timer) clearTimeout(timer);
  timer = window.setTimeout(() => void doSearch(true), 400);
}

function open(item: TitleItem): void {
  go(`/detail/${item.title_id}`);
}

onMounted(() => {
  if (query.value) void doSearch(true);
});
</script>

<template>
  <div>
    <div class="search-box">
      <input v-model="query" :placeholder="t('search_hint')" @input="onInput" @keyup.enter="doSearch(true)" />
    </div>

    <div v-if="!searched" class="hint">{{ t('search_hint') }}</div>

    <template v-else>
      <div v-if="errMsg" class="hint">{{ errMsg }}</div>
      <div v-else-if="results.length === 0 && !loading" class="hint">{{ t('empty') }}</div>
      <div class="grid">
        <PosterCard v-for="item in results" :key="item.title_id" :item="item" @open="open" />
      </div>
      <div v-if="loading" class="hint">{{ t('loading') }}</div>
      <div v-else-if="hasMore" style="text-align:center;padding-bottom:18px">
        <button class="btn" @click="doSearch(false)">{{ t('load_more') }}</button>
      </div>
      <div v-else-if="results.length" class="hint" style="padding:12px">{{ t('no_more') }}</div>
    </template>
  </div>
</template>
