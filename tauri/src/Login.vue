<script setup lang="ts">
import { ref } from 'vue';
import { loginUrl, clearSession, ensureSession } from '../api';
import { t } from '../i18n';
import { appState } from '../store';
import { back, go } from '../router';

const status = ref('');

async function openBrowser(): Promise<void> {
  status.value = '';
  try {
    // Tauri WebView 内打开外部页面：交给系统浏览器/新窗口
    const w = window.open(loginUrl(), '_blank');
    if (!w) status.value = '请长按复制链接到浏览器打开';
  } catch {
    status.value = loginUrl();
  }
}

async function refresh(): Promise<void> {
  status.value = t('loading');
  try {
    clearSession();
    await ensureSession();
    status.value = appState.user ? t('login_success') : t('login_required');
  } catch (e) {
    status.value = (e as Error).message;
  }
}

function copyUrl(): void {
  navigator.clipboard?.writeText(loginUrl()).then(
    () => (status.value = '链接已复制'),
    () => (status.value = loginUrl())
  );
}
</script>

<template>
  <div>
    <div style="padding:10px 14px">
      <button class="btn ghost" @click="back()">‹ 返回</button>
    </div>

    <div class="centered">
      <div style="font-size:16px;font-weight:700">{{ t('login') }}</div>
      <p style="color:var(--text-dim);font-size:13px;line-height:1.8;text-align:center">
        使用 Google 账号登录，登录后可在「我的」中同步收藏与观看历史。
      </p>
      <button class="btn primary" style="width:220px" @click="openBrowser">{{ t('login') }}（Google）</button>
      <button class="btn" style="width:220px" @click="refresh">我已完成登录，刷新状态</button>
      <button class="btn ghost" style="width:220px" @click="copyUrl">复制登录链接</button>
      <div v-if="status" class="hint" style="padding:8px">{{ status }}</div>
      <div v-if="appState.user" style="font-size:12px;color:var(--accent)">
        当前账号：{{ appState.user.name || appState.user.email || '已登录' }}
      </div>
      <button class="btn ghost" style="width:220px;margin-top:6px" @click="go('/library')">返回我的</button>
    </div>
  </div>
</template>
