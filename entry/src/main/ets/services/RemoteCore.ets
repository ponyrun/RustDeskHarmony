import { socket } from '@kit.NetworkKit';
import {
  createSession,
  decompressZstd,
  decrypt,
  destroySession,
  encrypt,
  getVideoDecoderStatus,
  getVideoRenderedFrames,
  hashPassword,
  pushVideoFrame,
  resetVideoDecoder,
  SessionMaterial,
  setVideoSurface,
  verifySignedMessage,
  verifySignedWithKey
} from 'libremote_crypto.so';
import {
  ConnectRequest,
  ConnectionListener,
  ConnectionState,
  RemoteCapabilities
} from '../model/RemoteModels';

export interface RemoteCore {
  connect(request: ConnectRequest, listener: ConnectionListener): void;
  disconnect(): void;
  sendPointer(x: number, y: number, buttons: number): void;
  sendKey(keyCode: number, pressed: boolean): void;
  sendShortcut(keyCode: number, modifiers: Array<number>): void;
  sendTextShortcut(text: string, modifiers: Array<number>): void;
  sendText(text: string): void;
  sendCharacter(text: string): void;
  sendChatText(text: string): void;
  sendClipboardText(text: string): void;
  setClipboardListener(listener: ((text: string) => void) | undefined): void;
  setChatListener(listener: ((text: string) => void) | undefined): void;
  setCursorListener(listener: ((x: number, y: number) => void) | undefined): void;
  setCursorImageListener(listener: ((cursor: RemoteCursorImage) => void) | undefined): void;
  setCursorIdListener(listener: ((id: string) => void) | undefined): void;
  setVideoSurface(surfaceId: string): void;
  setVideoViewport(width: number, height: number): void;
  refreshVideo(): void;
  videoStatus(): string;
  videoRenderedFrames(): number;
  videoAspectRatio(): number;
  videoWidth(): number;
  videoHeight(): number;
  capabilities(): RemoteCapabilities;
}

export class RemoteCursorImage {
  id: string = '';
  hotX: number = 0;
  hotY: number = 0;
  width: number = 0;
  height: number = 0;
  colors: ArrayBuffer = new ArrayBuffer(0);
}

class ServerEndpoint {
  host: string;
  port: number;

  constructor(host: string, port: number) {
    this.host = host;
    this.port = port;
  }
}

class ProtoField {
  number: number;
  wireType: number;
  value: number;
  bytes: Array<number>;

  constructor(number: number, wireType: number, value: number = 0, bytes: Array<number> = []) {
    this.number = number;
    this.wireType = wireType;
    this.value = value;
    this.bytes = bytes;
  }
}

class ProtoCursor {
  private data: Array<number>;
  private offset: number = 0;

  constructor(data: Array<number>) {
    this.data = data;
  }

  next(): ProtoField | undefined {
    if (this.offset >= this.data.length) {
      return undefined;
    }
    const key = this.readVarint();
    const number = Math.floor(key / 8);
    const wireType = key % 8;
    if (number <= 0) {
      throw new Error('RustDesk protobuf 字段编号无效');
    }
    if (wireType === 0) {
      return new ProtoField(number, wireType, this.readVarint());
    }
    if (wireType === 2) {
      const length = this.readVarint();
      if (length < 0 || this.offset + length > this.data.length) {
        throw new Error('RustDesk protobuf 长度无效');
      }
      const bytes = this.data.slice(this.offset, this.offset + length);
      this.offset += length;
      return new ProtoField(number, wireType, 0, bytes);
    }
    if (wireType === 1) {
      return new ProtoField(number, wireType, 0, this.readFixed(8));
    }
    if (wireType === 5) {
      return new ProtoField(number, wireType, 0, this.readFixed(4));
    }
    throw new Error(`暂不支持的 RustDesk protobuf wire type: ${wireType}`);
  }

  private readFixed(length: number): Array<number> {
    if (this.offset + length > this.data.length) {
      throw new Error('RustDesk protobuf 定长字段数据不完整');
    }
    const bytes = this.data.slice(this.offset, this.offset + length);
    this.offset += length;
    return bytes;
  }

  private readVarint(): number {
    let value = 0;
    let scale = 1;
    for (let index = 0; index < 10; index += 1) {
      if (this.offset >= this.data.length) {
        throw new Error('RustDesk protobuf 数据不完整');
      }
      const byte = this.data[this.offset];
      this.offset += 1;
      value += (byte & 0x7f) * scale;
      if ((byte & 0x80) === 0) {
        return value;
      }
      scale *= 128;
    }
    throw new Error('RustDesk protobuf varint 过长');
  }
}

class PeerIdentity {
  id: string;
  publicKey: Array<number>;

  constructor(id: string, publicKey: Array<number>) {
    this.id = id;
    this.publicKey = publicKey;
  }
}

class RouteInfo {
  relayServer: string = '';
  signedIdentity: Array<number> = [];
  relayUuid: string = '';
  refusal: string = '';
}

class HashChallenge {
  salt: string = '';
  challenge: string = '';
}

class LoginResult {
  error: string = '';
  accepted: boolean = false;
  hostname: string = '';
  platform: string = '';
  version: string = '';
  width: number = 0;
  height: number = 0;
}

class EncodedFrame {
  data: Array<number> = [];
  key: boolean = false;
  pts: number = 0;
}

class VideoPacket {
  codec: string = '';
  frames: Array<EncodedFrame> = [];
}

class PhysicalKeyStroke {
  code: number;
  shift: boolean;

  constructor(code: number, shift: boolean = false) {
    this.code = code;
    this.shift = shift;
  }
}

class RustDeskCodec {
  private pending: Array<number> = [];

  static punchHole(remoteId: string, licenceKey: string): ArrayBuffer {
    const request: Array<number> = [];
    RustDeskCodec.writeString(request, 1, remoteId);
    RustDeskCodec.writeString(request, 3, licenceKey);
    RustDeskCodec.writeString(request, 6, '1.4.7');

    const rendezvous: Array<number> = [];
    RustDeskCodec.writeBytes(rendezvous, 8, request);
    return RustDeskCodec.frame(rendezvous);
  }

  static requestRelay(remoteId: string, uuid: string, relayServer: string,
    licenceKey: string, announce: boolean): ArrayBuffer {
    const request: Array<number> = [];
    RustDeskCodec.writeString(request, 1, remoteId);
    RustDeskCodec.writeString(request, 2, uuid);
    if (announce) {
      RustDeskCodec.writeString(request, 4, relayServer);
      RustDeskCodec.writeBool(request, 5, true);
    } else {
      RustDeskCodec.writeString(request, 6, licenceKey);
    }
    const rendezvous: Array<number> = [];
    RustDeskCodec.writeBytes(rendezvous, 18, request);
    return RustDeskCodec.frame(rendezvous);
  }

  static publicKey(material: SessionMaterial): ArrayBuffer {
    const value: Array<number> = [];
    RustDeskCodec.writeBytes(value, 1, RustDeskCodec.bufferBytes(material.publicKey));
    RustDeskCodec.writeBytes(value, 2, RustDeskCodec.bufferBytes(material.sealedKey));
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 4, value);
    return RustDeskCodec.frame(message);
  }

  static login(remoteId: string, password: ArrayBuffer, myId: string): ArrayBuffer {
    const request: Array<number> = [];
    RustDeskCodec.writeString(request, 1, remoteId);
    RustDeskCodec.writeBytes(request, 2, RustDeskCodec.bufferBytes(password));
    RustDeskCodec.writeString(request, 4, myId);
    RustDeskCodec.writeString(request, 5, 'HarmonyOS RustDesk');
    const decoding: Array<number> = [];
    RustDeskCodec.writeInt(decoding, 1, 1); // VP9
    RustDeskCodec.writeInt(decoding, 2, 1); // H.264
    RustDeskCodec.writeInt(decoding, 3, 1); // H.265
    RustDeskCodec.writeInt(decoding, 4, 2); // PreferCodec::H264
    RustDeskCodec.writeInt(decoding, 5, 1); // VP8
    const option: Array<number> = [];
    RustDeskCodec.writeInt(option, 3, 2); // BoolOption::Yes — request the real remote cursor.
    RustDeskCodec.writeBytes(option, 10, decoding);
    RustDeskCodec.writeBytes(request, 6, option);
    RustDeskCodec.writeString(request, 11, '1.4.7');
    RustDeskCodec.writeString(request, 13, 'HarmonyOS');
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 7, request);
    return RustDeskCodec.bytesBuffer(message);
  }

  static loginResult(packet: Array<number>): LoginResult | undefined {
    const cursor = new ProtoCursor(packet);
    let field = cursor.next();
    while (field !== undefined) {
      if (field.number === 8 && field.wireType === 2) {
        const result = new LoginResult();
        const response = new ProtoCursor(field.bytes);
        let item = response.next();
        while (item !== undefined) {
          if (item.number === 1 && item.wireType === 2) {
            result.error = RustDeskCodec.utf8String(item.bytes);
          } else if (item.number === 2 && item.wireType === 2) {
            result.accepted = true;
            const peer = new ProtoCursor(item.bytes);
            let peerField = peer.next();
            while (peerField !== undefined) {
              if (peerField.number === 2 && peerField.wireType === 2) {
                result.hostname = RustDeskCodec.utf8String(peerField.bytes);
              } else if (peerField.number === 3 && peerField.wireType === 2) {
                result.platform = RustDeskCodec.utf8String(peerField.bytes);
              } else if (peerField.number === 7 && peerField.wireType === 2) {
                result.version = RustDeskCodec.utf8String(peerField.bytes);
              } else if (peerField.number === 4 && peerField.wireType === 2 && result.width === 0) {
                const display = new ProtoCursor(peerField.bytes);
                let displayField = display.next();
                while (displayField !== undefined) {
                  if (displayField.number === 3 && displayField.wireType === 0) result.width = displayField.value;
                  if (displayField.number === 4 && displayField.wireType === 0) result.height = displayField.value;
                  displayField = display.next();
                }
              }
              peerField = peer.next();
            }
          }
          item = response.next();
        }
        return result;
      }
      field = cursor.next();
    }
    return undefined;
  }

  static hasVideoFrame(packet: Array<number>): boolean {
    const cursor = new ProtoCursor(packet);
    let field = cursor.next();
    while (field !== undefined) {
      if (field.number === 6 && field.wireType === 2) return true;
      field = cursor.next();
    }
    return false;
  }

  static videoPacket(packet: Array<number>): VideoPacket | undefined {
    const message = new ProtoCursor(packet);
    let field = message.next();
    while (field !== undefined) {
      if (field.number === 6 && field.wireType === 2) {
        const result = new VideoPacket();
        const video = new ProtoCursor(field.bytes);
        let videoField = video.next();
        while (videoField !== undefined) {
          if (videoField.wireType === 2 && (videoField.number === 6 || videoField.number === 10 ||
            videoField.number === 11 || videoField.number === 12 || videoField.number === 13)) {
            if (videoField.number === 6) result.codec = 'vp9';
            if (videoField.number === 10) result.codec = 'h264';
            if (videoField.number === 11) result.codec = 'h265';
            if (videoField.number === 12) result.codec = 'vp8';
            if (videoField.number === 13) result.codec = 'av1';
            const frames = new ProtoCursor(videoField.bytes);
            let framesField = frames.next();
            while (framesField !== undefined) {
              if (framesField.number === 1 && framesField.wireType === 2) {
                const encoded = new EncodedFrame();
                const frame = new ProtoCursor(framesField.bytes);
                let frameField = frame.next();
                while (frameField !== undefined) {
                  if (frameField.number === 1 && frameField.wireType === 2) encoded.data = frameField.bytes;
                  if (frameField.number === 2 && frameField.wireType === 0) encoded.key = frameField.value !== 0;
                  if (frameField.number === 3 && frameField.wireType === 0) encoded.pts = frameField.value;
                  frameField = frame.next();
                }
                if (encoded.data.length > 0) result.frames.push(encoded);
              }
              framesField = frames.next();
            }
          }
          videoField = video.next();
        }
        return result.codec.length > 0 ? result : undefined;
      }
      field = message.next();
    }
    return undefined;
  }

  static hashChallenge(packet: Array<number>): HashChallenge | undefined {
    const cursor = new ProtoCursor(packet);
    let field = cursor.next();
    while (field !== undefined) {
      if (field.number === 9 && field.wireType === 2) {
        const result = new HashChallenge();
        const hash = new ProtoCursor(field.bytes);
        let item = hash.next();
        while (item !== undefined) {
          if (item.number === 1 && item.wireType === 2) result.salt = RustDeskCodec.asciiString(item.bytes);
          if (item.number === 2 && item.wireType === 2) result.challenge = RustDeskCodec.asciiString(item.bytes);
          item = hash.next();
        }
        return result;
      }
      field = cursor.next();
    }
    return undefined;
  }

  static shouldEchoTestDelay(packet: Array<number>): boolean {
    const message = new ProtoCursor(packet);
    let field = message.next();
    while (field !== undefined) {
      if (field.number === 5 && field.wireType === 2) {
        const delay = new ProtoCursor(field.bytes);
        let fromClient = false;
        let item = delay.next();
        while (item !== undefined) {
          if (item.number === 2 && item.wireType === 0) fromClient = item.value !== 0;
          item = delay.next();
        }
        return !fromClient;
      }
      field = message.next();
    }
    return false;
  }

  static frameBuffer(payload: ArrayBuffer): ArrayBuffer {
    return RustDeskCodec.frame(RustDeskCodec.bufferBytes(payload));
  }

  static mouseEvent(mask: number, x: number, y: number): ArrayBuffer {
    const event: Array<number> = [];
    RustDeskCodec.writeInt(event, 1, mask);
    RustDeskCodec.writeSignedInt(event, 2, x);
    RustDeskCodec.writeSignedInt(event, 3, y);
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 10, event);
    return RustDeskCodec.bytesBuffer(message);
  }

  static keyText(text: string, modifiers: Array<number> = []): ArrayBuffer {
    const event: Array<number> = [];
    RustDeskCodec.writeBool(event, 2, true);
    RustDeskCodec.writeUtf8String(event, 6, text);
    modifiers.forEach((modifier: number) => RustDeskCodec.writeInt(event, 8, modifier));
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 15, event);
    return RustDeskCodec.bytesBuffer(message);
  }

  static keyCharacter(character: string): ArrayBuffer {
    const event: Array<number> = [];
    RustDeskCodec.writeBool(event, 2, true);
    RustDeskCodec.writeInt(event, 4, character.charCodeAt(0));
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 15, event);
    return RustDeskCodec.bytesBuffer(message);
  }

  static keyPosition(code: number, down: boolean): ArrayBuffer {
    const event: Array<number> = [];
    RustDeskCodec.writeBool(event, 1, down);
    // A macOS ANSI "A" key has physical code 0. Because `chr` is a oneof field,
    // its tag must still be present when the scalar value is zero.
    RustDeskCodec.writeVarint(event, 4 * 8);
    RustDeskCodec.writeVarint(event, code);
    RustDeskCodec.writeInt(event, 9, 1); // KeyboardMode::Map — physical key position.
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 15, event);
    return RustDeskCodec.bytesBuffer(message);
  }

  static clipboardText(text: string): ArrayBuffer {
    const clipboard: Array<number> = [];
    RustDeskCodec.writeUtf8String(clipboard, 2, text);
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 16, clipboard);
    return RustDeskCodec.bytesBuffer(message);
  }

  static refreshVideo(): ArrayBuffer {
    const misc: Array<number> = [];
    RustDeskCodec.writeBool(misc, 10, true);
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 19, misc);
    return RustDeskCodec.bytesBuffer(message);
  }

  static chatText(text: string): ArrayBuffer {
    const chat: Array<number> = [];
    RustDeskCodec.writeUtf8String(chat, 1, text);
    const misc: Array<number> = [];
    RustDeskCodec.writeBytes(misc, 4, chat);
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 19, misc);
    return RustDeskCodec.bytesBuffer(message);
  }

  static receivedChatText(packet: Array<number>): string | undefined {
    const message = new ProtoCursor(packet);
    let field = message.next();
    while (field !== undefined) {
      if (field.number === 19 && field.wireType === 2) {
        const misc = new ProtoCursor(field.bytes);
        let item = misc.next();
        while (item !== undefined) {
          if (item.number === 4 && item.wireType === 2) {
            const chat = new ProtoCursor(item.bytes);
            let chatField = chat.next();
            while (chatField !== undefined) {
              if (chatField.number === 1 && chatField.wireType === 2) {
                return RustDeskCodec.utf8String(chatField.bytes);
              }
              chatField = chat.next();
            }
          }
          item = misc.next();
        }
      }
      field = message.next();
    }
    return undefined;
  }

  private static parseClipboard(bytes: Array<number>): string | undefined {
    const clipboard = new ProtoCursor(bytes);
    let compressed = false;
    let format = 0;
    let content: Array<number> = [];
    let field = clipboard.next();
    while (field !== undefined) {
      if (field.number === 1 && field.wireType === 0) compressed = field.value !== 0;
      if (field.number === 2 && field.wireType === 2) content = field.bytes;
      if (field.number === 5 && field.wireType === 0) format = field.value;
      field = clipboard.next();
    }
    if (compressed || format !== 0 || content.length === 0) return undefined;
    return RustDeskCodec.utf8String(content);
  }

  static receivedClipboardText(packet: Array<number>): string | undefined {
    const message = new ProtoCursor(packet);
    let field = message.next();
    while (field !== undefined) {
      if (field.number === 16 && field.wireType === 2) {
        return RustDeskCodec.parseClipboard(field.bytes);
      }
      if (field.number === 28 && field.wireType === 2) {
        const multi = new ProtoCursor(field.bytes);
        let item = multi.next();
        while (item !== undefined) {
          if (item.number === 1 && item.wireType === 2) {
            const text = RustDeskCodec.parseClipboard(item.bytes);
            if (text !== undefined) return text;
          }
          item = multi.next();
        }
      }
      field = message.next();
    }
    return undefined;
  }

  static cursorPosition(packet: Array<number>): Array<number> | undefined {
    const message = new ProtoCursor(packet);
    let field = message.next();
    while (field !== undefined) {
      if (field.number === 13 && field.wireType === 2) {
        const position = new ProtoCursor(field.bytes);
        let x = 0;
        let y = 0;
        let item = position.next();
        while (item !== undefined) {
          if (item.number === 1 && item.wireType === 0) x = RustDeskCodec.decodeSigned(item.value);
          if (item.number === 2 && item.wireType === 0) y = RustDeskCodec.decodeSigned(item.value);
          item = position.next();
        }
        return [x, y];
      }
      field = message.next();
    }
    return undefined;
  }

  static cursorImage(packet: Array<number>): RemoteCursorImage | undefined {
    const message = new ProtoCursor(packet);
    let field = message.next();
    while (field !== undefined) {
      if (field.number === 12 && field.wireType === 2) {
        const result = new RemoteCursorImage();
        let compressed: Array<number> = [];
        const cursor = new ProtoCursor(field.bytes);
        let item = cursor.next();
        while (item !== undefined) {
          if (item.number === 1 && item.wireType === 0) result.id = item.value.toString();
          if (item.number === 2 && item.wireType === 0) result.hotX = RustDeskCodec.decodeSigned(item.value);
          if (item.number === 3 && item.wireType === 0) result.hotY = RustDeskCodec.decodeSigned(item.value);
          if (item.number === 4 && item.wireType === 0) result.width = item.value;
          if (item.number === 5 && item.wireType === 0) result.height = item.value;
          if (item.number === 6 && item.wireType === 2) compressed = item.bytes;
          item = cursor.next();
        }
        if (result.id.length === 0 || result.width <= 0 || result.height <= 0 || compressed.length === 0 ||
          result.width > 2048 || result.height > 2048) return undefined;
        try {
          result.colors = decompressZstd(RustDeskCodec.bytesBuffer(compressed), result.width * result.height * 4);
        } catch (_) {
          return undefined;
        }
        return result;
      }
      field = message.next();
    }
    return undefined;
  }

  static cursorId(packet: Array<number>): string | undefined {
    const message = new ProtoCursor(packet);
    let field = message.next();
    while (field !== undefined) {
      if (field.number === 14 && field.wireType === 0) return field.value.toString();
      field = message.next();
    }
    return undefined;
  }

  private static decodeSigned(value: number): number {
    return value % 2 === 0 ? value / 2 : -(value + 1) / 2;
  }

  static controlKey(code: number, modifiers: Array<number> = []): ArrayBuffer {
    const event: Array<number> = [];
    RustDeskCodec.writeBool(event, 2, true);
    RustDeskCodec.writeInt(event, 3, code);
    modifiers.forEach((modifier: number) => RustDeskCodec.writeInt(event, 8, modifier));
    const message: Array<number> = [];
    RustDeskCodec.writeBytes(message, 15, event);
    return RustDeskCodec.bytesBuffer(message);
  }

  append(buffer: ArrayBuffer): Array<Array<number>> {
    const incoming = new Uint8Array(buffer);
    for (let index = 0; index < incoming.length; index += 1) {
      this.pending.push(incoming[index]);
    }

    const packets: Array<Array<number>> = [];
    while (this.pending.length > 0) {
      const headLength = (this.pending[0] & 0x03) + 1;
      if (this.pending.length < headLength) {
        break;
      }
      let encodedLength = 0;
      let scale = 1;
      for (let index = 0; index < headLength; index += 1) {
        encodedLength += this.pending[index] * scale;
        scale *= 256;
      }
      const payloadLength = Math.floor(encodedLength / 4);
      if (payloadLength > 16 * 1024 * 1024) {
        throw new Error('RustDesk 数据包超过 16 MiB 安全限制');
      }
      if (this.pending.length < headLength + payloadLength) {
        break;
      }
      packets.push(this.pending.slice(headLength, headLength + payloadLength));
      this.pending = this.pending.slice(headLength + payloadLength);
    }
    return packets;
  }

  static describeRendezvous(packet: Array<number>): string {
    const cursor = new ProtoCursor(packet);
    let field = cursor.next();
    while (field !== undefined) {
      if (field.number === 11 && field.wireType === 2) {
        return RustDeskCodec.describePunchHoleResponse(field.bytes);
      }
      if (field.number === 19 && field.wireType === 2) {
        return 'relay';
      }
      field = cursor.next();
    }
    return 'unexpected';
  }

  static signedPeerIdentity(packet: Array<number>): Array<number> {
    const cursor = new ProtoCursor(packet);
    let field = cursor.next();
    while (field !== undefined) {
      if (field.number === 11 && field.wireType === 2) {
        const response = new ProtoCursor(field.bytes);
        let responseField = response.next();
        while (responseField !== undefined) {
          if (responseField.number === 2 && responseField.wireType === 2) {
            return responseField.bytes;
          }
          responseField = response.next();
        }
      }
      field = cursor.next();
    }
    return [];
  }

  static routeInfo(packet: Array<number>): RouteInfo {
    const route = new RouteInfo();
    const cursor = new ProtoCursor(packet);
    let field = cursor.next();
    while (field !== undefined) {
      if (field.number === 11 && field.wireType === 2) {
        const response = new ProtoCursor(field.bytes);
        let item = response.next();
        while (item !== undefined) {
          if (item.number === 2 && item.wireType === 2) route.signedIdentity = item.bytes;
          if (item.number === 4 && item.wireType === 2) route.relayServer = RustDeskCodec.asciiString(item.bytes);
          if (item.number === 7 && item.wireType === 2) route.refusal = RustDeskCodec.asciiString(item.bytes);
          item = response.next();
        }
      } else if (field.number === 19 && field.wireType === 2) {
        const response = new ProtoCursor(field.bytes);
        let item = response.next();
        while (item !== undefined) {
          if (item.number === 2 && item.wireType === 2) route.relayUuid = RustDeskCodec.asciiString(item.bytes);
          if (item.number === 3 && item.wireType === 2) route.relayServer = RustDeskCodec.asciiString(item.bytes);
          if (item.number === 5 && item.wireType === 2) route.signedIdentity = item.bytes;
          if (item.number === 6 && item.wireType === 2) route.refusal = RustDeskCodec.asciiString(item.bytes);
          item = response.next();
        }
      }
      field = cursor.next();
    }
    return route;
  }

  static signedId(packet: Array<number>): Array<number> {
    const cursor = new ProtoCursor(packet);
    let field = cursor.next();
    while (field !== undefined) {
      if (field.number === 3 && field.wireType === 2) {
        const signed = new ProtoCursor(field.bytes);
        let item = signed.next();
        while (item !== undefined) {
          if (item.number === 1 && item.wireType === 2) return item.bytes;
          item = signed.next();
        }
      }
      field = cursor.next();
    }
    return [];
  }

  static decodePeerIdentity(buffer: ArrayBuffer): PeerIdentity {
    const bytes = RustDeskCodec.bufferBytes(buffer);
    const cursor = new ProtoCursor(bytes);
    let id = '';
    let publicKey: Array<number> = [];
    let field = cursor.next();
    while (field !== undefined) {
      if (field.number === 1 && field.wireType === 2) {
        id = RustDeskCodec.asciiString(field.bytes);
      } else if (field.number === 2 && field.wireType === 2) {
        publicKey = field.bytes;
      }
      field = cursor.next();
    }
    if (id.length === 0 || publicKey.length !== 32) {
      throw new Error('Server Pro 返回的签名设备身份无效');
    }
    return new PeerIdentity(id, publicKey);
  }

  static bytesBuffer(bytes: Array<number>): ArrayBuffer {
    return new Uint8Array(bytes).buffer;
  }

  private static describePunchHoleResponse(data: Array<number>): string {
    const cursor = new ProtoCursor(data);
    let hasRoute = false;
    let failure = 0;
    let otherFailure = '';
    let field = cursor.next();
    while (field !== undefined) {
      if ((field.number === 1 || field.number === 2 || field.number === 4 ||
        field.number === 11) && field.bytes.length > 0) {
        hasRoute = true;
      } else if (field.number === 3 && field.wireType === 0) {
        failure = field.value;
      } else if (field.number === 7 && field.wireType === 2) {
        otherFailure = RustDeskCodec.asciiString(field.bytes);
      }
      field = cursor.next();
    }
    if (hasRoute) {
      return 'route';
    }
    if (otherFailure.length > 0) {
      return `other:${otherFailure}`;
    }
    if (failure === 2) {
      return 'offline';
    }
    if (failure === 3) {
      return 'license_mismatch';
    }
    if (failure === 4) {
      return 'license_overuse';
    }
    return 'id_not_exist';
  }

  private static writeString(output: Array<number>, field: number, value: string): void {
    if (value.length === 0) {
      return;
    }
    const bytes: Array<number> = [];
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code > 0x7f) {
        throw new Error('RustDesk ID 和服务器 Key 必须使用 ASCII 字符');
      }
      bytes.push(code);
    }
    RustDeskCodec.writeBytes(output, field, bytes);
  }

  private static writeUtf8String(output: Array<number>, field: number, value: string): void {
    if (value.length === 0) return;
    const encoded = encodeURIComponent(value);
    const bytes: Array<number> = [];
    for (let index = 0; index < encoded.length; index += 1) {
      if (encoded.charAt(index) === '%' && index + 2 < encoded.length) {
        bytes.push(parseInt(encoded.substring(index + 1, index + 3), 16));
        index += 2;
      } else {
        bytes.push(encoded.charCodeAt(index));
      }
    }
    RustDeskCodec.writeBytes(output, field, bytes);
  }

  private static writeBytes(output: Array<number>, field: number, value: Array<number>): void {
    RustDeskCodec.writeVarint(output, field * 8 + 2);
    RustDeskCodec.writeVarint(output, value.length);
    value.forEach((byte: number) => output.push(byte));
  }

  private static writeBool(output: Array<number>, field: number, value: boolean): void {
    if (!value) return;
    RustDeskCodec.writeVarint(output, field * 8);
    RustDeskCodec.writeVarint(output, 1);
  }

  private static writeInt(output: Array<number>, field: number, value: number): void {
    if (value === 0) return;
    RustDeskCodec.writeVarint(output, field * 8);
    RustDeskCodec.writeVarint(output, value);
  }

  private static writeSignedInt(output: Array<number>, field: number, value: number): void {
    const integer = Math.floor(value);
    const zigzag = integer >= 0 ? integer * 2 : -integer * 2 - 1;
    RustDeskCodec.writeVarint(output, field * 8);
    RustDeskCodec.writeVarint(output, zigzag);
  }

  private static writeVarint(output: Array<number>, value: number): void {
    let remaining = value;
    while (remaining >= 128) {
      output.push((remaining % 128) | 0x80);
      remaining = Math.floor(remaining / 128);
    }
    output.push(remaining);
  }

  private static frame(payload: Array<number>): ArrayBuffer {
    const output: Array<number> = [];
    const length = payload.length;
    if (length <= 0x3f) {
      output.push(length * 4);
    } else if (length <= 0x3fff) {
      const header = length * 4 + 1;
      output.push(header & 0xff, Math.floor(header / 256) & 0xff);
    } else if (length <= 0x3fffff) {
      const header = length * 4 + 2;
      output.push(header & 0xff, Math.floor(header / 256) & 0xff,
        Math.floor(header / 65536) & 0xff);
    } else {
      throw new Error('RustDesk 请求数据包过大');
    }
    payload.forEach((byte: number) => output.push(byte));
    return new Uint8Array(output).buffer;
  }

  private static asciiString(bytes: Array<number>): string {
    let value = '';
    bytes.forEach((byte: number) => value += String.fromCharCode(byte));
    return value;
  }

  private static utf8String(bytes: Array<number>): string {
    let encoded = '';
    bytes.forEach((byte: number) => encoded += `%${byte.toString(16).padStart(2, '0')}`);
    try {
      return decodeURIComponent(encoded);
    } catch (_) {
      return RustDeskCodec.asciiString(bytes);
    }
  }

  static bufferBytes(buffer: ArrayBuffer): Array<number> {
    const source = new Uint8Array(buffer);
    const result: Array<number> = [];
    for (let index = 0; index < source.length; index += 1) {
      result.push(source[index]);
    }
    return result;
  }
}

class RendezvousRemoteCore implements RemoteCore {
  private tcp?: socket.TCPSocket;
  private listener?: ConnectionListener;
  private generation: number = 0;
  private responseTimer: number = -1;
  private peerSigningKey: Array<number> = [];
  private cryptoSessionId: number = 0;
  private loginAccepted: boolean = false;
  private videoPacketSeen: boolean = false;
  private clientId: string = '';
  private remoteWidth: number = 0;
  private remoteHeight: number = 0;
  private remotePlatformName: string = '';
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  private clipboardListener?: (text: string) => void;
  private chatListener?: (text: string) => void;
  private cursorListener?: (x: number, y: number) => void;
  private cursorImageListener?: (cursor: RemoteCursorImage) => void;
  private cursorIdListener?: (id: string) => void;

  connect(request: ConnectRequest, listener: ConnectionListener): void {
    this.disconnectSocket();
    this.generation += 1;
    const generation = this.generation;
    this.listener = listener;
    this.loginAccepted = false;
    this.videoPacketSeen = false;
    this.clientId = this.newClientId();
    this.remoteWidth = 0;
    this.remoteHeight = 0;
    this.remotePlatformName = '';
    resetVideoDecoder();
    listener(ConnectionState.Connecting, `正在连接真实 ID 服务器 ${request.serverProfile.idServer}`);
    this.open(request, generation);
  }

  disconnect(): void {
    this.generation += 1;
    this.disconnectSocket();
    resetVideoDecoder();
    if (this.listener) {
      this.listener(ConnectionState.Idle, '连接已断开');
    }
  }

  sendPointer(x: number, y: number, mask: number): void {
    if (this.cryptoSessionId === 0 || !this.tcp) return;
    const eventType = mask & 7;
    let remoteX = Math.floor(x);
    let remoteY = Math.floor(y);
    if (eventType !== 3 && eventType !== 4) {
      if (this.remoteWidth <= 0 || this.remoteHeight <= 0 || this.viewportWidth <= 0 ||
        this.viewportHeight <= 0) return;
      remoteX = Math.max(0, Math.min(this.remoteWidth - 1,
        Math.floor(x * this.remoteWidth / this.viewportWidth)));
      remoteY = Math.max(0, Math.min(this.remoteHeight - 1,
        Math.floor(y * this.remoteHeight / this.viewportHeight)));
    }
    try {
      const message = RustDeskCodec.mouseEvent(mask, remoteX, remoteY);
      const encrypted = encrypt(this.cryptoSessionId, message);
      this.tcp.send({ data: RustDeskCodec.frameBuffer(encrypted) }).catch(() => {
      });
    } catch (_) {
    }
  }

  sendKey(keyCode: number, pressed: boolean): void {
    if (!pressed) return;
    this.sendEncryptedInput(RustDeskCodec.controlKey(keyCode));
  }

  sendShortcut(keyCode: number, modifiers: Array<number>): void {
    this.sendEncryptedInput(RustDeskCodec.controlKey(keyCode, modifiers));
  }

  sendTextShortcut(text: string, modifiers: Array<number>): void {
    if (text.length === 0) return;
    this.sendEncryptedInput(RustDeskCodec.keyText(text, modifiers));
  }

  sendText(text: string): void {
    if (text.length === 0) return;
    // RustDesk's mobile clients forward committed IME text through KeyEvent.seq.
    // Sending each UTF-16 code unit as a physical key breaks CJK input and any
    // character that is not present on the remote physical keyboard layout.
    this.sendEncryptedInput(RustDeskCodec.keyText(text));
  }

  sendCharacter(text: string): void {
    if (text.length === 0) return;
    const character = text.charAt(0);
    const stroke = this.physicalKeyStroke(character);
    if (stroke === undefined) {
      this.sendEncryptedInput(RustDeskCodec.keyCharacter(character));
      return;
    }
    if (stroke.shift) this.sendPhysicalKey(this.shiftPositionCode(), true);
    this.sendPhysicalKey(stroke.code, true);
    this.sendPhysicalKey(stroke.code, false);
    if (stroke.shift) this.sendPhysicalKey(this.shiftPositionCode(), false);
  }

  private sendPhysicalKey(code: number, down: boolean): void {
    if (code < 0) return;
    this.sendEncryptedInput(RustDeskCodec.keyPosition(code, down));
  }

  private shiftPositionCode(): number {
    const platform = this.remotePlatformName.toLowerCase();
    if (platform.includes('mac')) return 56;
    if (platform.includes('linux')) return 50;
    return 42;
  }

  private physicalKeyStroke(character: string): PhysicalKeyStroke | undefined {
    const platform = this.remotePlatformName.toLowerCase();
    if (!platform.includes('mac') && !platform.includes('windows') && !platform.includes('linux')) {
      return undefined;
    }
    const lower = character.toLowerCase();
    let shift = character !== lower;
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    const letterIndex = letters.indexOf(lower);
    if (letterIndex >= 0) {
      const macCodes: number[] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
        45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6];
      const windowsCodes: number[] = [30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
        49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44];
      const base = platform.includes('mac') ? macCodes[letterIndex] : windowsCodes[letterIndex];
      return new PhysicalKeyStroke(platform.includes('linux') ? base + 8 : base, shift);
    }
    const unshifted = '1234567890-=[]\\;\',./` ';
    const shifted = '!@#$%^&*()_+{}|:"<>?~ ';
    let index = unshifted.indexOf(character);
    if (index < 0) {
      index = shifted.indexOf(character);
      shift = index >= 0 && character !== ' ';
    } else {
      shift = false;
    }
    if (index < 0) return undefined;
    const macCodes: number[] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 33,
      30, 42, 41, 39, 43, 47, 44, 50, 49];
    const windowsCodes: number[] = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 26,
      27, 43, 39, 40, 51, 52, 53, 41, 57];
    const base = platform.includes('mac') ? macCodes[index] : windowsCodes[index];
    return new PhysicalKeyStroke(platform.includes('linux') ? base + 8 : base, shift);
  }

  sendChatText(text: string): void {
    if (text.trim().length === 0) return;
    this.sendEncryptedInput(RustDeskCodec.chatText(text));
  }

  sendClipboardText(text: string): void {
    if (text.length === 0) return;
    this.sendEncryptedInput(RustDeskCodec.clipboardText(text));
  }

  setClipboardListener(listener: ((text: string) => void) | undefined): void {
    this.clipboardListener = listener;
  }

  setChatListener(listener: ((text: string) => void) | undefined): void {
    this.chatListener = listener;
  }

  setCursorListener(listener: ((x: number, y: number) => void) | undefined): void {
    this.cursorListener = listener;
  }

  setCursorImageListener(listener: ((cursor: RemoteCursorImage) => void) | undefined): void {
    this.cursorImageListener = listener;
  }

  setCursorIdListener(listener: ((id: string) => void) | undefined): void {
    this.cursorIdListener = listener;
  }

  setVideoSurface(surfaceId: string): void {
    setVideoSurface(surfaceId);
  }

  setVideoViewport(width: number, height: number): void {
    this.viewportWidth = Math.max(0, width);
    this.viewportHeight = Math.max(0, height);
  }

  refreshVideo(): void {
    this.sendEncryptedInput(RustDeskCodec.refreshVideo());
  }

  videoStatus(): string {
    return getVideoDecoderStatus();
  }

  videoRenderedFrames(): number {
    return getVideoRenderedFrames();
  }

  videoAspectRatio(): number {
    if (this.remoteWidth <= 0 || this.remoteHeight <= 0) return 0;
    return this.remoteWidth / this.remoteHeight;
  }

  videoWidth(): number {
    return this.remoteWidth;
  }

  videoHeight(): number {
    return this.remoteHeight;
  }

  private sendEncryptedInput(message: ArrayBuffer): void {
    if (this.cryptoSessionId === 0 || !this.tcp) return;
    try {
      const encrypted = encrypt(this.cryptoSessionId, message);
      this.tcp.send({ data: RustDeskCodec.frameBuffer(encrypted) }).catch(() => {
      });
    } catch (_) {
    }
  }

  capabilities(): RemoteCapabilities {
    const result = new RemoteCapabilities();
    result.clipboard = true;
    result.hardwareDecode = true;
    result.nativeCore = true;
    return result;
  }

  private async open(request: ConnectRequest, generation: number): Promise<void> {
    try {
      const endpoint = this.parseEndpoint(request.serverProfile.idServer);
      const tcp = socket.constructTCPSocketInstance();
      this.tcp = tcp;
      const codec = new RustDeskCodec();

      tcp.on('message', (info: socket.SocketMessageInfo) => {
        if (generation !== this.generation) {
          return;
        }
        try {
          const packets = codec.append(info.message);
          packets.forEach((packet: Array<number>) =>
            this.handlePacket(packet, request, generation));
        } catch (error) {
          this.fail(generation, `RustDesk 协议解析失败：${String(error)}`);
        }
      });
      tcp.on('error', (error: Error) => {
        this.fail(generation, `ID 服务器连接错误：${socketErrorText(error)}`);
      });

      await tcp.bind({ address: '0.0.0.0', port: 0, family: 1 });
      await tcp.connect({
        address: { address: endpoint.host, port: endpoint.port },
        timeout: 8000
      });
      if (generation !== this.generation) {
        return;
      }
      listenerSafe(this.listener, ConnectionState.Authenticating,
        `已连接 hbbs，正在查询远端 ${request.remoteId}`);
      await tcp.send({
        data: RustDeskCodec.punchHole(request.remoteId, request.serverProfile.publicKey)
      });
      this.responseTimer = setTimeout(() => {
        this.fail(generation, 'hbbs 已连接，但等待远端路由响应超时');
      }, 10000);
    } catch (error) {
      this.fail(generation, `无法连接真实 ID 服务器：${String(error)}`);
    }
  }

  private handlePacket(packet: Array<number>, request: ConnectRequest, generation: number): void {
    const result = RustDeskCodec.describeRendezvous(packet);
    if (result === 'route' || result === 'relay') {
      try {
        const route = RustDeskCodec.routeInfo(packet);
        const signedIdentity = route.signedIdentity;
        if (signedIdentity.length === 0) {
          throw new Error('hbbs 未返回签名设备公钥');
        }
        const verified = verifySignedMessage(RustDeskCodec.bytesBuffer(signedIdentity),
          request.serverProfile.publicKey);
        const peer = RustDeskCodec.decodePeerIdentity(verified);
        if (peer.id !== request.remoteId) {
          throw new Error(`签名设备 ID ${peer.id} 与请求 ID 不一致`);
        }
        this.peerSigningKey = peer.publicKey;
        this.clearResponseTimer();
        const relayServer = request.serverProfile.relayServer.trim().length > 0 ?
          request.serverProfile.relayServer.trim() : route.relayServer;
        if (relayServer.length === 0) {
          throw new Error('服务器未提供可用的 hbbr 中继地址');
        }
        listenerSafe(this.listener, ConnectionState.Authenticating,
          'Server Pro 身份验证通过，正在申请真实 hbbr 中继通道');
        if (route.relayUuid.length > 0) {
          this.openRelay(request, relayServer, route.relayUuid, generation);
        } else {
          this.requestRelay(request, relayServer, generation);
        }
      } catch (error) {
        this.fail(generation, `Server Pro 身份验证失败：${String(error)}`);
      }
    } else if (result === 'offline') {
      this.fail(generation, '远端设备当前离线');
    } else if (result === 'license_mismatch') {
      this.fail(generation, 'Server Pro Key 与服务器不匹配');
    } else if (result === 'license_overuse') {
      this.fail(generation, 'Server Pro 许可证已超出设备或并发限制');
    } else if (result.startsWith('other:')) {
      this.fail(generation, `服务器拒绝连接：${result.substring(6)}`);
    } else if (result === 'id_not_exist') {
      this.fail(generation, '远程 ID 不存在');
    }
  }

  private async requestRelay(request: ConnectRequest, relayServer: string,
    generation: number): Promise<void> {
    try {
      this.disconnectSocket();
      const endpoint = this.parseEndpoint(request.serverProfile.idServer);
      const uuid = this.uuid();
      const tcp = socket.constructTCPSocketInstance();
      this.tcp = tcp;
      const codec = new RustDeskCodec();
      tcp.on('message', (info: socket.SocketMessageInfo) => {
        if (generation !== this.generation || this.tcp !== tcp) return;
        try {
          codec.append(info.message).forEach((packet: Array<number>) => {
            const route = RustDeskCodec.routeInfo(packet);
            if (route.refusal.length > 0) {
              this.fail(generation, `hbbr 拒绝中继：${route.refusal}`);
            } else if (RustDeskCodec.describeRendezvous(packet) === 'relay') {
              this.clearResponseTimer();
              this.openRelay(request, route.relayServer.length > 0 ? route.relayServer : relayServer,
                route.relayUuid.length > 0 ? route.relayUuid : uuid, generation);
            }
          });
        } catch (error) {
          this.fail(generation, `中继响应解析失败：${String(error)}`);
        }
      });
      tcp.on('error', (error: Error) => {
        if (this.tcp === tcp) this.fail(generation, `申请中继失败：${socketErrorText(error)}`);
      });
      await tcp.bind({ address: '0.0.0.0', port: 0, family: 1 });
      await tcp.connect({ address: { address: endpoint.host, port: endpoint.port }, timeout: 8000 });
      if (generation !== this.generation || this.tcp !== tcp) return;
      await tcp.send({ data: RustDeskCodec.requestRelay(request.remoteId, uuid, relayServer,
        request.serverProfile.publicKey, true) });
      this.responseTimer = setTimeout(() => this.fail(generation, '等待 hbbs 分配中继超时'), 10000);
    } catch (error) {
      this.fail(generation, `无法申请 RustDesk 中继：${String(error)}`);
    }
  }

  private async openRelay(request: ConnectRequest, relayServer: string, uuid: string,
    generation: number): Promise<void> {
    try {
      this.disconnectSocket();
      const endpoint = this.parseRelayEndpoint(relayServer);
      const tcp = socket.constructTCPSocketInstance();
      this.tcp = tcp;
      const codec = new RustDeskCodec();
      tcp.on('message', (info: socket.SocketMessageInfo) => {
        if (generation !== this.generation || this.tcp !== tcp) return;
        try {
          codec.append(info.message).forEach((packet: Array<number>) => {
            this.handleRelayPacket(packet, request, generation).catch((error: Error) =>
              this.fail(generation, `中继会话处理失败：${error.message}`));
          });
        } catch (error) {
          this.fail(generation, `中继数据解析失败：${String(error)}`);
        }
      });
      tcp.on('error', (error: Error) => {
        if (this.tcp === tcp) this.fail(generation, `hbbr 中继连接错误：${socketErrorText(error)}`);
      });
      await tcp.bind({ address: '0.0.0.0', port: 0, family: 1 });
      await tcp.connect({ address: { address: endpoint.host, port: endpoint.port }, timeout: 10000 });
      if (generation !== this.generation || this.tcp !== tcp) return;
      listenerSafe(this.listener, ConnectionState.Authenticating,
        `已连接 hbbr ${endpoint.host}:${endpoint.port}，正在等待远端加密握手`);
      await tcp.send({ data: RustDeskCodec.requestRelay(request.remoteId, uuid, relayServer,
        request.serverProfile.publicKey, false) });
      this.responseTimer = setTimeout(() => this.fail(generation,
        '等待远端 SignedId 握手超时；请确认远端在线且 hbbr 21117 端口可访问'), 30000);
    } catch (error) {
      this.fail(generation, `无法建立 hbbr 中继：${String(error)}`);
    }
  }

  private async handleRelayPacket(packet: Array<number>, request: ConnectRequest,
    generation: number): Promise<void> {
    if (this.cryptoSessionId !== 0) {
      const plain = decrypt(this.cryptoSessionId, RustDeskCodec.bytesBuffer(packet));
      const plainPacket = RustDeskCodec.bufferBytes(plain);
      if (RustDeskCodec.shouldEchoTestDelay(plainPacket)) {
        if (!this.tcp) throw new Error('回复会话保活前中继已关闭');
        const keepAlive = encrypt(this.cryptoSessionId, plain);
        try {
          await this.tcp.send({ data: RustDeskCodec.frameBuffer(keepAlive) });
        } catch (error) {
          throw new Error(`回复会话保活失败：${String(error)}`);
        }
        return;
      }
      const challenge = RustDeskCodec.hashChallenge(plainPacket);
      if (challenge !== undefined) {
        const response = hashPassword(request.password, challenge.salt, challenge.challenge);
        const login = RustDeskCodec.login(request.remoteId, response, this.clientId);
        if (!this.tcp) throw new Error('发送登录请求前中继已关闭');
        const encrypted = encrypt(this.cryptoSessionId, login);
        try {
          await this.tcp.send({ data: RustDeskCodec.frameBuffer(encrypted) });
        } catch (error) {
          throw new Error(`发送加密登录请求失败：${String(error)}`);
        }
        listenerSafe(this.listener, ConnectionState.Authenticating,
          request.password.length > 0 ? '已发送加密密码登录，正在等待远端授权' :
            '已发送无密码登录，请在远端设备上点击接受');
        return;
      }
      const login = RustDeskCodec.loginResult(plainPacket);
      if (login !== undefined) {
        if (login.error === 'No Password Access') {
          listenerSafe(this.listener, ConnectionState.Authenticating,
            '远端已收到请求，请在远端 RustDesk 窗口中点击接受');
        } else if (login.error.length > 0) {
          this.fail(generation, this.loginError(login.error));
        } else if (login.accepted) {
          this.loginAccepted = true;
          this.remoteWidth = login.width;
          this.remoteHeight = login.height;
          this.remotePlatformName = login.platform;
          const peer = [login.hostname, login.platform, login.version].filter((value: string) =>
            value.length > 0).join(' · ');
          listenerSafe(this.listener, ConnectionState.Authenticating,
            `远端授权成功${peer.length > 0 ? `（${peer}）` : ''}，正在接收真实视频流`);
        }
        return;
      }
      const clipboardText = RustDeskCodec.receivedClipboardText(plainPacket);
      if (clipboardText !== undefined) {
        if (this.clipboardListener) this.clipboardListener(clipboardText);
        return;
      }
      const chatText = RustDeskCodec.receivedChatText(plainPacket);
      if (chatText !== undefined) {
        if (this.chatListener) this.chatListener(chatText);
        return;
      }
      const cursorImage = RustDeskCodec.cursorImage(plainPacket);
      if (cursorImage !== undefined) {
        if (this.cursorImageListener) this.cursorImageListener(cursorImage);
        return;
      }
      const cursorId = RustDeskCodec.cursorId(plainPacket);
      if (cursorId !== undefined) {
        if (this.cursorIdListener) this.cursorIdListener(cursorId);
        return;
      }
      const cursor = RustDeskCodec.cursorPosition(plainPacket);
      if (cursor !== undefined) {
        if (this.cursorListener && this.remoteWidth > 0 && this.remoteHeight > 0) {
          this.cursorListener(cursor[0] / this.remoteWidth, cursor[1] / this.remoteHeight);
        }
        return;
      }
      const video = RustDeskCodec.videoPacket(plainPacket);
      if (video !== undefined) {
        let accepted = false;
        video.frames.forEach((frame: EncodedFrame) => {
          if (pushVideoFrame(video.codec, RustDeskCodec.bytesBuffer(frame.data), frame.key, frame.pts,
            this.remoteWidth, this.remoteHeight)) accepted = true;
        });
        if (accepted && !this.videoPacketSeen) {
          this.videoPacketSeen = true;
          listenerSafe(this.listener, ConnectionState.Connected,
            `已接入 ${video.codec.toUpperCase()} 真实画面：${getVideoDecoderStatus()}`);
        } else if (!accepted && !this.videoPacketSeen) {
          listenerSafe(this.listener, ConnectionState.Authenticating,
            `已收到 ${video.codec.toUpperCase()} 视频，但解码器未就绪：${getVideoDecoderStatus()}`);
        }
      }
      return;
    }
    const signedId = RustDeskCodec.signedId(packet);
    if (signedId.length === 0) {
      throw new Error('远端没有发送 RustDesk SignedId');
    }
    const verified = verifySignedWithKey(RustDeskCodec.bytesBuffer(signedId),
      RustDeskCodec.bytesBuffer(this.peerSigningKey));
    const peer = RustDeskCodec.decodePeerIdentity(verified);
    if (peer.id !== request.remoteId) {
      throw new Error(`中继远端 ID ${peer.id} 与请求 ID 不一致`);
    }
    const material = createSession(RustDeskCodec.bytesBuffer(peer.publicKey));
    this.cryptoSessionId = material.id;
    this.clearResponseTimer();
    if (!this.tcp) throw new Error('中继通道已经关闭');
    try {
      await this.tcp.send({ data: RustDeskCodec.publicKey(material) });
    } catch (error) {
      throw new Error(`发送会话公钥失败：${String(error)}`);
    }
    listenerSafe(this.listener, ConnectionState.Authenticating,
      '真实中继与端到端加密握手已建立，下一步正在接入密码登录与视频流');
  }

  private fail(generation: number, message: string): void {
    if (generation !== this.generation) {
      return;
    }
    this.clearResponseTimer();
    listenerSafe(this.listener, ConnectionState.Failed, message);
    this.disconnectSocket();
    resetVideoDecoder();
  }

  private parseEndpoint(value: string): ServerEndpoint {
    let endpoint = value.trim();
    endpoint = endpoint.replace('tcp://', '').replace('http://', '').replace('https://', '');
    const slash = endpoint.indexOf('/');
    if (slash >= 0) {
      endpoint = endpoint.substring(0, slash);
    }
    const separator = endpoint.lastIndexOf(':');
    if (separator > 0 && endpoint.indexOf(':') === separator) {
      const port = Number(endpoint.substring(separator + 1));
      if (port > 0 && port <= 65535) {
        return new ServerEndpoint(endpoint.substring(0, separator), port);
      }
    }
    if (endpoint.length === 0) {
      throw new Error('请先配置 ID 服务器');
    }
    return new ServerEndpoint(endpoint, 21116);
  }

  private parseRelayEndpoint(value: string): ServerEndpoint {
    const parsed = this.parseEndpoint(value);
    if (value.indexOf(':') < 0) parsed.port = 21117;
    return parsed;
  }

  private uuid(): string {
    let value = '';
    for (let index = 0; index < 32; index += 1) {
      value += Math.floor(Math.random() * 16).toString(16);
    }
    return `${value.substring(0, 8)}-${value.substring(8, 12)}-4${value.substring(13, 16)}-` +
      `${(8 + Math.floor(Math.random() * 4)).toString(16)}${value.substring(17, 20)}-${value.substring(20)}`;
  }

  private newClientId(): string {
    return `${Math.floor(100000000 + Math.random() * 900000000)}`;
  }

  private loginError(error: string): string {
    if (error === 'Offline') return '远端拒绝登录：请求中的远程 ID 不匹配';
    if (error === 'Wrong Password') return '远端拒绝登录：密码错误';
    if (error === 'Connection not allowed') return '远端设备不允许该连接';
    return `远端拒绝登录：${error}`;
  }

  private disconnectSocket(): void {
    this.clearResponseTimer();
    if (this.tcp) {
      const tcp = this.tcp;
      this.tcp = undefined;
      tcp.close().catch(() => {
      });
    }
    if (this.cryptoSessionId !== 0) {
      destroySession(this.cryptoSessionId);
      this.cryptoSessionId = 0;
    }
  }

  private clearResponseTimer(): void {
    if (this.responseTimer >= 0) {
      clearTimeout(this.responseTimer);
      this.responseTimer = -1;
    }
  }
}

function listenerSafe(listener: ConnectionListener | undefined,
  state: ConnectionState, message: string): void {
  if (listener) {
    listener(state, message);
  }
}

function socketErrorText(error: Error): string {
  if (error && error.message && error.message.length > 0) return error.message;
  const value = String(error);
  return value.length > 0 && value !== 'undefined' ? value : '连接被系统中断';
}

export class RemoteCoreFactory {
  static create(): RemoteCore {
    return new RendezvousRemoteCore();
  }
}
