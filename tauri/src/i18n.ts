import { reactive } from 'vue';

export type Lang = 'zh-Hans' | 'en';

const ZH: Record<string, string> = {
  nav_home: '首页',
  nav_search: '搜索',
  nav_library: '我的',
  app_tagline: '短剧中文字幕 · 免费在线观看',
  search_hint: '搜索短剧…',
  loading: '加载中…',
  empty: '暂无内容',
  retry: '重试',
  err_load: '加载失败',
  err_network: '网络错误，请稍后重试',
  see_all: '查看全部',
  episodes: '剧集',
  all_episodes: '全部剧集',
  description: '简介',
  favorite: '收藏',
  favorited: '已收藏',
  rate: '评分',
  login: '登录',
  login_required: '请先登录',
  login_success: '登录成功',
  history: '观看历史',
  favorites: '我的收藏',
  quality: '清晰度',
  speed: '倍速',
  play_failed: '播放失败',
  player_fail: '视频加载失败（CDN 可能限制直链或网络不可达）',
  continue_watch: '已为您续播',
  next_ep: '下一集',
  prev_ep: '上一集',
  mute: '静音',
  unmute: '取消声音',
  fullscreen: '全屏',
  exit_full: '退出全屏',
  completed: '已完结',
  ongoing: '连载中',
  views: '播放',
  ep_short: '第',
  ep_prefix: '第',
  ep_suffix: '集',
  no_more: '没有更多了',
  load_more: '加载更多',
  subtitle: '字幕'
};

const EN: Record<string, string> = {
  nav_home: 'Home',
  nav_search: 'Search',
  nav_library: 'Library',
  app_tagline: 'Short dramas, free online',
  search_hint: 'Search short dramas…',
  loading: 'Loading…',
  empty: 'Nothing here yet',
  retry: 'Retry',
  err_load: 'Failed to load',
  err_network: 'Network error, please retry',
  see_all: 'See all',
  episodes: 'Episodes',
  all_episodes: 'All episodes',
  description: 'Description',
  favorite: 'Favorite',
  favorited: 'Favorited',
  rate: 'Rate',
  login: 'Sign in',
  login_required: 'Please sign in first',
  login_success: 'Signed in',
  history: 'Watch history',
  favorites: 'Favorites',
  quality: 'Quality',
  speed: 'Speed',
  play_failed: 'Playback failed',
  player_fail: 'Failed to load video (CDN may block direct links or network unreachable)',
  continue_watch: 'Resumed playback',
  next_ep: 'Next',
  prev_ep: 'Previous',
  mute: 'Mute',
  unmute: 'Unmute',
  fullscreen: 'Fullscreen',
  exit_full: 'Exit full',
  completed: 'Completed',
  ongoing: 'Ongoing',
  views: 'views',
  ep_short: 'EP',
  ep_prefix: 'EP',
  ep_suffix: '',
  no_more: 'No more items',
  load_more: 'Load more',
  subtitle: 'Subtitles'
};

export const i18nState = reactive<{ lang: Lang }>({
  lang: (localStorage.getItem('dtv_lang') as Lang) || 'zh-Hans'
});

export function t(key: string): string {
  const dict = i18nState.lang === 'en' ? EN : ZH;
  return dict[key] ?? ZH[key] ?? key;
}

export function setLang(l: Lang): void {
  i18nState.lang = l;
  localStorage.setItem('dtv_lang', l);
}

export function toggleLang(): void {
  setLang(i18nState.lang === 'zh-Hans' ? 'en' : 'zh-Hans');
}
