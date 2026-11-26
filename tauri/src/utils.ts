export function fmtCount(n?: number): string {
  if (!n || n <= 0) return '';
  if (n >= 100000000) return (n / 100000000).toFixed(1) + '亿';
  if (n >= 10000) return (n / 10000).toFixed(1) + '万';
  return String(n);
}

export function fmtTime(sec: number): string {
  if (!isFinite(sec) || sec < 0) sec = 0;
  const total = Math.floor(sec);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = m < 10 ? '0' + m : String(m);
  const ss = s < 10 ? '0' + s : String(s);
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

export interface SubCue { startMs: number; endMs: number; text: string }

export function parseVtt(text: string): SubCue[] {
  const cues: SubCue[] = [];
  const lines = text.split(/\r?\n/);
  let i = 0;
  const toMs = (s: string): number => {
    const m = /(\d+):(\d+):(\d+)[.,](\d+)/.exec(s.trim());
    if (!m) return 0;
    return Number(m[1]) * 3600000 + Number(m[2]) * 60000 + Number(m[3]) * 1000 + Number(m[4]);
  };
  while (i < lines.length) {
    const line = lines[i];
    const arrow = line.indexOf('-->');
    if (arrow > 0) {
      const startMs = toMs(line.slice(0, arrow));
      const endMs = toMs(line.slice(arrow + 3));
      i++;
      const buf: string[] = [];
      while (i < lines.length && lines[i].trim() !== '' && lines[i].indexOf('-->') < 0) {
        buf.push(lines[i].trim());
        i++;
      }
      if (buf.length) cues.push({ startMs, endMs, text: buf.join(' ') });
    } else {
      i++;
    }
  }
  return cues;
}
