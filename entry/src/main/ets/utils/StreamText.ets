/**
 * Classify live assistant deltas: status chatter vs the real answer.
 */

export function isProgressText(text: string): boolean {
  const t = (text ?? '').trim();
  if (t.length === 0) {
    return true;
  }
  if (t.indexOf('```') >= 0) {
    return false;
  }
  if (t.startsWith('#') || t.indexOf('\n#') >= 0) {
    return false;
  }
  if (t.startsWith('|') || t.indexOf('\n|') >= 0) {
    return false;
  }
  if (t.startsWith('**')) {
    const close = t.indexOf('**', 2);
    if (close > 2) {
      return false;
    }
    if (t.length > 40) {
      return false;
    }
  }
  if (t.indexOf('\n- ') >= 0 && t.length > 120) {
    return false;
  }
  if (t.length > 360) {
    return false;
  }
  let blanks = 0;
  let i = 0;
  while (i < t.length - 1) {
    if (t.charAt(i) === '\n' && t.charAt(i + 1) === '\n') {
      blanks++;
      i += 2;
    } else {
      i++;
    }
  }
  return blanks < 2;
}

export function lastNonEmptyLine(text: string, maxLen: number = 80): string {
  const src = text ?? '';
  const lines = src.split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].trim();
    if (line.length > 0) {
      return line.length > maxLen ? `${line.substring(0, maxLen)}…` : line;
    }
  }
  return '';
}

export function lastTextSummary(texts: string[], maxLen: number = 72): string {
  for (let i = texts.length - 1; i >= 0; i--) {
    const line = lastNonEmptyLine(texts[i], maxLen);
    if (line.length > 0) {
      return line;
    }
  }
  return '';
}

export function lastStep(text: string): string {
  const src = text ?? '';
  const idx = src.lastIndexOf('\n\n');
  if (idx < 0) {
    return src;
  }
  return src.substring(idx + 2);
}

export function dropLastStep(text: string): string {
  const src = text ?? '';
  const idx = src.lastIndexOf('\n\n');
  if (idx < 0) {
    return '';
  }
  return src.substring(0, idx);
}

export function countSteps(text: string): number {
  const t = (text ?? '').trim();
  if (t.length === 0) {
    return 0;
  }
  let n = 1;
  let i = 0;
  while (i < t.length - 1) {
    if (t.charAt(i) === '\n' && t.charAt(i + 1) === '\n') {
      n++;
      i += 2;
    } else {
      i++;
    }
  }
  return n;
}

export function shortPathForTool(path: string): string {
  if (!path || path.length === 0) {
    return '';
  }
  const cleaned = path.replace(/\/$/, '');
  const parts = cleaned.split('/');
  const base = parts.length > 0 ? parts[parts.length - 1] : path;
  return base.length > 0 ? base : path;
}

export function friendlyToolName(name: string): string {
  const n = name ?? '';
  if (isSubagentTool(n)) {
    return '子任务';
  }
  if (n.indexOf('read') >= 0) {
    return '读取';
  }
  if (n.indexOf('edit') >= 0 || n.indexOf('write') >= 0 || n.indexOf('replace') >= 0) {
    return '编辑';
  }
  if (n.indexOf('terminal') >= 0 || n.indexOf('shell') >= 0 || n.indexOf('cmd') >= 0) {
    return '终端';
  }
  if (n.indexOf('grep') >= 0 || n.indexOf('search') >= 0) {
    return '搜索';
  }
  if (n.indexOf('list') >= 0 || n.indexOf('dir') >= 0) {
    return '目录';
  }
  if (n.indexOf('mcp') >= 0) {
    return 'MCP';
  }
  return n.length > 0 ? n : '工具';
}

export function isSubagentTool(name: string): boolean {
  const n = (name ?? '').toLowerCase();
  if (n === 'task' || n === 'agent' || n === 'task_tool') {
    return true;
  }
  if (n.indexOf('subagent') >= 0) {
    return true;
  }
  if (n === 'generalpurpose' || n === 'general_purpose' || n === 'explore') {
    return true;
  }
  return false;
}

export function subagentDetail(argsText: string): string {
  if (!argsText || argsText.length === 0) {
    return '';
  }
  try {
    const args = JSON.parse(argsText) as Record<string, Object>;
    const kind = plainArg(args['subagent_type'] ?? args['subagentType'] ?? args['model']);
    let title = plainArg(args['description'] ?? args['title']);
    if (title.length === 0) {
      title = firstLine(plainArg(args['prompt'] ?? args['task']));
    }
    if (title.length > 72) {
      title = `${title.substring(0, 72)}…`;
    }
    if (kind.length > 0 && title.length > 0) {
      return `${kind} · ${title}`;
    }
    return title.length > 0 ? title : kind;
  } catch (_e) {
    return '';
  }
}

export function plainArg(v: Object | undefined): string {
  if (v === undefined || v === null) {
    return '';
  }
  const t = typeof v;
  if (t === 'string' || t === 'number' || t === 'boolean') {
    const s = `${v}`.trim();
    if (s === '[object Object]' || s === 'undefined' || s === 'null') {
      return '';
    }
    return s;
  }
  return '';
}

function firstLine(text: string): string {
  const t = (text ?? '').trim();
  const nl = t.indexOf('\n');
  return nl >= 0 ? t.substring(0, nl).trim() : t;
}
