// L10n.ets -- minimal multilingual dictionary (subset of the web i18n.js).
import { getString, putString } from '../store/AppStore';

export const LANG_ZH = 'zh-Hans';
export const LANG_EN = 'en';
export const SUPPORTED_LANGS: string[] = [LANG_ZH, LANG_EN];

let curLang: string = LANG_ZH;

const ZH: Record<string, string> = {
  'app_tagline': '短剧中文字幕 · 免费在线观看',
  'nav_home': '首页',
  'nav_search': '搜索',
  'nav_library': '我的',
  'search_hint': '搜索短剧…',
  'search_suggest': '搜索建议',
  'err_load': '加载失败',
  'err_network': '网络错误，请稍后重试',
  'retry': '重试',
  'see_all': '查看全部',
  'episodes': '剧集',
  'description': '简介',
  'tags': '标签',
  'favorite': '收藏',
  'favorited': '已收藏',
  'rate': '评分',
  'login': '登录',
  'logout': '退出登录',
  'login_required': '请先登录',
  'login_success': '登录成功',
  'history': '观看历史',
  'favorites': '我的收藏',
  'empty': '暂无内容',
  'loading': '加载中…',
  'episode_locked': '该集需要解锁',
  'continue_watch': '已为您续播',
  'next_ep': '下一集',
  'prev_ep': '上一集',
  'no_more': '没有更多了',
  'load_more': '加载更多',
  'lang_switch': '语言',
  'completed': '已完结',
  'ongoing': '连载中',
  'views': '播放',
  'subtitle': '字幕',
  'played_reported': '观看进度已同步',
  'mute': '静音',
  'unmute': '取消静音',
  'fullscreen': '全屏',
  'exit_full': '退出全屏',
  'play_failed': '播放失败',
  'player_fail': '视频加载失败（CDN 可能限制直链或当前网络不可达）',
  'ep_short': '第',
  'ep_prefix': '第',
  'ep_suffix': '集',
  'all_episodes': '全部剧集'
};

const EN: Record<string, string> = {
  'app_tagline': 'Short dramas, free online',
  'nav_home': 'Home',
  'nav_search': 'Search',
  'nav_library': 'Library',
  'search_hint': 'Search short dramas…',
  'search_suggest': 'Suggestions',
  'err_load': 'Failed to load',
  'err_network': 'Network error, please retry',
  'retry': 'Retry',
  'see_all': 'See all',
  'episodes': 'Episodes',
  'description': 'Description',
  'tags': 'Tags',
  'favorite': 'Favorite',
  'favorited': 'Favorited',
  'rate': 'Rate',
  'login': 'Sign in',
  'logout': 'Sign out',
  'login_required': 'Please sign in first',
  'login_success': 'Signed in',
  'history': 'Watch history',
  'favorites': 'Favorites',
  'empty': 'Nothing here yet',
  'loading': 'Loading…',
  'episode_locked': 'This episode is locked',
  'continue_watch': 'Resumed playback',
  'next_ep': 'Next',
  'prev_ep': 'Previous',
  'no_more': 'No more items',
  'load_more': 'Load more',
  'lang_switch': 'Language',
  'completed': 'Completed',
  'ongoing': 'Ongoing',
  'views': 'views',
  'subtitle': 'Subtitles',
  'played_reported': 'Progress synced',
  'mute': 'Mute',
  'unmute': 'Unmute',
  'fullscreen': 'Fullscreen',
  'exit_full': 'Exit full',
  'play_failed': 'Playback failed',
  'player_fail': 'Failed to load video (CDN may block direct links or network unreachable)',
  'ep_short': 'EP',
  'ep_prefix': 'EP',
  'ep_suffix': '',
  'all_episodes': 'All episodes'
};

export function dict(): Record<string, string> {
  return curLang === LANG_EN ? EN : ZH;
}

export function t(key: string): string {
  const d = dict();
  return d[key] ?? ZH[key] ?? key;
}

export function currentLang(): string {
  return curLang;
}

export async function loadLang(): Promise<void> {
  const l = await getString('dtv_lang', LANG_ZH);
  curLang = SUPPORTED_LANGS.indexOf(l) >= 0 ? l : LANG_ZH;
}

export async function setLang(l: string): Promise<void> {
  curLang = SUPPORTED_LANGS.indexOf(l) >= 0 ? l : LANG_ZH;
  await putString('dtv_lang', curLang);
}
