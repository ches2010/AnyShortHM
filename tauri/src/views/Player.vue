<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { getText, isTauri } from '../http';
import { api, type PlayData, type EpisodeItem } from '../api';
import { t } from '../i18n';
import { route, back, goPlayer } from '../router';
import { appState, getProgress, saveProgress } from '../store';
import { fmtTime, parseVtt, type SubCue } from '../utils';

const episodeId = ref(Number(route.params.episodeId || 0));
const titleId = ref(Number(route.params.titleId || 0));
const titleName = ref(route.params.titleName || '');
const slug = ref(route.params.slug || '');
const currentEpNo = ref(Number(route.params.episodeNo || 1));

const videoEl = ref<HTMLVideoElement | null>(null);
const srcUrl = ref('');
const loading = ref(true);
const errMsg = ref('');
const playing = ref(false);
const posSec = ref(0);
const durationSec = ref(0);
const muted = ref(false);
const speed = ref(1);
const cue = ref('');
const isFullscreen = ref(false);

const qualities = ref<string[]>([]);
const curQuality = ref('');
const qualityUrls = ref<Map<string, string>>(new Map());
const candidates = ref<string[]>([]);
const candIndex = ref(0);
const episodes = ref<EpisodeItem[]>([]);
const showQuality = ref(false);
const showEpisodes = ref(false);

let cues: SubCue[] = [];
let reported = false;
let pendingSeekMs = 0;
let dragging = false;
const SPEEDS = [1, 1.25, 1.5, 2];

function buildCandidates(pd: PlayData): string[] {
  const out: string[] = [];
  const push = (u?: string): void => {
    if (u && out.indexOf(u) < 0) out.push(u);
  };
  push(pd.selected?.url);
  for (const s of pd.streams ?? []) if (s.codec === 'h264') push(s.url);
  for (const s of pd.streams ?? []) push(s.url);
  return out;
}

async function loadPlay(): Promise<void> {
  loading.value = true;
  errMsg.value = '';
  reported = false;
  try {
    const pd = await api.play(episodeId.value);
    const map = new Map<string, string>();
    for (const s of pd.streams ?? []) if (s.quality && s.codec === 'h264' && !map.has(s.quality)) map.set(s.quality, s.url);
    for (const s of pd.streams ?? []) if (s.quality && !map.has(s.quality)) map.set(s.quality, s.url);
    qualityUrls.value = map;
    qualities.value = [...map.keys()].sort((a, b) => parseInt(b) - parseInt(a));
    curQuality.value = pd.selected?.quality || qualities.value[0] || '';
    candidates.value = buildCandidates(pd);
    candIndex.value = 0;
    await playUrl(candidates.value[0]);
    void loadSubs();
  } catch (e) {
    errMsg.value = (e as Error).message;
    loading.value = false;
  }
}

async function playUrl(url: string): Promise<void> {
  if (!url) {
    errMsg.value = t('player_fail');
    loading.value = false;
    return;
  }
  srcUrl.value = url;
  await nextTick();
  const v = videoEl.value;
  if (v) {
    v.load();
    try {
      await v.play();
    } catch {
      /* 自动播放被拦截时等待用户点击 */
    }
  }
}

async function loadSubs(): Promise<void> {
  cues = [];
  cue.value = '';
  try {
    const tracks = await api.subtitles(episodeId.value);
    const url = tracks.map((x) => x.url || x.vtt_url || x.file || '').find((u) => !!u);
    if (!url) return;
    const text = await getText(url);
    cues = parseVtt(text);
  } catch (e) {
    if (!isTauri()) console.warn('[player] subtitle fetch failed (likely CORS):', e);
    cues = [];
  }
}

async function loadEpisodes(): Promise<void> {
  if (!titleId.value) return;
  try {
    const page = await api.episodes(titleId.value);
    episodes.value = page.data ?? [];
  } catch {
    episodes.value = [];
  }
}

function onLoadedMetadata(): void {
  const v = videoEl.value;
  if (!v) return;
  durationSec.value = v.duration || 0;
  loading.value = false;
  const resumeMs = pendingSeekMs > 0 ? pendingSeekMs : (getProgress(titleId.value)?.posMs ?? 0);
  if (resumeMs > 5000 && v.duration * 1000 > resumeMs + 5000) {
    v.currentTime = resumeMs / 1000;
    pendingSeekMs = 0;
  }
}

function onTimeUpdate(): void {
  const v = videoEl.value;
  if (!v) return;
  if (!dragging) posSec.value = v.currentTime;
  const ms = v.currentTime * 1000;
  if (cues.length) {
    const c = cues.find((x) => ms >= x.startMs && ms <= x.endMs);
    cue.value = c ? c.text : '';
  }
  if (!reported && ms > 10000) {
    reported = true;
    api.saveProgress(episodeId.value).catch(() => {});
  }
  saveProgress(titleId.value, currentEpNo.value, ms);
}

function onEnded(): void {
  playing.value = false;
  nextEp();
}

async function onError(): Promise<void> {
  const v = videoEl.value;
  const msg = v?.error?.message || '';
  if (candIndex.value + 1 < candidates.value.length) {
    candIndex.value += 1;
    await playUrl(candidates.value[candIndex.value]);
    return;
  }
  errMsg.value = msg || t('player_fail');
  loading.value = false;
}

function togglePlay(): void {
  const v = videoEl.value;
  if (!v) return;
  if (v.paused) {
    v.play().catch(() => {});
  } else {
    v.pause();
  }
}

function onPlayState(): void {
  const v = videoEl.value;
  if (v) playing.value = !v.paused;
}

function seekTo(sec: number): void {
  const v = videoEl.value;
  if (!v) return;
  v.currentTime = Math.max(0, Math.min(sec, durationSec.value || sec));
}

function seekBy(delta: number): void {
  seekTo((videoEl.value?.currentTime ?? 0) + delta);
}

function onSeekInput(e: Event): void {
  dragging = true;
  seekTo(Number((e.target as HTMLInputElement).value));
}

function onSeekChange(): void {
  dragging = false;
}

function toggleMute(): void {
  muted.value = !muted.value;
  const v = videoEl.value;
  if (v) v.muted = muted.value;
}

function cycleSpeed(): void {
  const idx = SPEEDS.findIndex((s) => Math.abs(s - speed.value) < 0.01);
  speed.value = SPEEDS[(idx + 1) % SPEEDS.length];
  const v = videoEl.value;
  if (v) v.playbackRate = speed.value;
}

function switchQuality(q: string): void {
  showQuality.value = false;
  if (q === curQuality.value) return;
  const url = qualityUrls.value.get(q);
  if (!url) return;
  const v = videoEl.value;
  pendingSeekMs = (v?.currentTime ?? 0) * 1000;
  curQuality.value = q;
  candidates.value = [url];
  candIndex.value = 0;
  void playUrl(url);
}

async function toggleFullscreen(): Promise<void> {
  const el = document.querySelector('.player-shell') as HTMLElement | null;
  if (!el) return;
  try {
    if (!document.fullscreenElement) {
      await el.requestFullscreen();
      isFullscreen.value = true;
    } else {
      await document.exitFullscreen();
      isFullscreen.value = false;
    }
  } catch {
    isFullscreen.value = !isFullscreen.value;
  }
}

function gotoEp(no: number): void {
  const ep = episodes.value.find((x) => x.episode_no === no);
  if (!ep) return;
  showEpisodes.value = false;
  goPlayer({
    episodeId: ep.episode_id,
    episodeNo: ep.episode_no,
    titleId: titleId.value,
    titleName: titleName.value,
    slug: slug.value
  });
}

function nextEp(): void {
  gotoEp(currentEpNo.value + 1);
}

function prevEp(): void {
  gotoEp(currentEpNo.value - 1);
}

const epLabel = computed(() => `${t('ep_short')}${currentEpNo.value}${t('ep_suffix')}`);

onMounted(() => {
  void loadPlay();
  void loadEpisodes();
});

onBeforeUnmount(() => {
  saveProgress(titleId.value, currentEpNo.value, (videoEl.value?.currentTime ?? 0) * 1000);
});
</script>

<template>
  <div class="player-shell">
    <div class="video-wrap">
      <video
        ref="videoEl"
        :src="srcUrl"
        playsinline
        webkit-playsinline
        preload="metadata"
        @loadedmetadata="onLoadedMetadata"
        @timeupdate="onTimeUpdate"
        @ended="onEnded"
        @error="onError"
        @play="onPlayState"
        @pause="onPlayState"
        @click="togglePlay"
      ></video>

      <div v-if="loading" class="center-play"><div class="play-big">···</div></div>

      <div v-if="errMsg" class="center-play">
        <div style="text-align:center;padding:0 24px">
          <div style="font-size:14px">{{ t('play_failed') }}</div>
          <div style="font-size:11px;opacity:.7;margin-top:6px">{{ errMsg }}</div>
          <button class="btn primary" style="margin-top:12px" @click="loadPlay">{{ t('retry') }}</button>
        </div>
      </div>

      <div v-if="cue" class="subtitle-line">{{ cue }}</div>

      <div class="video-layer">
        <div class="video-top">
          <span class="back" @click="back()">‹</span>
          <span class="title">{{ titleName }} · {{ epLabel }}</span>
          <button class="icon-btn" @click="toggleMute">{{ muted ? '🔇' : '🔊' }}</button>
          <button class="icon-btn" @click="toggleFullscreen">{{ isFullscreen ? '⤡' : '⤢' }}</button>
        </div>

        <div v-if="!playing && !loading && !errMsg" class="center-play">
          <div class="play-big" @click="togglePlay">▶</div>
        </div>

        <div class="video-spacer"></div>

        <div class="video-bottom">
          <input
            class="seek-bar"
            type="range"
            min="0"
            :max="durationSec || 1"
            step="0.5"
            :value="posSec"
            @input="onSeekInput"
            @change="onSeekChange"
          />
          <div class="time-row">
            <span>{{ fmtTime(posSec) }}</span>
            <span style="flex:1"></span>
            <button v-if="qualities.length" class="pill" @click="showQuality = true">{{ curQuality.toUpperCase() }}</button>
            <button class="pill" style="margin-left:8px" @click="cycleSpeed">{{ speed.toFixed(2) }}x</button>
            <span style="flex:1"></span>
            <span>{{ fmtTime(durationSec) }}</span>
          </div>
          <div class="ctrl-row">
            <button class="ctrl-btn" @click="prevEp">{{ t('prev_ep') }}</button>
            <button class="ctrl-btn" @click="seekBy(-10)">-10s</button>
            <div class="play-big" @click="togglePlay">{{ playing ? '❚❚' : '▶' }}</div>
            <button class="ctrl-btn" @click="seekBy(10)">+10s</button>
            <button class="ctrl-btn" @click="nextEp">{{ t('next_ep') }}</button>
          </div>
          <div style="text-align:center;margin-top:8px">
            <button class="btn ghost" style="font-size:12px" @click="showEpisodes = true">{{ t('all_episodes') }} ›</button>
          </div>
        </div>
      </div>
    </div>

    <div v-if="showQuality" class="sheet-mask" @click.self="showQuality = false">
      <div class="sheet">
        <div class="sheet-head">
          <h3>{{ t('quality') }}</h3>
          <span class="close" @click="showQuality = false">✕</span>
        </div>
        <div
          v-for="q in qualities"
          :key="q"
          class="sheet-row"
          :class="{ active: q === curQuality }"
          @click="switchQuality(q)"
        >
          {{ q.toUpperCase() }}
          <span v-if="q === curQuality" class="tick">✓</span>
        </div>
      </div>
    </div>

    <div v-if="showEpisodes" class="sheet-mask" @click.self="showEpisodes = false">
      <div class="sheet">
        <div class="sheet-head">
          <h3>{{ t('episodes') }}</h3>
          <span class="close" @click="showEpisodes = false">✕</span>
        </div>
        <div class="ep-grid" style="padding:0">
          <div
            v-for="ep in episodes"
            :key="ep.episode_id"
            class="ep-cell"
            :class="{ locked: ep.locked, current: ep.episode_no === currentEpNo }"
            @click="gotoEp(ep.episode_no)"
          >{{ ep.episode_no }}</div>
        </div>
      </div>
    </div>
  </div>
</template>
