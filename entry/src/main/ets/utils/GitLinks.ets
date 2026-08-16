export interface GitWebRef {
  host: string;
  owner: string;
  repo: string;
  path: string;
}

/** Parse github/gitlab https or ssh remote into web path parts. */
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
  return {
    host: host,
    owner: segs[0],
    repo: segs[segs.length - 1],
    path: path
  };
}

/**
 * Files-changed URL. GitHub compare when we have a head branch;
 * falls back to the branch tree page.
 */
export function gitCompareUrl(repoUrl: string, baseRef: string, headBranch: string): string {
  const head = (headBranch ?? '').trim();
  if (head.length === 0) {
    return '';
  }
  const git = parseGitWeb(repoUrl);
  if (!git) {
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

function enc(value: string): string {
  return encodeURIComponent(value);
}
