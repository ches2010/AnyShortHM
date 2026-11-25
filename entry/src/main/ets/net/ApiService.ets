// ApiService.ets -- typed wrappers for every /v1 endpoint used by the app.
import { http } from '@kit.NetworkKit';
import {
  HomeData, TitleDetail, TitleItem, EpisodeItem, PlayData, TitlePage, EpisodePage,
  CollectionData, HistoryPage, SubtitleTrack, Envelope
} from '../model/Models';
import { apiGet, apiPost, apiPut, apiDelete } from './ApiClient';

interface EmptyObj {}

const EMPTY_OBJ: EmptyObj = {};

function dataOf(raw: string): object {
  const env = JSON.parse(raw) as Envelope;
  return env.data ?? EMPTY_OBJ;
}

function arrayOf(raw: string): object[] {
  const env = JSON.parse(raw) as Envelope;
  return (env.data ?? []) as object[];
}

function pageOf(raw: string): Envelope {
  return JSON.parse(raw) as Envelope;
}

export class ApiService {
  static async home(lang: string): Promise<HomeData> {
    return dataOf(await apiGet('/home?lang=' + lang)) as HomeData;
  }

  static async browse(sort: string, lang: string, cursor: string, limit: number): Promise<TitlePage> {
    let p = '/browse?sort=' + sort + '&lang=' + lang + '&limit=' + limit;
    if (cursor !== '') {
      p += '&cursor=' + encodeURIComponent(cursor);
    }
    return pageOf(await apiGet(p)) as TitlePage;
  }

  static async search(q: string, lang: string, cursor: string, limit: number): Promise<TitlePage> {
    let p = '/search?q=' + encodeURIComponent(q) + '&lang=' + lang + '&limit=' + limit;
    if (cursor !== '') {
      p += '&cursor=' + encodeURIComponent(cursor);
    }
    return pageOf(await apiGet(p)) as TitlePage;
  }

  static async suggest(q: string, lang: string): Promise<string[]> {
    const arr = arrayOf(await apiGet('/suggest?q=' + encodeURIComponent(q) + '&lang=' + lang));
    const out: string[] = [];
    for (const it of arr) {
      const s = it as Record<string, string>;
      if (s['q'] ?? s['text'] ?? s['name']) {
        out.push(s['q'] ?? s['text'] ?? s['name']);
      }
    }
    return out;
  }

  static async title(id: number, lang: string): Promise<TitleDetail> {
    return dataOf(await apiGet('/titles/' + id + '?lang=' + lang)) as TitleDetail;
  }

  static async episodes(id: number, lang: string, cursor: string, limit: number): Promise<EpisodePage> {
    let p = '/titles/' + id + '/episodes?lang=' + lang + '&limit=' + limit;
    if (cursor !== '') {
      p += '&cursor=' + encodeURIComponent(cursor);
    }
    return pageOf(await apiGet(p)) as EpisodePage;
  }

  static async play(episodeId: number, lang: string, subLang: string): Promise<PlayData> {
    let p = '/episodes/' + episodeId + '/play?lang=' + lang;
    if (subLang !== '') {
      p += '&sub_lang=' + encodeURIComponent(subLang);
    }
    return dataOf(await apiGet(p)) as PlayData;
  }

  static async subtitles(episodeId: number, lang: string): Promise<SubtitleTrack[]> {
    const arr = arrayOf(await apiGet('/episodes/' + episodeId + '/subtitles?lang=' + lang));
    return arr as SubtitleTrack[];
  }

  static async saveProgress(episodeId: number): Promise<void> {
    await apiPost('/watch/progress', JSON.stringify({ episode_id: episodeId }));
  }

  static async history(lang: string, cursor: string, limit: number): Promise<HistoryPage> {
    let p = '/history?lang=' + lang + '&limit=' + limit;
    if (cursor !== '') {
      p += '&cursor=' + encodeURIComponent(cursor);
    }
    return pageOf(await apiGet(p)) as HistoryPage;
  }

  static async favorites(lang: string, cursor: string, limit: number): Promise<TitlePage> {
    let p = '/favorites?lang=' + lang + '&limit=' + limit;
    if (cursor !== '') {
      p += '&cursor=' + encodeURIComponent(cursor);
    }
    return pageOf(await apiGet(p)) as TitlePage;
  }

  static async addFavorite(titleId: number): Promise<void> {
    await apiPost('/favorites', JSON.stringify({ title_id: titleId }));
  }

  static async removeFavorite(titleId: number): Promise<void> {
    await apiDelete('/favorites/' + titleId);
  }

  static async rate(titleId: number, score: number): Promise<void> {
    await apiPut('/titles/' + titleId + '/rating', JSON.stringify({ score: score }));
  }

  static async collection(cid: string, lang: string, cursor: string, limit: number): Promise<CollectionData> {
    let p = '/collections/' + cid + '?lang=' + lang + '&limit=' + limit;
    if (cursor !== '') {
      p += '&cursor=' + encodeURIComponent(cursor);
    }
    return dataOf(await apiGet(p)) as CollectionData;
  }

  static async titlesByIds(ids: number[], lang: string): Promise<TitleItem[]> {
    if (ids.length === 0) {
      return [];
    }
    const arr = arrayOf(await apiGet('/watch/progress?title_ids=' + ids.join(',') + '&lang=' + lang));
    return arr as TitleItem[];
  }
}
