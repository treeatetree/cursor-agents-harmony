import { isSubagentTool, plainArg, shortPathForTool, subagentDetail } from './StreamText';
import { ToolCallEvent } from '../models/Sse';
import { isOpaqueStepLabel } from './TimelineMedia';

/** Cloud web uses the raw slug: "Used web-fetch". */
export function toolSlug(name: string): string {
  let n = (name ?? '').trim();
  if (n.length === 0) {
    return 'tool';
  }
  const slash = n.lastIndexOf('/');
  if (slash >= 0 && slash < n.length - 1) {
    n = n.substring(slash + 1);
  }
  const low = n.toLowerCase();
  if (low.indexOf('mcp_') === 0 || low.indexOf('mcp-') === 0) {
    n = n.substring(4);
  }
  return n.replace(/_/g, '-');
}

export function toolArgDetail(name: string, argsText: string): string {
  if (isSubagentTool(name)) {
    return subagentDetail(argsText);
  }
  if (!argsText || argsText.length === 0) {
    return '';
  }
  try {
    const args = JSON.parse(argsText) as Record<string, Object>;
    if (args['path']) {
      return shortPathForTool(plainArg(args['path']));
    }
    if (args['command']) {
      const cmd = plainArg(args['command']);
      return cmd.length > 48 ? `${cmd.substring(0, 48)}…` : cmd;
    }
    if (args['query'] || args['url']) {
      const q = plainArg(args['query'] ?? args['url']);
      return q.length > 48 ? `${q.substring(0, 48)}…` : q;
    }
  } catch (_e) {
  }
  return '';
}

/** "正在用 web-fetch" / "用了 web-fetch · path" */
export function usedToolLine(name: string, running: boolean, detail: string = ''): string {
  if (isSubagentTool(name)) {
    const extra = detail;
    const head = running ? '在开子任务' : '子任务';
    return extra.length > 0 ? `${head} · ${extra}` : head;
  }
  const slug = toolSlug(name);
  const head = running ? `正在用 ${slug}` : `用了 ${slug}`;
  if (detail.length > 0) {
    return `${head} · ${detail}`;
  }
  return head;
}

export function usedToolFromEvent(tool: ToolCallEvent): string {
  const running = (tool.status ?? 'running') !== 'completed';
  return usedToolLine(tool.name, running, toolArgDetail(tool.name, tool.argsText ?? ''));
}

/** Drop Cursor's opaque stepId ("步骤 642"). Keep a real title if the cloud sent one. */
export function meaningfulStepTitle(raw: string): string {
  const t = (raw ?? '').trim();
  if (t.length === 0 || isOpaqueStepLabel(t)) {
    return '';
  }
  return t;
}

export function processLiveTitle(connecting: boolean, runningSlug: string, hasTools: boolean,
  elapsed: string): string {
  let head = '在想下一步';
  if (connecting) {
    head = '在准备环境';
  } else if (runningSlug.length > 0) {
    head = `正在用 ${runningSlug}`;
  } else if (hasTools) {
    head = '在看可用工具';
  }
  if (elapsed.length > 0) {
    return `${head} · ${elapsed}`;
  }
  return head;
}

/** Gray waiting line after a pause between SSE steps. */
export function waitingThinkLabel(tick: number): string {
  const n = (Math.abs(tick) % 3) + 1;
  if (n === 1) {
    return '在想下一步.';
  }
  if (n === 2) {
    return '在想下一步..';
  }
  return '在想下一步…';
}

export function processDoneTitle(hadTools: boolean, elapsed: string): string {
  if (elapsed.length > 0) {
    return hadTools ? `用了 ${elapsed}` : `思考了 ${elapsed}`;
  }
  return hadTools ? '过程' : '思考过程';
}

export function runHeaderVerb(status: string, elapsed: string): string {
  if (status === 'CREATING') {
    return '在准备环境';
  }
  if (status === 'RUNNING') {
    return '环境就绪';
  }
  if (status === 'FINISHED') {
    return elapsed.length > 0 ? `用了 ${elapsed}` : '已完成';
  }
  if (status === 'ERROR') {
    return '失败';
  }
  if (status === 'CANCELLED') {
    return '已取消';
  }
  if (status === 'EXPIRED') {
    return '已过期';
  }
  return status.length > 0 ? status : '运行';
}
