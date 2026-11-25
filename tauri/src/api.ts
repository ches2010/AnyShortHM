import { request } from './http';
import { i18nState } from './i18n';
import { appState, setUser } from './store';

export const API_BASE = 'https://anyshort.net/v1';
export const WEB_BASE = 'https://anyshort.net';

let token = '';
let handshaking: Promise<string> | null = null;

export interface TitleItem {
  title_id: number;
  name: string;
  slug: string;
  cover_url: string;
  source?: string;
  orientation?: string;
  total_episodes?: number;
  is_completed?: boolean;
  view_count?: number;
  primary_language?: string;
}

export interface Rail {
  title: string;
  title_key?: string;
  kind: string;
  ref: string;
  items: TitleItem[];
  next?: string;
}

export interface HomeData {
  spotlight: { items: TitleItem[] };
  rails: Rail[];
  banners: { title: string; image_url: string; position?: string; link_type?: string; link_ref?: string }[];
}

export interface TagItem { tag_id: number; name: string; slug: string }

export interface TitleDetail extends TitleItem {
  description?: string;
  tags?: TagItem[];
  episode_count?: number;
  subtitle_languages?: string[];
  gating?: { mode?: string; free_episodes?: number; coin_per_episode?: number };
  rating?: { avg?: number; count?: number };
  is_favorite?: boolean;
  my_rating?: number;
}

export interface EpisodeItem {
  episode_id: number;
  episode_no: number;
  has_streams?: boolean;
  access?: string;
  locked?: boolean;
  unlock_cost?: number;
}

export interface StreamInfo {
  quality?: string;
  codec?: string;
  protocol?: string;
  width?: number;
  height?: number;
  url: string;
  expire_at?: string;
}

export interface PlayData {
  episode_id: number;
  title_id: number;
  episode_no: number;
  selected?: StreamInfo;
  streams?: StreamInfo[];
  sub_lang?: string;
  sub_langs?: string[];
}

export interface PageMeta { limit?: number; has_more?: boolean; next?: string }
export interface TitlePage { data?: TitleItem[]; page?: PageMeta }
export interface EpisodePage { data?: EpisodeItem[]; page?: PageMeta }

function lang(): string {
  return i18nState.lang;
}

async function handshake(): Promise<string> {
  const dev = appState.deviceId;
  const body: Record<string, string> = { platform: 'web' };
  if (dev) body.device_id = dev;
  const res = await request(API_BASE + '/auth/session', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) throw new Error('session ' + res.status);
  const j = await res.json();
  token = j.data.access_token as string;
  if (j.data.device_id) {
    appState.deviceId = j.data.device_id;
    localStorage.setItem('dtv_device', j.data.device_id);
  }
  setUser(j.data.user ?? null);
  return token;
}

export async function ensureSession(): Promise<void> {
  if (token) return;
  if (!handshaking) {
    handshaking = handshake().finally(() => { handshaking = null; });
  }
  await handshaking;
}

export function clearSession(): void {
  token = '';
  setUser(null);
}

async function req<T>(path: string, method = 'GET', body?: unknown): Promise<T> {
  await ensureSession();
  const headers: Record<string, string> = { authorization: 'Bearer ' + token };
  if (body !== undefined) headers['content-type'] = 'application/json';
  let res = await request(API_BASE + path, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined
  });
  if (res.status === 401) {
    token = '';
    await ensureSession();
    res = await request(API_BASE + path, {
      method,
      headers: { authorization: 'Bearer ' + token, ...(body !== undefined ? { 'content-type': 'application/json' } : {}) },
      body: body !== undefined ? JSON.stringify(body) : undefined
    });
  }
  const j = await res.json();
  if (!res.ok) {
    const e = new Error((j?.error?.message as string) || 'HTTP ' + res.status);
    (e as Error & { status?: number }).status = res.status;
    throw e;
  }
  return j as T;
}

const d = <T>(p: Promise<{ data: T }>) => p.then((j) => j.data);

export const api = {
  home: () => d(req<{ data: HomeData }>(`/home?lang=${lang()}`)),
  browse: (sort: string, cursor = '', limit = 18) =>
    req<TitlePage>(`/browse?sort=${sort}&lang=${lang()}&limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`),
  search: (q: string, cursor = '', limit = 20) =>
    req<TitlePage>(`/search?q=${encodeURIComponent(q)}&lang=${lang()}&limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`),
  title: (id: number) => d(req<{ data: TitleDetail }>(`/titles/${id}?lang=${lang()}`)),
  episodes: (id: number, cursor = '', limit = 200) =>
    req<EpisodePage>(`/titles/${id}/episodes?lang=${lang()}&limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`),
  play: (episodeId: number) => d(req<{ data: PlayData }>(`/episodes/${episodeId}/play?lang=${lang()}`)),
  subtitles: (episodeId: number) =>
    d(req<{ data: { url?: string; vtt_url?: string; file?: string }[] }>(`/episodes/${episodeId}/subtitles?lang=${lang()}`)),
  saveProgress: (episodeId: number) => req<unknown>('/watch/progress', 'POST', { episode_id: episodeId }),
  history: (cursor = '', limit = 24) =>
    req<{ data: { title_id?: number; episode_no?: number; name?: string; slug?: string; cover_url?: string }[]; page?: PageMeta }>(
      `/history?lang=${lang()}&limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`
    ),
  favorites: (cursor = '', limit = 24) =>
    req<TitlePage>(`/favorites?lang=${lang()}&limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`),
  addFavorite: (titleId: number) => req<unknown>('/favorites', 'POST', { title_id: titleId }),
  removeFavorite: (titleId: number) => req<unknown>(`/favorites/${titleId}`, 'DELETE'),
  rate: (titleId: number, score: number) => req<unknown>(`/titles/${titleId}/rating`, 'PUT', { score })
};

export function loginUrl(): string {
  return `${API_BASE}/auth/google/start?next=${encodeURIComponent('/' + lang() + '/')}`;
}
