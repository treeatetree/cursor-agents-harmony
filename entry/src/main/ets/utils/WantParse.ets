/** Read agent id from a notification Want (parameters or cursoragent:// uri). */
export function agentIdFromLaunch(parameters: Record<string, Object> | undefined, uri: string): string {
  if (parameters) {
    const direct = `${parameters['agentId'] ?? ''}`;
    if (direct.length > 0 && direct !== 'undefined') {
      return direct;
    }
  }
  const raw = uri ?? '';
  const prefix = 'cursoragent://open/';
  if (raw.indexOf(prefix) === 0) {
    return raw.substring(prefix.length);
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

export function noticeTextFromLaunch(parameters: Record<string, Object> | undefined): string {
  if (!parameters) {
    return '';
  }
  const text = `${parameters['noticeText'] ?? ''}`;
  if (text.length === 0 || text === 'undefined') {
    return '';
  }
  return text;
}
