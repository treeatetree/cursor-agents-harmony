export type SseEventType =
  | 'status'
  | 'assistant'
  | 'thinking'
  | 'tool_call'
  | 'interaction_update'
  | 'heartbeat'
  | 'result'
  | 'error'
  | 'done'
  | 'unknown';

export interface SseFrame {
  id: string;
  event: SseEventType;
  data: string;
}

export interface ToolCallEvent {
  callId: string;
  name: string;
  status: string; // running | completed
  argsText?: string;
  resultText?: string;
  truncatedArgs?: boolean;
  truncatedResult?: boolean;
}

export interface StatusEvent {
  runId?: string;
  status?: string;
}

export interface TextDeltaEvent {
  text?: string;
}

export interface ResultEvent {
  runId?: string;
  status?: string;
  text?: string;
  durationMs?: number;
  gitJson?: string;
}

export interface StreamErrorEvent {
  code?: string;
  message?: string;
}
