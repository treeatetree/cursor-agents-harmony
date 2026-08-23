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
  // <timestamp> wraps almost every Cloud Agent turn, including assistant finals.
  // It is chrome, not a protocol payload.
  return t.indexOf('<system_notification>') >= 0 ||
    t.indexOf('<task>') >= 0 ||
    t.indexOf('<user_query>') >= 0 ||
    t.indexOf('<user_visible_high_level_summary>') >= 0;
}

/** Drop the composer timestamp wrapper. Safe on plain text. */
export function stripComposerWrapper(text: string): string {
  return stripTag(text ?? '', 'timestamp').trim();
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

/** Parent-agent spawn briefs that Cursor stores as user_message. */
export function looksLikeAgentTaskPrompt(text: string): boolean {
  const t = unwrapPromptText(text);
  if (t.length < 40) {
    return false;
  }
  const low = t.toLowerCase();
  if (t.charAt(0) === '{') {
    if (low.indexOf('"prompt"') >= 0 &&
      (low.indexOf('subagent') >= 0 || low.indexOf('"description"') >= 0)) {
      return true;
    }
  }
  if (low.indexOf('the parent agent') >= 0 || low.indexOf('parent agent') >= 0) {
    return true;
  }
  if (low.indexOf("your team's answer") >= 0 || low.indexOf('your teams answer') >= 0) {
    return true;
  }
  if (low.indexOf('subagent_type') >= 0 || low.indexOf('subagent type') >= 0) {
    return true;
  }
  if ((low.indexOf('you are a ') >= 0 || low.indexOf('you are an ') >= 0) &&
    low.indexOf('agent') >= 0) {
    return true;
  }
  if (low.indexOf('explore agent') >= 0 || low.indexOf('general-purpose') >= 0 ||
    low.indexOf('general purpose') >= 0 || low.indexOf('generalpurpose') >= 0) {
    return true;
  }
  if (low.indexOf('briefly inform the user about the task result') >= 0) {
    return true;
  }
  if (t.indexOf('你是一个') >= 0 || t.indexOf('你是一名') >= 0) {
    return t.indexOf('子代理') >= 0 || t.indexOf('子任务') >= 0 || t.indexOf('探索') >= 0 ||
      t.indexOf('代理') >= 0;
  }
  return false;
}

export function agentPromptTitle(text: string): string {
  const t = unwrapPromptText(text);
  if (t.charAt(0) === '{') {
    try {
      const raw = JSON.parse(t) as Record<string, Object>;
      const d = `${raw['description'] ?? raw['title'] ?? ''}`.trim();
      if (d.length > 0) {
        return `子任务提示词 · ${clipLine(d, 28)}`;
      }
    } catch (_e) {
    }
  }
  const line = firstPromptLine(t);
  return line.length > 0 ? `子任务提示词 · ${clipLine(line, 28)}` : '子任务提示词';
}

export function agentPromptBody(text: string): string {
  const t = unwrapPromptText(text);
  if (t.charAt(0) === '{') {
    try {
      const raw = JSON.parse(t) as Record<string, Object>;
      const p = `${raw['prompt'] ?? ''}`.trim();
      if (p.length > 0) {
        return p;
      }
    } catch (_e) {
    }
  }
  return t;
}

export function unwrapPromptText(text: string): string {
  const src = text ?? '';
  const q = extractTag(src, 'user_query').trim();
  if (q.length > 0) {
    return q;
  }
  const leftover = leftoverUserText(src);
  return leftover.length > 0 ? leftover : src.trim();
}

function firstPromptLine(text: string): string {
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length > 0) {
      return line;
    }
  }
  return '';
}

function clipLine(text: string, max: number): string {
  const t = text.trim();
  if (t.length <= max) {
    return t;
  }
  return `${t.substring(0, max)}…`;
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
