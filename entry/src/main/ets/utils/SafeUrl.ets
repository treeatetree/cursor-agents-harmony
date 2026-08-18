export interface ParsedHttpUrl {
  scheme: string;
  hostname: string;
  href: string;
}

const TRUSTED_HOSTS: string[] = ['cursor.com', 'cursor.so'];

export function parseHttpUrl(raw: string): ParsedHttpUrl | undefined {
  const trimmed = (raw ?? '').trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  const lower = trimmed.toLowerCase();
  let scheme = '';
  let rest = trimmed;
  const sep = trimmed.indexOf('://');
  if (sep <= 0) {
    return undefined;
  }
  scheme = lower.substring(0, sep);
  rest = trimmed.substring(sep + 3);
  if (scheme !== 'http' && scheme !== 'https') {
    return undefined;
  }
  const slash = rest.indexOf('/');
  const hostPort = slash >= 0 ? rest.substring(0, slash) : rest;
  if (hostPort.length === 0) {
    return undefined;
  }
  const at = hostPort.lastIndexOf('@');
  const hostOnly = at >= 0 ? hostPort.substring(at + 1) : hostPort;
  const colon = hostOnly.indexOf(':');
  const hostname = (colon >= 0 ? hostOnly.substring(0, colon) : hostOnly).toLowerCase();
  if (hostname.length === 0 || hostname.indexOf('.') < 0 && hostname !== 'localhost') {
    if (hostname !== 'localhost') {
      return undefined;
    }
  }
  if (hostname.indexOf(' ') >= 0) {
    return undefined;
  }
  return { scheme: scheme, hostname: hostname, href: trimmed };
}

export function isTrustedCursorHost(hostname: string): boolean {
  const h = (hostname ?? '').toLowerCase();
  for (let i = 0; i < TRUSTED_HOSTS.length; i++) {
    const root = TRUSTED_HOSTS[i];
    if (h === root || h.endsWith(`.${root}`)) {
      return true;
    }
  }
  return false;
}

export function isSafeHttpsUrl(raw: string): boolean {
  const parsed = parseHttpUrl(raw);
  return parsed !== undefined && parsed.scheme === 'https';
}

export function isInAppBrowserUrl(raw: string): boolean {
  const parsed = parseHttpUrl(raw);
  if (!parsed || parsed.scheme !== 'https') {
    return false;
  }
  return isTrustedCursorHost(parsed.hostname);
}

export function isBlockedLinkScheme(raw: string): boolean {
  const trimmed = (raw ?? '').trim().toLowerCase();
  const sep = trimmed.indexOf(':');
  if (sep <= 0) {
    return true;
  }
  const scheme = trimmed.substring(0, sep);
  return scheme !== 'https';
}

export function linkHostname(raw: string): string {
  const parsed = parseHttpUrl(raw);
  return parsed ? parsed.hostname : '';
}
