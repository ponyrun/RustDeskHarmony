export enum ConnectionState {
  Idle = 'idle',
  Connecting = 'connecting',
  Authenticating = 'authenticating',
  Connected = 'connected',
  Reconnecting = 'reconnecting',
  Failed = 'failed'
}

export enum LayoutMode {
  Compact = 'compact',
  Medium = 'medium',
  Expanded = 'expanded'
}

export class RemoteDevice {
  id: string;
  name: string;
  platform: string;
  online: boolean;
  favorite: boolean;
  lastSeen: string;
  color: string;

  constructor(id: string, name: string, platform: string, online: boolean,
    favorite: boolean, lastSeen: string, color: string) {
    this.id = id;
    this.name = name;
    this.platform = platform;
    this.online = online;
    this.favorite = favorite;
    this.lastSeen = lastSeen;
    this.color = color;
  }
}

export class ConnectRequest {
  remoteId: string;
  password: string;
  serverProfile: ServerProfile;

  constructor(remoteId: string, password: string, serverProfile: ServerProfile) {
    this.remoteId = remoteId;
    this.password = password;
    this.serverProfile = serverProfile;
  }
}

export class ServerProfile {
  name: string = 'RustDesk Server Pro';
  idServer: string = '';
  relayServer: string = '';
  apiServer: string = '';
  publicKey: string = '';
  useWebSocket: boolean = false;
  allowInsecureApi: boolean = false;

  normalizedApiServer(): string {
    let value = this.apiServer.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  configured(): boolean {
    return this.idServer.trim().length > 0 && this.publicKey.trim().length > 0;
  }
}

export class ServerValidation {
  valid: boolean;
  message: string;

  constructor(valid: boolean, message: string) {
    this.valid = valid;
    this.message = message;
  }
}

export class RemoteCapabilities {
  hardwareDecode: boolean = false;
  clipboard: boolean = true;
  fileTransfer: boolean = false;
  nativeCore: boolean = false;
}

export type ConnectionListener = (state: ConnectionState, message: string) => void;
