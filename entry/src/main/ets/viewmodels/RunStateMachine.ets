import { DetailPhase, phaseFromRun } from '../utils/RunState';

export class RunStateMachine {
  phase: DetailPhase = 'Idle';

  reset(): void {
    this.phase = 'Idle';
  }

  sync(status: string, loading: boolean, sending: boolean): DetailPhase {
    this.phase = phaseFromRun(status, loading, sending);
    return this.phase;
  }
}
