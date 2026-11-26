<script setup lang="ts">
import { onMounted, ref, watch } from 'vue';
import { api, type TitleDetail, type EpisodeItem } from '../api';
import { t } from '../i18n';
import { route, back, goPlayer, go } from '../router';
import { appState } from '../store';
import { fmtCount } from '../utils';

const loading = ref(true);
const errMsg = ref('');
const detail = ref<TitleDetail | null>(null);
const episodes = ref<EpisodeItem[]>([]);
const isFav = ref(false);
const myRating = ref(0);

const titleId = () => Number(route.params.id || 0);

async function load(): Promise<void> {
  const id = titleId();
  if (!id) return;
  loading.value = true;
  errMsg.value = '';
  try {
    const d = await api.title(id);
    detail.value = d;
    isFav.value = !!d.is_favorite;
    myRating.value = d.my_rating ?? 0;
    const page = await api.episodes(id);
    episodes.value = page.data ?? [];
  } catch (e) {
    errMsg.value = (e as Error).message;
  } finally {
    loading.value = false;
  }
}

async function toggleFav(): Promise<void> {
  if (!appState.user) {
    go('/login');
    return;
  }
  try {
    if (isFav.value) {
      await api.removeFavorite(titleId());
      isFav.value = false;
    } else {
      await api.addFavorite(titleId());
      isFav.value = true;
    }
  } catch (e) {
    errMsg.value = (e as Error).message;
  }
}

async function rate(score: number): Promise<void> {
  if (!appState.user) {
    go('/login');
    return;
  }
  try {
    await api.rate(titleId(), score);
    myRating.value = score;
  } catch (e) {
    errMsg.value = (e as Error).message;
  }
}

function play(ep: EpisodeItem): void {
  if (ep.locked) return;
  const d = detail.value;
  goPlayer({
    episodeId: ep.episode_id,
    episodeNo: ep.episode_no,
    titleId: titleId(),
    titleName: d?.name ?? '',
    slug: d?.slug ?? ''
  });
}

onMounted(load);
watch(() => route.params.id, load);
</script>

<template>
  <div>
    <div style="padding:10px 14px">
      <button class="btn ghost" @click="back()">‹ 返回</button>
    </div>

    <div v-if="loading" class="hint">{{ t('loading') }}</div>
    <div v-else-if="errMsg" class="hint">{{ errMsg }}</div>

    <template v-else-if="detail">
      <div class="detail-head">
        <img class="poster" :src="detail.cover_url" :alt="detail.name" />
        <div style="min-width:0">
          <h2>{{ detail.name }}</h2>
          <div class="detail-meta">
            {{ detail.episode_count ?? 0 }} 集 ·
            {{ detail.is_completed ? t('completed') : t('ongoing') }}
            <span v-if="detail.view_count"> · {{ fmtCount(detail.view_count) }} {{ t('views') }}</span>
            <span v-if="detail.rating?.count"> · ★ {{ detail.rating?.avg }}</span>
          </div>
          <div class="tag-row">
            <span v-for="tag in detail.tags ?? []" :key="tag.tag_id" class="tag">{{ tag.name }}</span>
          </div>
        </div>
      </div>

      <div class="actions">
        <button class="btn" @click="toggleFav">
          {{ isFav ? '♥ ' + t('favorited') : '♡ ' + t('favorite') }}
        </button>
        <button
          v-for="s in [1, 2, 3, 4, 5]"
          :key="s"
          class="btn"
          :style="{ color: s <= myRating ? '#ffc53d' : 'var(--text-dim)' }"
          @click="rate(s)"
        >★</button>
      </div>

      <div v-if="detail.description">
        <div class="section-title"><h3>{{ t('description') }}</h3></div>
        <p class="desc">{{ detail.description }}</p>
      </div>

      <div class="section-title"><h3>{{ t('episodes') }}（{{ episodes.length }}）</h3></div>
      <div class="ep-grid">
        <div
          v-for="ep in episodes"
          :key="ep.episode_id"
          class="ep-cell"
          :class="{ locked: ep.locked }"
          @click="play(ep)"
        >{{ ep.locked ? '🔒' + ep.episode_no : ep.episode_no }}</div>
      </div>
    </template>
  </div>
</template>
