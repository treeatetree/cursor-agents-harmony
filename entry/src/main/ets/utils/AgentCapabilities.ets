import { CustomSubagentDef, EnvTarget, EnvVarDef, McpServerDef } from '../models/Api';

export function emptyMcp(): McpServerDef {
  return { name: '', type: 'http', url: '', command: '', argsText: '', envText: '', headersText: '' };
}

export function emptySubagent(): CustomSubagentDef {
  return { name: '', description: '', prompt: '', model: 'inherit' };
}

export function emptyEnvVar(): EnvVarDef {
  return { key: '', value: '' };
}

export function defaultEnv(): EnvTarget {
  return { kind: 'default', name: '' };
}

export function usesNamedEnv(env: EnvTarget): boolean {
  return env.kind !== 'default' && env.name.trim().length > 0;
}

export function hasTools(env: EnvTarget, mcp: McpServerDef[], subs: CustomSubagentDef[],
  vars: EnvVarDef[]): boolean {
  if (env.kind !== 'default') {
    return true;
  }
  return countMcp(mcp) > 0 || countSubs(subs) > 0 || countVars(vars) > 0;
}

export function toolsChipLabel(env: EnvTarget, mcp: McpServerDef[], subs: CustomSubagentDef[],
  vars: EnvVarDef[]): string {
  const bits: string[] = [];
  if (env.kind !== 'default') {
    bits.push(envNameLabel(env));
  }
  const m = countMcp(mcp);
  if (m > 0) {
    bits.push(`MCP ${m}`);
  }
  const s = countSubs(subs);
  if (s > 0) {
    bits.push(`子代理 ${s}`);
  }
  const v = countVars(vars);
  if (v > 0) {
    bits.push(`变量 ${v}`);
  }
  if (bits.length === 0) {
    return '能力';
  }
  const joined = bits.join(' · ');
  return joined.length > 18 ? `${joined.substring(0, 16)}…` : joined;
}

export function envNameLabel(env: EnvTarget): string {
  if (env.kind === 'cloud') {
    return env.name.length > 0 ? env.name : '云环境';
  }
  if (env.kind === 'pool') {
    return env.name.length > 0 ? env.name : '自建池';
  }
  if (env.kind === 'machine') {
    return env.name.length > 0 ? env.name : '机器';
  }
  return '默认';
}

export function countMcp(list: McpServerDef[]): number {
  let n = 0;
  for (let i = 0; i < list.length; i++) {
    if (isMcpReady(list[i])) {
      n++;
    }
  }
  return n;
}

export function countSubs(list: CustomSubagentDef[]): number {
  let n = 0;
  for (let i = 0; i < list.length; i++) {
    if (list[i].name.trim().length > 0 && list[i].prompt.trim().length > 0) {
      n++;
    }
  }
  return n;
}

export function countVars(list: EnvVarDef[]): number {
  let n = 0;
  for (let i = 0; i < list.length; i++) {
    if (isVarReady(list[i])) {
      n++;
    }
  }
  return n;
}

export function isMcpReady(s: McpServerDef): boolean {
  if (s.name.trim().length === 0) {
    return false;
  }
  if (s.type === 'stdio') {
    return s.command.trim().length > 0;
  }
  return s.url.trim().length > 0;
}

export function isVarReady(v: EnvVarDef): boolean {
  const key = v.key.trim();
  if (key.length === 0 || key.indexOf('CURSOR_') === 0) {
    return false;
  }
  return v.value.length > 0;
}

export function toApiEnv(env: EnvTarget): object | undefined {
  if (!usesNamedEnv(env)) {
    return undefined;
  }
  const o: Record<string, Object> = {};
  o['type'] = env.kind;
  o['name'] = env.name.trim();
  return o;
}

export function toApiMcp(list: McpServerDef[]): Object[] {
  const out: Object[] = [];
  for (let i = 0; i < list.length && out.length < 50; i++) {
    const s = list[i];
    if (!isMcpReady(s)) {
      continue;
    }
    const o: Record<string, Object> = {};
    o['name'] = s.name.trim();
    o['type'] = s.type;
    if (s.type === 'stdio') {
      o['command'] = s.command.trim();
      const args = splitArgs(s.argsText);
      if (args.length > 0) {
        o['args'] = args;
      }
      const env = parseEnvText(s.envText);
      if (env) {
        o['env'] = env;
      }
    } else {
      o['url'] = s.url.trim();
      const headers = parseEnvText(s.headersText);
      if (headers) {
        o['headers'] = headers;
      }
    }
    out.push(o);
  }
  return out;
}

export function toApiSubagents(list: CustomSubagentDef[]): Object[] {
  const out: Object[] = [];
  for (let i = 0; i < list.length && out.length < 20; i++) {
    const s = list[i];
    if (s.name.trim().length === 0 || s.prompt.trim().length === 0) {
      continue;
    }
    const o: Record<string, Object> = {};
    o['name'] = s.name.trim();
    o['description'] = s.description.trim().length > 0 ? s.description.trim() : s.name.trim();
    o['prompt'] = s.prompt.trim();
    if (s.model.trim().length > 0 && s.model !== 'inherit') {
      o['model'] = s.model.trim();
    } else {
      o['model'] = 'inherit';
    }
    out.push(o);
  }
  return out;
}

export function toApiEnvVars(list: EnvVarDef[]): Record<string, Object> | undefined {
  const o: Record<string, Object> = {};
  let n = 0;
  for (let i = 0; i < list.length && n < 50; i++) {
    if (!isVarReady(list[i])) {
      continue;
    }
    o[list[i].key.trim()] = list[i].value;
    n++;
  }
  return n > 0 ? o : undefined;
}

export function serializeTools(env: EnvTarget, mcp: McpServerDef[], subs: CustomSubagentDef[]): string {
  const payload: Record<string, Object> = {};
  payload['envKind'] = env.kind;
  payload['envName'] = env.name;
  payload['mcp'] = mcp as Object;
  payload['subs'] = subs as Object;
  return JSON.stringify(payload);
}

export function parseToolsPref(raw: string): ToolsPref {
  const out: ToolsPref = {
    env: defaultEnv(),
    mcp: [],
    subs: []
  };
  if (!raw || raw.length === 0) {
    return out;
  }
  try {
    const o = JSON.parse(raw) as Record<string, Object>;
    out.env = {
      kind: `${o['envKind'] ?? 'default'}`,
      name: `${o['envName'] ?? ''}`
    };
    out.mcp = asMcpList(o['mcp']);
    out.subs = asSubList(o['subs']);
  } catch (_e) {
  }
  return out;
}

export interface ToolsPref {
  env: EnvTarget;
  mcp: McpServerDef[];
  subs: CustomSubagentDef[];
}

function asMcpList(raw: Object | undefined): McpServerDef[] {
  if (raw === undefined || raw === null) {
    return [];
  }
  const arr = raw as Object[];
  if (arr.length === undefined) {
    return [];
  }
  const out: McpServerDef[] = [];
  for (let i = 0; i < arr.length; i++) {
    const s = arr[i] as Record<string, Object>;
    out.push({
      name: `${s['name'] ?? ''}`,
      type: `${s['type'] ?? 'http'}`,
      url: `${s['url'] ?? ''}`,
      command: `${s['command'] ?? ''}`,
      argsText: `${s['argsText'] ?? ''}`,
      envText: `${s['envText'] ?? ''}`,
      headersText: `${s['headersText'] ?? ''}`
    });
  }
  return out;
}

function asSubList(raw: Object | undefined): CustomSubagentDef[] {
  if (raw === undefined || raw === null) {
    return [];
  }
  const arr = raw as Object[];
  if (arr.length === undefined) {
    return [];
  }
  const out: CustomSubagentDef[] = [];
  for (let i = 0; i < arr.length; i++) {
    const s = arr[i] as Record<string, Object>;
    out.push({
      name: `${s['name'] ?? ''}`,
      description: `${s['description'] ?? ''}`,
      prompt: `${s['prompt'] ?? ''}`,
      model: `${s['model'] ?? 'inherit'}`
    });
  }
  return out;
}

function splitArgs(text: string): string[] {
  const bits = text.trim().split(/\s+/);
  const out: string[] = [];
  for (let i = 0; i < bits.length; i++) {
    if (bits[i].length > 0) {
      out.push(bits[i]);
    }
  }
  return out;
}

function parseEnvText(text: string): Record<string, Object> | undefined {
  const o: Record<string, Object> = {};
  const parts = text.split(/[;\n]/);
  let n = 0;
  for (let i = 0; i < parts.length; i++) {
    const line = parts[i].trim();
    const eq = line.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const k = line.substring(0, eq).trim();
    const v = line.substring(eq + 1);
    if (k.length === 0) {
      continue;
    }
    o[k] = v;
    n++;
  }
  return n > 0 ? o : undefined;
}
