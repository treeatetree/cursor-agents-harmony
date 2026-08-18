export function repoTail(url: string): string {
  const full = shortRepoName(url);
  const i = full.lastIndexOf('/');
  return i >= 0 ? full.substring(i + 1) : full;
}

export function elapsedLabel(totalSec: number): string {
  if (totalSec < 60) {
    return `${totalSec}s`;
  }
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  if (min < 60) {
    return sec > 0 ? `${min}m ${sec < 10 ? '0' : ''}${sec}s` : `${min}m`;
  }
  const hr = Math.floor(min / 60);
  const rem = min % 60;
  return rem > 0 ? `${hr}h ${rem}m` : `${hr}h`;
}

export function elapsedSince(iso: string): string {
  if (!iso || iso.length === 0) {
    return '';
  }
  const t = Date.parse(iso);
  if (isNaN(t)) {
    return '';
  }
  const sec = Math.max(0, Math.floor((Date.now() - t) / 1000));
  return elapsedLabel(sec);
}

export function shortRepoName(url: string): string {
  if (!url) {
    return '';
  }
  const cleaned = url.replace(/\.git$/, '').replace(/\/$/, '');
  const parts = cleaned.split('/');
  if (parts.length >= 2) {
    return `${parts[parts.length - 2]}/${parts[parts.length - 1]}`;
  }
  return cleaned;
}

/** Case-insensitive owner/name, so inbox URL and API repository collapse. */
export function repoIdentity(url: string): string {
  return shortRepoName(url ?? '').toLowerCase();
}

/** Shorten opaque agent ids for list rows. */
export function shortAgentId(id: string): string {
  if (!id || id.length <= 14) {
    return id;
  }
  return `${id.substring(0, 8)}…${id.substring(id.length - 4)}`;
}

/** Format token usage for humans. Includes charged cost when present. */
export function formatUsageFriendly(raw: object): string {
  try {
    const r = raw as Record<string, Object>;
    const total = r['totalUsage'] as Record<string, Object> | undefined;
    if (!total) {
      return '';
    }
    const bits: string[] = [];
    const map: Array<[string, string]> = [
      ['inputTokens', '输入'],
      ['outputTokens', '输出'],
      ['cacheReadTokens', '缓存读'],
      ['cacheWriteTokens', '缓存写']
    ];
    for (let i = 0; i < map.length; i++) {
      const key = map[i][0];
      const label = map[i][1];
      if (total[key] !== undefined && total[key] !== null) {
        bits.push(`${label} ${formatTokenCount(Number(total[key]))}`);
      }
    }
    const cost = r['cost'] as Record<string, Object> | undefined;
    if (cost) {
      const cents = Number(cost['chargedCents'] ?? cost['rawCostCents'] ?? 0);
      if (cents > 0 && cents === cents) {
        bits.push(`约 $${(cents / 100).toFixed(cents >= 100 ? 2 : 3)}`);
      }
    }
    if (bits.length === 0) {
      return '';
    }
    return bits.join(' · ');
  } catch (_e) {
    return '';
  }
}

export function formatTokenShort(n: number | undefined): string {
  return formatTokenCount(n ?? 0);
}

function formatTokenCount(n: number): string {
  if (!n || isBadNumber(n)) {
    return '0';
  }
  if (n < 1000) {
    return `${Math.round(n)}`;
  }
  if (n < 10000) {
    return `${(n / 1000).toFixed(1)}k`;
  }
  return `${Math.round(n / 1000)}k`;
}

function isBadNumber(n: number): boolean {
  return n !== n || n < 0;
}

export function fileNameOf(path: string): string {
  const p = path ?? '';
  const slash = p.lastIndexOf('/');
  if (slash < 0 || slash >= p.length - 1) {
    return p;
  }
  return p.substring(slash + 1);
}

export function isImagePath(path: string): boolean {
  const p = (path ?? '').toLowerCase();
  return p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.jpeg') ||
    p.endsWith('.gif') || p.endsWith('.webp') || p.endsWith('.heic') ||
    p.endsWith('.heif') || p.endsWith('.hif') || p.endsWith('.avif');
}

export function isVideoPath(path: string): boolean {
  const p = (path ?? '').toLowerCase();
  return p.endsWith('.mp4') || p.endsWith('.webm') || p.endsWith('.mov');
}

export function formatBytes(n: number | undefined): string {
  const v = n ?? 0;
  if (!v || isBadNumber(v)) {
    return '';
  }
  if (v < 1024) {
    return `${Math.round(v)} B`;
  }
  if (v < 1024 * 1024) {
    return `${(v / 1024).toFixed(1)} KB`;
  }
  return `${(v / (1024 * 1024)).toFixed(1)} MB`;
}
