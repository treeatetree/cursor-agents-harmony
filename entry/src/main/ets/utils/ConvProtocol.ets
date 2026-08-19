/**
 * Cursor composer protocol that conversation GET sometimes returns as user_message.
 * Those must not paint as user bubbles.
 */

export interface ParsedTask {
  kind: string;
  status: string;
  title: string;
  taskId: string;
  summary: string;
  response: string;
}

export interface ParsedProtocol {
  protocol: boolean;
  userText: string;
  tasks: ParsedTask[];
}

export function isComposerProtocol(text: string): boolean {
  const t = text ?? '';
  return t.indexOf('<system_notification>') >= 0 ||
    t.indexOf('<task>') >= 0 ||
    t.indexOf('<user_query>') >= 0 ||
    t.indexOf('<timestamp>') >= 0 ||
    t.indexOf('<user_visible_high_level_summary>') >= 0;
}

export function parseComposerProtocol(text: string): ParsedProtocol {
  const src = text ?? '';
  if (!isComposerProtocol(src)) {
    return { protocol: false, userText: src.trim(), tasks: [] };
  }
  const tasks: ParsedTask[] = [];
  const rawTasks = extractAllTags(src, 'task');
  for (let i = 0; i < rawTasks.length; i++) {
    const task = parseTaskBlock(rawTasks[i]);
    if (task.title.length > 0 || task.summary.length > 0 || task.response.length > 0) {
      tasks.push(task);
    }
  }
  let userText = extractTag(src, 'user_query').trim();
  if (userText.length === 0) {
    userText = leftoverUserText(src);
  }
  return { protocol: true, userText: userText, tasks: tasks };
}

export function taskCardTitle(task: ParsedTask): string {
  const title = task.title.trim();
  return title.length > 0 ? `子任务 · ${title}` : '子任务';
}

export function taskCardBody(task: ParsedTask): string {
  const summary = task.summary.trim();
  const response = task.response.trim();
  if (summary.length > 0 && response.length > 0 && summary !== response) {
    return `${summary}\n\n${response}`;
  }
  if (response.length > 0) {
    return response;
  }
  return summary;
}

export function taskFailed(task: ParsedTask): boolean {
  const s = task.status.toLowerCase();
  return s === 'error' || s === 'failed' || s === 'fail';
}

function parseTaskBlock(block: string): ParsedTask {
  const summary = extractTag(block, 'user_visible_high_level_summary');
  const response = extractTag(block, 'response');
  return {
    kind: fieldOf(block, 'kind'),
    status: fieldOf(block, 'status'),
    title: fieldOf(block, 'title'),
    taskId: fieldOf(block, 'task_id'),
    summary: summary,
    response: response
  };
}

function leftoverUserText(src: string): string {
  let t = src;
  t = stripTag(t, 'timestamp');
  t = stripTag(t, 'system_notification');
  t = stripTag(t, 'task');
  t = stripTag(t, 'user_query');
  t = stripTag(t, 'user_visible_high_level_summary');
  t = stripTag(t, 'response');
  t = t.trim();
  if (t.length === 0 || looksLikeProtocolResidue(t)) {
    return '';
  }
  return t;
}

function looksLikeProtocolResidue(text: string): boolean {
  const t = text.trim();
  if (t.length === 0) {
    return true;
  }
  if (t.indexOf('kind:') === 0 || t.indexOf('status:') === 0 || t.indexOf('task_id:') === 0) {
    return true;
  }
  if (t.indexOf('fc_') === 0 || t.indexOf('call_') === 0) {
    return true;
  }
  return t.indexOf('<') >= 0 && t.indexOf('>') > 0 && t.length < 80;
}

function fieldOf(block: string, key: string): string {
  const prefix = `${key}:`;
  const lines = block.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.indexOf(prefix) === 0) {
      return line.substring(prefix.length).trim();
    }
  }
  return '';
}

function extractTag(src: string, name: string): string {
  const open = `<${name}>`;
  const close = `</${name}>`;
  const a = src.indexOf(open);
  if (a < 0) {
    return '';
  }
  const start = a + open.length;
  const b = src.indexOf(close, start);
  if (b < 0) {
    return src.substring(start).trim();
  }
  return src.substring(start, b).trim();
}

function extractAllTags(src: string, name: string): string[] {
  const out: string[] = [];
  const open = `<${name}>`;
  const close = `</${name}>`;
  let from = 0;
  while (from < src.length) {
    const a = src.indexOf(open, from);
    if (a < 0) {
      break;
    }
    const start = a + open.length;
    const b = src.indexOf(close, start);
    if (b < 0) {
      out.push(src.substring(start).trim());
      break;
    }
    out.push(src.substring(start, b).trim());
    from = b + close.length;
  }
  return out;
}

function stripTag(src: string, name: string): string {
  const open = `<${name}>`;
  const close = `</${name}>`;
  let t = src;
  while (true) {
    const a = t.indexOf(open);
    if (a < 0) {
      return t;
    }
    const b = t.indexOf(close, a);
    if (b < 0) {
      return `${t.substring(0, a)}${t.substring(a + open.length)}`;
    }
    t = `${t.substring(0, a)}${t.substring(b + close.length)}`;
  }
}
