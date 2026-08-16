import { ToolCallEvent } from './Sse';

export type TimelineKind =
  | 'userPrompt'
  | 'runHeader'
  | 'thinking'
  | 'progress'
  | 'step'
  | 'assistant'
  | 'tool'
  | 'runOutcome'
  | 'streamNotice';

export interface TimelineItem {
  key: string;
  kind: TimelineKind;
  runId: string;
  text?: string;
  tool?: ToolCallEvent;
  statusLabel?: string;
  collapsed?: boolean;
  /** User opened this row; stream/persist must not auto-fold it. */
  pinnedOpen?: boolean;
  failed?: boolean;
  streaming?: boolean;
  stepCount?: number;
  usageShort?: string;
}
