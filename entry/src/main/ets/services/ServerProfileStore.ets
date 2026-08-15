import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ServerProfile, ServerValidation } from '../model/RemoteModels';

const STORE_NAME: string = 'rustdesk_server_pro';

export class ServerProfileStore {
  private store: preferences.Preferences;

  constructor(context: common.UIAbilityContext) {
    this.store = preferences.getPreferencesSync(context, { name: STORE_NAME });
  }

  load(): ServerProfile {
    const profile = new ServerProfile();
    try {
      profile.name = this.store.getSync('name', profile.name) as string;
      profile.idServer = this.store.getSync('id_server', '') as string;
      profile.relayServer = this.store.getSync('relay_server', '') as string;
      profile.apiServer = this.store.getSync('api_server', '') as string;
      profile.publicKey = this.store.getSync('public_key', '') as string;
      profile.useWebSocket = this.store.getSync('use_websocket', false) as boolean;
      profile.allowInsecureApi = this.store.getSync('allow_insecure_api', false) as boolean;
    } catch (_error) {
      return new ServerProfile();
    }
    return profile;
  }

  save(profile: ServerProfile): boolean {
    try {
      this.store.putSync('name', profile.name.trim());
      this.store.putSync('id_server', profile.idServer.trim());
      this.store.putSync('relay_server', profile.relayServer.trim());
      this.store.putSync('api_server', profile.normalizedApiServer());
      this.store.putSync('public_key', profile.publicKey.trim());
      this.store.putSync('use_websocket', profile.useWebSocket);
      this.store.putSync('allow_insecure_api', profile.allowInsecureApi);
      this.store.flushSync();
      return true;
    } catch (_error) {
      return false;
    }
  }

  clientUuid(): string {
    try {
      let uuid = this.store.getSync('client_uuid', '') as string;
      if (uuid.length === 0) {
        uuid = `harmony-${Date.now()}-${Math.floor(Math.random() * 1000000000)}`;
        this.store.putSync('client_uuid', uuid);
        this.store.flushSync();
      }
      return uuid;
    } catch (_error) {
      return `harmony-${Date.now()}`;
    }
  }

  clear(): void {
    try {
      this.store.clearSync();
      this.store.flushSync();
    } catch (_error) {
    }
  }

  static validate(profile: ServerProfile, requireApi: boolean): ServerValidation {
    if (profile.idServer.trim().length === 0) {
      return new ServerValidation(false, '请输入 ID Server（hbbs）地址');
    }
    if (profile.idServer.indexOf('://') >= 0) {
      return new ServerValidation(false, 'ID Server 只填写域名/IP 和可选端口，不要添加协议头');
    }
    if (profile.publicKey.trim().length < 16) {
      return new ServerValidation(false, '服务器公钥无效，请从 Server Pro 控制台复制 Key');
    }
    if (requireApi || profile.apiServer.trim().length > 0) {
      const api = profile.normalizedApiServer();
      if (!api.startsWith('https://') && !api.startsWith('http://')) {
        return new ServerValidation(false, 'API Server 必须以 https:// 或 http:// 开头');
      }
      if (api.startsWith('http://') && !profile.allowInsecureApi) {
        return new ServerValidation(false, 'HTTP 会明文传输登录凭据；请先明确开启“允许 HTTP / 不安全 TLS”');
      }
    }
    return new ServerValidation(true, '配置有效');
  }

  // A remote desktop session only uses hbbs/hbbr and the server public key.
  // The Server Pro API URL is an account/address-book concern and must not
  // prevent an otherwise valid remote-control connection from starting.
  static validateRemoteConnection(profile: ServerProfile): ServerValidation {
    if (profile.idServer.trim().length === 0) {
      return new ServerValidation(false, '请输入 ID Server（hbbs）地址');
    }
    if (profile.idServer.indexOf('://') >= 0) {
      return new ServerValidation(false, 'ID Server 只填写域名/IP 和可选端口，不要添加协议头');
    }
    if (profile.publicKey.trim().length < 16) {
      return new ServerValidation(false, '服务器公钥无效，请从 Server Pro 控制台复制 Key');
    }
    return new ServerValidation(true, '远程连接配置有效');
  }
}
