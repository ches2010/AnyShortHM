import { reactive } from 'vue';

export interface Route {
  name: string;
  params: Record<string, string>;
}

function parse(): Route {
  const h = location.hash.replace(/^#/, '') || '/home';
  const [pathPart, queryPart] = h.split('?');
  const segs = pathPart.split('/').filter(Boolean);
  const params: Record<string, string> = {};
  if (queryPart) {
    for (const kv of queryPart.split('&')) {
      const [k, v] = kv.split('=');
      if (k) params[decodeURIComponent(k)] = decodeURIComponent(v ?? '');
    }
  }
  const name = segs[0] || 'home';
  if (name === 'detail' && segs[1]) params.id = segs[1];
  if (name === 'player') {
    if (segs[1]) params.episodeId = segs[1];
  }
  return { name, params };
}

export const route = reactive<Route>(parse());

window.addEventListener('hashchange', () => {
  const r = parse();
  route.name = r.name;
  route.params = r.params;
});

export function go(path: string): void {
  if (location.hash === '#' + path) return;
  location.hash = path;
}

export function back(): void {
  if (history.length > 1) {
    history.back();
  } else {
    go('/home');
  }
}

export function goPlayer(params: { episodeId: number; episodeNo: number; titleId: number; titleName: string; slug: string }): void {
  const q = new URLSearchParams({
    episodeNo: String(params.episodeNo),
    titleId: String(params.titleId),
    titleName: params.titleName,
    slug: params.slug
  });
  go(`/player/${params.episodeId}?${q.toString()}`);
}
