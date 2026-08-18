import { StreamCoordinator } from './StreamCoordinator';

/** Session-scoped handle around the global SSE coordinator. */
export class StreamSession {
  agentId: string = '';
  runId: string = '';
  generation: number = 0;

  bind(agentId: string, runId: string): void {
    this.agentId = agentId;
    this.runId = runId;
    this.generation = StreamCoordinator.getInstance().currentGeneration();
  }

  matches(agentId: string, runId: string): boolean {
    return this.agentId === agentId && this.runId === runId &&
      StreamCoordinator.getInstance().currentGeneration() === this.generation;
  }

  release(): void {
    StreamCoordinator.getInstance().release();
    this.agentId = '';
    this.runId = '';
    this.generation = 0;
  }
}
