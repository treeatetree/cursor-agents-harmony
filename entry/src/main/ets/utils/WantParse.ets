const AGENT_ID_MAX = 80;
const AGENT_ID_RE = /^[A-Za-z0-9._:-]+$/;

function validAgentId(id: string): boolean {
  if (id.length === 0 || id.length > AGENT_ID_MAX || id === 'undefined') {
    return false;
  }
  return AGENT_ID_RE.test(id);
}

/** Read agent id from a notification Want (parameters or cursoragent:// uri). */
export function agentIdFromLaunch(parameters: Record<string, Object> | undefined, uri: string): string {
  if (parameters) {
    const direct = `${parameters['agentId'] ?? ''}`;
    if (validAgentId(direct)) {
      return direct;
    }
  }
  const raw = uri ?? '';
  const prefix = 'cursoragent://open/';
  if (raw.indexOf(prefix) === 0) {
    const id = raw.substring(prefix.length);
    return validAgentId(id) ? id : '';
  }
  return '';
}

export function showUnreadFromLaunch(parameters: Record<string, Object> | undefined): boolean {
  if (!parameters) {
    return false;
  }
  const v = `${parameters['showUnread'] ?? ''}`;
  return v === '1' || v === 'true';
}

/** External noticeText is ignored — lock-screen copy must not be attacker-controlled. */
export function noticeTextFromLaunch(_parameters: Record<string, Object> | undefined): string {
  return '';
}
