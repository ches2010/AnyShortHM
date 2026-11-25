<script setup lang="ts">
import type { TitleItem } from '../api';
import { fmtCount } from '../utils';

defineProps<{ item: TitleItem }>();
defineEmits<{ (e: 'open', item: TitleItem): void }>();
</script>

<template>
  <div class="card" @click="$emit('open', item)">
    <img class="poster" :src="item.cover_url" :alt="item.name" loading="lazy" />
    <div class="name">{{ item.name }}</div>
    <div class="meta">{{ fmtCount(item.view_count) }}{{ item.view_count ? ' 播放' : '' }}</div>
  </div>
</template>
