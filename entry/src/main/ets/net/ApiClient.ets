// ApiClient.ets -- HTTP layer for the AnyShort /v1 API.
// Session handshake (JWT access token + device_id), transparent re-handshake on 401.
// Mirrors the web client (anyshort.net/api.js).
import { http } from '@kit.NetworkKit';
import { Envelope, SessionInfo } from '../model/Models';
import { getString, putString } from '../store/AppStore';

export const API_BASE = 'https://anyshort.net/v1';
export const WEB_BASE = 'https://anyshort.net';

let accessToken: string = '';
let handshaking: Promise<string> | null = null;

export function currentToken(): string {
  return accessToken;
}

export function clearSession(): void {
  accessToken = '';
}

type KV = Record<string, string>;

async function httpRaw(url: string, method: http.RequestMethod, body: string | null,
  withAuth: boolean): Promise<string> {
  const req = http.createHttp();
  try {
    const header: KV = { 'content-type': 'application/json' };
    if (withAuth && accessToken) {
      header['authorization'] = 'Bearer ' + accessToken;
    }
    const opt: http.HttpRequestOptions = {
      method: method,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    if (body !== null) {
      opt.extraData = body;
    }
    const resp = await req.request(url, opt);
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      const err = new Error('HTTP ' + resp.responseCode);
      err.name = 'HttpError';
      err.message = 'HTTP ' + resp.responseCode;
      throw err;
    }
    return resp.result as string;
  } finally {
    req.destroy();
  }
}

async function doHandshake(): Promise<string> {
  const dev = await getString('dtv_device', '');
  const bodyObj: KV = { 'platform': 'web' };
  if (dev !== '') {
    bodyObj['device_id'] = dev;
  }
  const raw = await httpRaw(API_BASE + '/auth/session', http.RequestMethod.POST,
    JSON.stringify(bodyObj), false);
  const env = JSON.parse(raw) as Envelope;
  const data = (env.data ?? {}) as SessionInfo;
  accessToken = data.access_token ?? '';
  if (data.device_id && data.device_id !== dev) {
    await putString('dtv_device', data.device_id);
  }
  if (data.user) {
    await putString('dtv_user', JSON.stringify(data.user));
  } else {
    await putString('dtv_user', '');
  }
  return accessToken;
}

export async function ensureSession(): Promise<void> {
  if (accessToken !== '') {
    return;
  }
  if (handshaking === null) {
    handshaking = doHandshake()
      .then((t: string) => {
        handshaking = null;
        return t;
      })
      .catch((e: Error) => {
        handshaking = null;
        throw e;
      });
  }
  await handshaking;
}

export async function apiRequest(path: string, method: http.RequestMethod,
  body: string | null): Promise<string> {
  await ensureSession();
  try {
    return await httpRaw(API_BASE + path, method, body, true);
  } catch (e) {
    const msg = (e as Error).message;
    if (msg.indexOf('401') >= 0) {
      // token expired -> re-handshake once and retry
      accessToken = '';
      await ensureSession();
      return await httpRaw(API_BASE + path, method, body, true);
    }
    throw e as Error;
  }
}

export async function apiGet(path: string): Promise<string> {
  return apiRequest(path, http.RequestMethod.GET, null);
}

export async function apiPost(path: string, bodyJson: string): Promise<string> {
  return apiRequest(path, http.RequestMethod.POST, bodyJson);
}

export async function apiPut(path: string, bodyJson: string): Promise<string> {
  return apiRequest(path, http.RequestMethod.PUT, bodyJson);
}

export async function apiDelete(path: string): Promise<string> {
  return apiRequest(path, http.RequestMethod.DELETE, null);
}
