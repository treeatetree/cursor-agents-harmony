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
  | 'streamNotice'
  | 'subagent';

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
  sentTags?: string[];
  /** Local or API ISO time. Empty means unknown — never invent for history. */
  localAt?: string;
  /** https / file URIs to show in the bubble. Never store raw base64 here. */
  imageUrls?: string[];
}
