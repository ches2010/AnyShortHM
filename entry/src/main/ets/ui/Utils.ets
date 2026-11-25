// Utils.ets -- small formatting helpers shared by views.
export function fmtCount(n?: number): string {
  if (!n || n <= 0) {
    return '';
  }
  if (n >= 100000000) {
    return (n / 100000000).toFixed(1) + '亿';
  }
  if (n >= 10000) {
    return (n / 10000).toFixed(1) + '万';
  }
  return String(n);
}

export function fmtTime(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = m < 10 ? '0' + m : String(m);
  const ss = s < 10 ? '0' + s : String(s);
  if (h > 0) {
    return h + ':' + mm + ':' + ss;
  }
  return mm + ':' + ss;
}
