import { connection } from '@kit.NetworkKit';
import { Log } from './Log';

const TAG = 'NetMon';

export class NetworkMonitor {
  private static instance: NetworkMonitor | undefined = undefined;
  online: boolean = true;
  private listeners: Array<(online: boolean) => void> = [];
  private netCap: connection.NetConnection | undefined = undefined;

  static getInstance(): NetworkMonitor {
    if (!NetworkMonitor.instance) {
      NetworkMonitor.instance = new NetworkMonitor();
    }
    return NetworkMonitor.instance;
  }

  start(): void {
    if (this.netCap) {
      return;
    }
    try {
      this.netCap = connection.createNetConnection();
      this.netCap.register(() => {
      });
      this.netCap.on('netAvailable', () => {
        this.setOnline(true);
      });
      this.netCap.on('netUnavailable', () => {
        this.setOnline(false);
      });
      Log.info(TAG, 'started');
    } catch (e) {
      Log.warn(TAG, `start failed: ${JSON.stringify(e)}`);
    }
  }

  onChange(cb: (online: boolean) => void): () => void {
    this.listeners.push(cb);
    return () => {
      const next: Array<(online: boolean) => void> = [];
      for (let i = 0; i < this.listeners.length; i++) {
        if (this.listeners[i] !== cb) {
          next.push(this.listeners[i]);
        }
      }
      this.listeners = next;
    };
  }

  private setOnline(v: boolean): void {
    if (this.online === v) {
      return;
    }
    this.online = v;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](v);
    }
  }
}
