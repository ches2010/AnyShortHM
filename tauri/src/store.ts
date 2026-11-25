import { reactive } from 'vue';

export interface LocalProgress {
  ep: number;
  posMs: number;
  ts: number;
}

export const appState = reactive({
  user: JSON.parse(localStorage.getItem('dtv_user') || 'null') as { name?: string; email?: string } | null,
  deviceId: localStorage.getItem('dtv_device') || ''
});

export function setUser(u: { name?: string; email?: string } | null): void {
  appState.user = u;
  if (u) {
    localStorage.setItem('dtv_user', JSON.stringify(u));
  } else {
    localStorage.removeItem('dtv_user');
  }
}

export function saveProgress(titleId: number, ep: number, posMs: number): void {
  if (!titleId || posMs < 3000) return;
  const p: LocalProgress = { ep, posMs: Math.floor(posMs), ts: Date.now() };
  localStorage.setItem('t' + titleId, JSON.stringify(p));
}

export function getProgress(titleId: number): LocalProgress | null {
  const raw = localStorage.getItem('t' + titleId);
  if (!raw) return null;
  try {
    const p = JSON.parse(raw) as LocalProgress;
    return p && p.ep > 0 ? p : null;
  } catch {
    return null;
  }
}
