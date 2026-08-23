const CONCURRENCY_ZH = '同时运行的 Cloud Agent 已达上限，先归档旧任务再试';

export function looksLikeConcurrencyLimit(message: string): boolean {
  const low = message.toLowerCase();
  return low.indexOf('limit') >= 0 || low.indexOf('upgrade') >= 0 ||
    low.indexOf('simultaneous') >= 0 || low.indexOf('concurrent') >= 0 ||
    low.indexOf('resource_exhausted') >= 0 ||
    message.indexOf('上限') >= 0 || message.indexOf('同时') >= 0;
}

export function looksLikeResourceExhausted(apiCode: string, message: string): boolean {
  const code = apiCode.toLowerCase();
  const low = message.toLowerCase();
  return code.indexOf('resource_exhausted') >= 0 ||
    low.indexOf('resource_exhausted') >= 0 ||
    low.indexOf('resource exhausted') >= 0;
}

/** User-facing copy for POST /v1/agents failures. */
export function mapCreateHttpMessage(code: number, apiCode: string, message: string): string {
  if (code === 409) {
    return '这次任务可能已经建过，请回 Inbox 看一下';
  }
  if (code === 403) {
    if (looksLikeResourceExhausted(apiCode, message) || looksLikeConcurrencyLimit(message)) {
      return CONCURRENCY_ZH;
    }
    return '无权限，请检查 Cursor 订阅计划';
  }
  if (code === 429) {
    if (looksLikeResourceExhausted(apiCode, message) || looksLikeConcurrencyLimit(message)) {
      return CONCURRENCY_ZH;
    }
    return '创建任务过于频繁，请稍等再发';
  }
  if (code === 500 || code === 502 || code === 503 || code === 504) {
    return 'Cursor 创建任务繁忙，请稍后再发';
  }
  return '';
}

export function mapHttpUserMessage(method: string, path: string, code: number, apiCode: string,
  message: string): string {
  const creating = method === 'POST' && path === '/v1/agents';
  if (code === 401) {
    return 'API Key 无效或已过期';
  }
  if (creating) {
    const mapped = mapCreateHttpMessage(code, apiCode, message);
    if (mapped.length > 0) {
      return mapped;
    }
  } else if (code === 403) {
    return looksLikeConcurrencyLimit(message) || looksLikeResourceExhausted(apiCode, message) ?
      CONCURRENCY_ZH : '无权限，请检查 Cursor 订阅计划';
  }
  if (code === 429) {
    if (path.indexOf('/repositories') >= 0) {
      return '仓库列表每分钟只能刷新一次，请稍后再试';
    }
    if (looksLikeResourceExhausted(apiCode, message) || looksLikeConcurrencyLimit(message)) {
      return CONCURRENCY_ZH;
    }
    return '请求过于频繁，请稍后重试';
  }
  if (code === 400) {
    return mapClient400(apiCode, message);
  }
  if (code === 503) {
    return '服务繁忙，请稍后重试';
  }
  return sanitizeApiMessage(message, `请求失败（${code}）`);
}

export function mapClient400(apiCode: string, message: string): string {
  const low = message.toLowerCase();
  if (low.indexOf('not supported in your region') >= 0 ||
    (apiCode === 'invalid_model' && low.indexOf('region') >= 0)) {
    return '这个模型在当前地区不可用，换 Composer、Grok、Kimi 或 GLM';
  }
  if (apiCode === 'invalid_model') {
    return '这个模型或参数不被支持，换一组参数或换模型';
  }
  return sanitizeApiMessage(message, '请求失败（400）');
}

export function sanitizeApiMessage(message: string, fallback: string): string {
  const t = (message ?? '').trim();
  if (t.length === 0) {
    return fallback;
  }
  const head = t.substring(0, 1);
  if (head === '{' || head === '[' || head === '<') {
    return fallback;
  }
  const low = t.toLowerCase();
  if (low.indexOf('body') === 0 || low.indexOf('"body"') >= 0 || low.indexOf('request body') >= 0) {
    return fallback;
  }
  if (t.length > 96) {
    return fallback;
  }
  return t;
}
