<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { api, type HomeData, type TitleItem, type Rail } from '../api';
import { t } from '../i18n';
import { go } from '../router';
import PosterCard from '../components/PosterCard.vue';
import { fmtCount } from '../utils';

const loading = ref(true);
const errMsg = ref('');
const home = ref<HomeData | null>(null);
const refreshing = ref(false);

async function load(): Promise<void> {
  loading.value = true;
  errMsg.value = '';
  try {
    home.value = await api.home();
  } catch (e) {
    errMsg.value = (e as Error).message;
  } finally {
    loading.value = false;
    refreshing.value = false;
  }
}

function open(item: TitleItem): void {
  go(`/detail/${item.title_id}`);
}

function openList(rail: Rail): void {
  go(`/list/${rail.kind}/${rail.ref}?title=${encodeURIComponent(rail.title)}`);
}

onMounted(load);
</script>

<template>
  <div>
    <div v-if="loading" class="centered"><div>{{ t('loading') }}</div></div>

    <div v-else-if="errMsg" class="centered">
      <div>{{ t('err_load') }}</div>
      <div class="hint" style="padding:0">{{ errMsg }}</div>
      <button class="btn primary" @click="load">{{ t('retry') }}</button>
    </div>

    <template v-else-if="home">
      <section v-if="home.spotlight?.items?.length">
        <div class="section-title"><h3>热门推荐</h3></div>
        <div class="rail">
          <div
            v-for="item in home.spotlight.items"
            :key="'sp' + item.title_id"
            style="width:168px;flex:none"
            @click="open(item)"
          >
            <img class="poster" :src="item.cover_url" :alt="item.name" style="width:168px;height:238px" />
            <div class="name" style="width:168px">{{ item.name }}</div>
            <div class="meta">{{ fmtCount(item.view_count) }} 播放 · {{ item.total_episodes }} 集</div>
          </div>
        </div>
      </section>

      <section v-for="rail in home.rails" :key="rail.kind + rail.ref">
        <div class="section-title">
          <h3>{{ rail.title }}</h3>
          <span class="more" @click="openList(rail)">{{ t('see_all') }} ›</span>
        </div>
        <div class="rail">
          <div v-for="item in rail.items" :key="rail.ref + '-' + item.title_id" style="width:106px;flex:none">
            <PosterCard :item="item" @open="open" />
          </div>
        </div>
      </section>

      <div class="hint" style="padding:20px">数据来自 anyshort.net</div>
    </template>
  </div>
</template>
