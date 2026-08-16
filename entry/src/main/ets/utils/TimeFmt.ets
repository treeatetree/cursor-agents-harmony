export function relativeTime(iso: string): string {
  if (!iso || iso.length === 0) {
    return '';
  }
  const t = Date.parse(iso);
  if (isNaN(t)) {
    return '';
  }
  const diff = Date.now() - t;
  const sec = Math.floor(diff / 1000);
  if (sec < 60) {
    return '刚刚';
  }
  const min = Math.floor(sec / 60);
  if (min < 60) {
    return `${min} 分钟前`;
  }
  const hr = Math.floor(min / 60);
  if (hr < 24) {
    return `${hr} 小时前`;
  }
  const day = Math.floor(hr / 24);
  if (day < 30) {
    return `${day} 天前`;
  }
  return iso.substring(0, 10);
}

export function shortRepo(url: string): string {
  if (!url) {
    return '';
  }
  // https://github.com/owner/repo.git → owner/repo
  const cleaned = url.replace(/\.git$/, '').replace(/\/$/, '');
  const parts = cleaned.split('/');
  if (parts.length >= 2) {
    return `${parts[parts.length - 2]}/${parts[parts.length - 1]}`;
  }
  return cleaned;
}
