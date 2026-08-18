export interface GitWebRef {
  host: string;
  owner: string;
  repo: string;
  path: string;
}

/** Parse github/gitlab/origin https or ssh remote into web path parts. */
export function parseGitWeb(repoUrl: string): GitWebRef | undefined {
  const raw = (repoUrl ?? '').trim();
  if (raw.length === 0) {
    return undefined;
  }
  let host = '';
  let path = '';
  if (raw.indexOf('git@') === 0) {
    const rest = raw.substring(4);
    const colon = rest.indexOf(':');
    if (colon < 1) {
      return undefined;
    }
    host = rest.substring(0, colon);
    path = rest.substring(colon + 1);
  } else {
    let u = raw;
    if (u.indexOf('https://') === 0) {
      u = u.substring(8);
    } else if (u.indexOf('http://') === 0) {
      u = u.substring(7);
    }
    const slash = u.indexOf('/');
    if (slash < 1) {
      return undefined;
    }
    host = u.substring(0, slash);
    path = u.substring(slash + 1);
  }
  if (path.endsWith('.git')) {
    path = path.substring(0, path.length - 4);
  }
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  const segs = path.split('/');
  if (segs.length < 2 || segs[0].length === 0 || segs[1].length === 0) {
    return undefined;
  }
  const h = host.toLowerCase();
  if ((h === 'cursor.com' || h === 'www.cursor.com') && segs[0] === 'codebase') {
    if (segs.length < 3 || segs[1].length === 0 || segs[2].length === 0) {
      return undefined;
    }
    return {
      host: host,
      owner: segs[1],
      repo: segs[segs.length - 1],
      path: segs.slice(1).join('/')
    };
  }
  return {
    host: host,
    owner: segs[0],
    repo: segs[segs.length - 1],
    path: path
  };
}

export function isOriginRepo(repoUrl: string): boolean {
  const low = (repoUrl ?? '').toLowerCase();
  if (low.indexOf('origin.cursor.com') >= 0 || low.indexOf('cursor.com/codebase') >= 0) {
    return true;
  }
  const git = parseGitWeb(repoUrl);
  return !!git && isOriginGit(git);
}

/** Typed text is a pasteable GitHub / Origin URL, not a name filter. */
export function looksLikeRepoUrl(raw: string): boolean {
  const t = (raw ?? '').trim().toLowerCase();
  if (t.length < 8) {
    return false;
  }
  if (t.indexOf('https://') === 0 || t.indexOf('http://') === 0 || t.indexOf('git@') === 0) {
    return true;
  }
  return t.indexOf('github.com/') >= 0 || t.indexOf('origin.cursor.com/') >= 0;
}

/** Codebase browse URL → Origin clone URL used by Cloud Agents. */
export function normalizeCreateRepoUrl(url: string): string {
  const cleaned = (url ?? '').trim();
  if (cleaned.length === 0) {
    return cleaned;
  }
  const git = parseGitWeb(cleaned);
  if (git && (isOriginGit(git) || isOriginRepo(cleaned))) {
    return `https://origin.cursor.com/${git.owner}/${git.repo}`;
  }
  return cleaned;
}

/**
 * Files-changed URL. GitHub compare when we have a head branch;
 * Origin falls back to the Codebase repo page (no public compare path).
 */
export function gitCompareUrl(repoUrl: string, baseRef: string, headBranch: string): string {
  const git = parseGitWeb(repoUrl);
  if (!git) {
    return '';
  }
  if (isOriginGit(git) || isOriginRepo(repoUrl)) {
    return `https://cursor.com/codebase/${git.owner}/${git.repo}`;
  }
  const head = (headBranch ?? '').trim();
  if (head.length === 0) {
    return '';
  }
  const base = (baseRef ?? '').trim();
  const host = git.host.toLowerCase();
  if (host === 'github.com' || host.endsWith('.github.com')) {
    if (base.length > 0 && base !== head) {
      return `https://github.com/${git.owner}/${git.repo}/compare/${enc(base)}...${enc(head)}`;
    }
    return `https://github.com/${git.owner}/${git.repo}/tree/${enc(head)}`;
  }
  if (host.indexOf('gitlab') >= 0) {
    if (base.length > 0 && base !== head) {
      return `https://${git.host}/${git.path}/-/compare/${enc(base)}...${enc(head)}`;
    }
    return `https://${git.host}/${git.path}/-/tree/${enc(head)}`;
  }
  return '';
}

function isOriginGit(git: GitWebRef): boolean {
  const host = git.host.toLowerCase();
  return host === 'origin.cursor.com' || host.endsWith('.origin.cursor.com');
}

function enc(value: string): string {
  return encodeURIComponent(value);
}
