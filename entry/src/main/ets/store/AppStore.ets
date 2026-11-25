// AppStore.ets -- preferences-backed key/value store + global UIAbility context.
import { preferences } from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';

let gContext: common.UIAbilityContext | null = null;
let gPrefs: preferences.Preferences | null = null;
let gInitPromise: Promise<void> | null = null;

export function initAppStore(ctx: common.UIAbilityContext): void {
  gContext = ctx;
  if (!gInitPromise) {
    gInitPromise = preferences.getPreferences(ctx, { name: 'anyshort_store' })
      .then((p: preferences.Preferences) => {
        gPrefs = p;
      })
      .catch((e: Error) => {
        console.error('AppStore init failed: ' + e.message);
      });
  }
}

export function appContext(): common.UIAbilityContext {
  if (!gContext) {
    throw new Error('AppStore not initialized');
  }
  return gContext;
}

export async function storeReady(): Promise<void> {
  if (gInitPromise) {
    await gInitPromise;
  }
}

export async function getString(key: string, def: string): Promise<string> {
  await storeReady();
  if (!gPrefs) {
    return def;
  }
  try {
    const v = await gPrefs.get(key, def);
    return typeof v === 'string' ? v : def;
  } catch (e) {
    return def;
  }
}

export async function putString(key: string, val: string): Promise<void> {
  await storeReady();
  if (!gPrefs) {
    return;
  }
  try {
    await gPrefs.put(key, val);
    await gPrefs.flush();
  } catch (e) {
    console.error('putString ' + key + ' failed');
  }
}

// ---- watch progress for resume ("continue watching"), stored locally per title ----
export interface LocalProgress {
  ep: number;
  posMs: number;
  ts: number;
}

export async function getLocalProgress(titleId: number): Promise<LocalProgress | null> {
  const raw = await getString('t' + titleId, '');
  if (!raw) {
    return null;
  }
  try {
    const o = JSON.parse(raw) as LocalProgress;
    if (o && o.ep > 0) {
      return o;
    }
    return null;
  } catch (e) {
    return null;
  }
}

export async function saveLocalProgress(titleId: number, ep: number, posMs: number): Promise<void> {
  const p: LocalProgress = { ep: ep, posMs: Math.floor(posMs), ts: Date.now() };
  await putString('t' + titleId, JSON.stringify(p));
}
