// Models.ets -- data models mirroring the AnyShort /v1 public API envelopes.
// Verified against live API responses on 2026-11-25.

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

export interface Spotlight {
  mode?: string;
  tag_id?: number;
  items: TitleItem[];
}

export interface Rail {
  title: string;
  title_key?: string;
  kind: string;          // "auto" -> /browse?sort=..., "manual" -> /collections/{ref}
  ref: string;
  items: TitleItem[];
  next?: string;
}

export interface Banner {
  title: string;
  image_url: string;
  position?: string;
  link_type?: string;
  link_ref?: string;
}

export interface HomeData {
  spotlight: Spotlight;
  rails: Rail[];
  banners: Banner[];
  popular_sort?: string;
}

export interface TagItem {
  tag_id: number;
  name: string;
  slug: string;
}

export interface Gating {
  mode?: string;          // "free_all" | "free_n" | ...
  free_episodes?: number;
  coin_per_episode?: number;
}

export interface RatingInfo {
  avg?: number;
  count?: number;
}

export interface TitleDetail {
  title_id: number;
  name: string;
  slug: string;
  cover_url: string;
  orientation?: string;
  total_episodes?: number;
  is_completed?: boolean;
  view_count?: number;
  primary_language?: string;
  published_at?: string;
  description?: string;
  tags?: TagItem[];
  episode_count?: number;
  subtitle_languages?: string[];
  available_languages?: string[];
  gating?: Gating;
  rating?: RatingInfo;
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
  stale?: boolean;
}

export interface PlayData {
  episode_id: number;
  title_id: number;
  episode_no: number;
  source?: string;
  access?: string;
  sub_lang?: string;
  sub_langs?: string[];
  protocol?: string;
  selected?: StreamInfo;
  streams?: StreamInfo[];
}

export interface UserInfo {
  uid?: string;
  name?: string;
  email?: string;
  avatar_url?: string;
}

export interface SessionInfo {
  access_token: string;
  refresh_token?: string;
  expires_in?: number;
  device_id?: string;
  user?: UserInfo | null;
}

export interface PageMeta {
  limit?: number;
  has_more?: boolean;
  next?: string;
}

export interface TitlePage {
  data?: TitleItem[];
  page?: PageMeta;
}

export interface EpisodePage {
  data?: EpisodeItem[];
  page?: PageMeta;
}

export interface CollectionData {
  name?: string;
  items?: TitleItem[];
  next?: string;
}

export interface HistoryItem {
  title_id?: number;
  episode_id?: number;
  episode_no?: number;
  name?: string;
  slug?: string;
  cover_url?: string;
  updated_at?: string;
}

export interface HistoryPage {
  data?: HistoryItem[];
  page?: PageMeta;
}

export interface Envelope {
  data?: object;
  meta?: object;
  page?: object;
  error?: ErrBody;
}

export interface ErrBody {
  code?: string;
  message?: string;
}

// /v1/episodes/{id}/subtitles -> { data: SubtitleTrack[] }
export interface SubtitleTrack {
  lang?: string;
  language?: string;
  url?: string;
  vtt_url?: string;
  file?: string;
}

// One parsed WEBVTT cue used by the player overlay.
export interface SubCue {
  startMs: number;
  endMs: number;
  text: string;
}
