import { socket } from '@kit.NetworkKit';
import { RemoteDevice } from '../model/RemoteModels';

interface LanSocketMessage {
  message: ArrayBuffer;
}

class VarintResult {
  value: number;
  next: number;

  constructor(value: number, next: number) {
    this.value = value;
    this.next = next;
  }
}

export class LanDiscoveryService {
  private udp: socket.UDPSocket | undefined = undefined;
  private peers: RemoteDevice[] = [];

  async discover(): Promise<RemoteDevice[]> {
    this.close();
    this.peers = [];
    const udp = socket.constructUDPSocketInstance();
    this.udp = udp;
    udp.on('message', (event: LanSocketMessage) => this.receive(event.message));
    try {
      await udp.bind({ address: '0.0.0.0', port: 0, family: 1 });
      await udp.setExtraOptions({ broadcast: true });
      const query = new Uint8Array([0xB2, 0x01, 0x06, 0x0A, 0x04, 0x70, 0x69, 0x6E, 0x67]);
      await udp.send({
        data: query.buffer,
        address: { address: '255.255.255.255', port: 21119, family: 1 }
      });
    } catch (error) {
      this.close();
      throw new Error(`局域网广播失败：${String(error)}`);
    }
    return await new Promise<RemoteDevice[]>((resolve: (value: RemoteDevice[]) => void) => {
      setTimeout(() => {
        const result = this.peers.slice();
        this.close();
        resolve(result);
      }, 3200);
    });
  }

  close(): void {
    if (this.udp !== undefined) {
      try {
        this.udp.off('message');
        this.udp.close();
      } catch (_) {
      }
      this.udp = undefined;
    }
  }

  private receive(buffer: ArrayBuffer): void {
    try {
      const bytes = new Uint8Array(buffer);
      let offset = 0;
      const outerTag = this.varint(bytes, offset);
      offset = outerTag.next;
      if (outerTag.value !== 178) return;
      const outerLength = this.varint(bytes, offset);
      offset = outerLength.next;
      const end = Math.min(bytes.length, offset + outerLength.value);
      let cmd = '';
      let id = '';
      let username = '';
      let hostname = '';
      let platform = 'RustDesk';
      while (offset < end) {
        const tag = this.varint(bytes, offset);
        offset = tag.next;
        const wire = tag.value & 7;
        const field = tag.value >> 3;
        if (wire !== 2) return;
        const length = this.varint(bytes, offset);
        offset = length.next;
        const value = this.decodeUtf8(bytes.slice(offset, Math.min(end, offset + length.value)));
        offset += length.value;
        if (field === 1) cmd = value;
        if (field === 3) id = value;
        if (field === 4) username = value;
        if (field === 5) hostname = value;
        if (field === 6) platform = value;
      }
      if (cmd !== 'pong' || id.length === 0 || this.peers.some((peer: RemoteDevice) => peer.id === id)) return;
      const name = hostname.length > 0 ? hostname : (username.length > 0 ? username : '局域网设备');
      this.peers.push(new RemoteDevice(id, name, platform, true, false, '局域网在线', '#69A8E8'));
    } catch (_) {
    }
  }

  private varint(bytes: Uint8Array, start: number): VarintResult {
    let value = 0;
    let shift = 0;
    let index = start;
    while (index < bytes.length && shift < 35) {
      const byte = bytes[index++];
      value |= (byte & 0x7F) << shift;
      if ((byte & 0x80) === 0) break;
      shift += 7;
    }
    return new VarintResult(value, index);
  }

  private decodeUtf8(bytes: Uint8Array): string {
    let encoded = '';
    for (let index = 0; index < bytes.length; index += 1) {
      encoded += `%${bytes[index].toString(16).padStart(2, '0')}`;
    }
    try {
      return decodeURIComponent(encoded);
    } catch (_) {
      return '';
    }
  }
}
