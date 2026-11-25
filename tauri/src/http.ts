// 统一的 HTTP 入口：让同一份前端产物既能跑 Nova Tauri 壳，也能跑纯 WebView 壳（ArkWeb）。
//
// - Tauri 环境：走 @tauri-apps/plugin-http，由 Rust 侧发请求，不受浏览器 CORS 限制
// - 纯 WebView / 浏览器：走平台原生 fetch，受 CORS 约束
//
// 探测用 `__TAURI_INTERNALS__` 判断，而不是静态 import（@tauri-apps/api 的 isTauri 在 2.x 各小版本里
// 名字有变化，且静态 import 在纯 WebView 下会因缺少注入对象而在模块求值期就抛错）。

export interface Resp {
  ok: boolean;
  status: number;
  json(): Promise<any>;
  text(): Promise<string>;
}

type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

let impl: FetchLike | null = null;
let loading: Promise<FetchLike> | null = null;

export function isTauri(): boolean {
  const w = globalThis as unknown as Record<string, unknown>;
  return typeof w.__TAURI_INTERNALS__ === 'object' || typeof w.__TAURI__ === 'object';
}

function nativeFetch(): FetchLike {
  return (input: string, init?: RequestInit) => fetch(input, init);
}

/** 解析可用的 fetch 实现：Tauri 下动态加载插件，失败则退回原生 fetch。 */
export async function getFetch(): Promise<FetchLike> {
  if (impl) return impl;
  if (!isTauri()) {
    impl = nativeFetch();
    return impl;
  }
  if (!loading) {
    loading = import('@tauri-apps/plugin-http')
      .then((m) => {
        console.info('[http] using tauri-plugin-http');
        return m.fetch as unknown as FetchLike;
      })
      .catch((e: unknown) => {
        // 插件缺失或 capability 未授权：退回原生 fetch，并明确告警（此时大概率会被 CORS 拦）
        console.warn('[http] tauri plugin-http unavailable, falling back to native fetch:', e);
        return nativeFetch();
      });
  }
  const f = await loading;
  impl = f;
  return f;
}

export interface HttpOpts {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  /** 非 Tauri 环境下是否携带 Cookie（跨域请求需要服务端支持） */
  credentials?: RequestCredentials;
}

/** 发请求并归一化成 Resp，屏蔽插件返回与原生 Response 的结构差异。 */
export async function request(url: string, opts: HttpOpts = {}): Promise<Resp> {
  const f = await getFetch();
  const init: RequestInit = {
    method: opts.method || 'GET',
    headers: opts.headers
  };
  if (opts.body !== undefined) init.body = opts.body;
  if (!isTauri() && opts.credentials) init.credentials = opts.credentials;

  const res = await f(url, init);
  return {
    ok: res.ok,
    status: res.status,
    json: () => res.json(),
    text: () => res.text()
  };
}

/** 取文本：优先 Tauri 插件，其次原生 fetch（用于字幕等非 JSON 资源）。 */
export async function getText(url: string, headers?: Record<string, string>): Promise<string> {
  const r = await request(url, { method: 'GET', headers });
  return r.text();
}
