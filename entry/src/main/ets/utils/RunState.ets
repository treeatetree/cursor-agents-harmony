import { RunStatus } from '../models/Api';

const TERMINAL: string[] = ['FINISHED', 'ERROR', 'CANCELLED', 'EXPIRED'];

export function isTerminalStatus(status?: string): boolean {
  const s = status ?? '';
  return TERMINAL.indexOf(s) >= 0;
}

export function isInFlightStatus(status?: string): boolean {
  return status === 'RUNNING' || status === 'CREATING';
}

/** True when an incoming snapshot may replace the current run status. */
export function canApplyRunStatus(prev: string, next: string): boolean {
  if (!next || next.length === 0) {
    return false;
  }
  if (prev === next) {
    return true;
  }
  if (isTerminalStatus(prev) && !isTerminalStatus(next)) {
    return false;
  }
  return true;
}

/** Prefer the newer ISO timestamp. Empty loses. */
export function pickNewerIso(a?: string, b?: string): string {
  const left = a ?? '';
  const right = b ?? '';
  if (left.length === 0) {
    return right;
  }
  if (right.length === 0) {
    return left;
  }
  return left >= right ? left : right;
}

export function isNewerIso(candidate?: string, current?: string): boolean {
  const next = candidate ?? '';
  const prev = current ?? '';
  if (next.length === 0) {
    return prev.length === 0;
  }
  if (prev.length === 0) {
    return true;
  }
  return next >= prev;
}

export type DetailPhase =
  'Idle' | 'Loading' | 'Ready' | 'Creating' | 'Streaming' | 'Settling' | 'Finished' | 'Error';

export function phaseFromRun(status: string, loading: boolean, sending: boolean): DetailPhase {
  if (loading) {
    return 'Loading';
  }
  if (sending && (status === 'CREATING' || status.length === 0)) {
    return 'Creating';
  }
  if (status === 'CREATING' || status === 'RUNNING') {
    return 'Streaming';
  }
  if (status === 'FINISHED' || status === 'CANCELLED' || status === 'EXPIRED') {
    return 'Finished';
  }
  if (status === 'ERROR') {
    return 'Error';
  }
  return 'Ready';
}

export function sameRunId(left?: string, right?: string): boolean {
  const a = left ?? '';
  const b = right ?? '';
  return a.length > 0 && a === b;
}

export type RunStatusName = RunStatus;
