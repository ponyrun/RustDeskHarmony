import { http } from '@kit.NetworkKit';
import { RemoteDevice, ServerProfile } from '../model/RemoteModels';

interface LoginResponseBody {
  access_token?: string;
  token?: string;
  error?: string;
  message?: string;
}

interface PeerInfoBody {
  username?: string;
  device_name?: string;
  os?: string;
}

interface PeerBody {
  id?: string;
  alias?: string;
  hostname?: string;
  username?: string;
  platform?: string;
  status?: number;
  info?: PeerInfoBody;
}

interface DevicePageBody {
  data?: PeerBody[] | string;
  total?: number;
  error?: string;
  message?: string;
  guid?: string;
}

interface LegacyAddressBookBody {
  peers?: PeerBody[];
}

class DeviceInfo {
  os: string = 'harmonyos';
  type: string = 'mobile';
  name: string = 'RustDesk Harmony';
}

class LoginPayload {
  username: string;
  password: string;
  autoLogin: boolean = false;
  uuid: string;
  type: string = 'account';
  deviceInfo: DeviceInfo = new DeviceInfo();

  constructor(username: string, password: string, uuid: string) {
    this.username = username;
    this.password = password;
    this.uuid = uuid;
  }
}

export class ServerLoginResult {
  success: boolean;
  message: string;
  accessToken: string;

  constructor(success: boolean, message: string, accessToken: string = '') {
    this.success = success;
    this.message = message;
    this.accessToken = accessToken;
  }
}

export class ServerDeviceListResult {
  success: boolean;
  message: string;
  devices: RemoteDevice[];
  total: number;

  constructor(success: boolean, message: string, devices: RemoteDevice[] = [], total: number = 0) {
    this.success = success;
    this.message = message;
    this.devices = devices;
    this.total = total;
  }
}

export class ServerProApi {
  static async login(profile: ServerProfile, username: string, password: string,
    uuid: string): Promise<ServerLoginResult> {
    const request = http.createHttp();
    const endpoint = `${profile.normalizedApiServer()}/api/login`;
    try {
      const response = await request.request(endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: JSON.stringify(new LoginPayload(username, password, uuid)),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000,
        usingCache: false
      });
      const status = Number(response.responseCode);
      const body = JSON.parse(String(response.result)) as LoginResponseBody;
      if (status >= 200 && status < 300) {
        const token = body.access_token ? body.access_token : (body.token ? body.token : '');
        if (token.length > 0) {
          return new ServerLoginResult(true, 'Server Pro 登录成功', token);
        }
        return new ServerLoginResult(false, body.message ? body.message : '服务器未返回访问令牌');
      }
      const detail = body.error ? body.error : (body.message ? body.message : `HTTP ${status}`);
      return new ServerLoginResult(false, `登录失败：${detail}`);
    } catch (error) {
      return new ServerLoginResult(false, `无法访问 API Server：${String(error)}`);
    } finally {
      request.destroy();
    }
  }

  static async devices(profile: ServerProfile, accessToken: string): Promise<ServerDeviceListResult> {
    const devices: RemoteDevice[] = [];
    const pageSize = 100;
    let current = 1;
    let total = 0;
    do {
      const page = await ServerProApi.getPeerPage(profile,
        `/api/peers?current=${current}&pageSize=${pageSize}&accessible=&status=1`,
        accessToken, 'Server Pro 设备');
      if (!page.success) return page;
      devices.push(...page.devices);
      total = page.total;
      current += 1;
    } while ((current - 1) * pageSize < total);
    return new ServerDeviceListResult(true, `已同步 ${devices.length} 个 Server Pro 设备`, devices, total);
  }

  static async addressBook(profile: ServerProfile,
    accessToken: string): Promise<ServerDeviceListResult> {
    const legacy = await ServerProApi.getLegacyAddressBook(profile, accessToken);
    if (legacy.success || !legacy.message.includes('HTTP 404')) return legacy;
    return ServerProApi.getPersonalAddressBook(profile, accessToken);
  }

  private static async getLegacyAddressBook(profile: ServerProfile,
    accessToken: string): Promise<ServerDeviceListResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${profile.normalizedApiServer()}/api/ab`, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000,
        usingCache: false
      });
      const status = Number(response.responseCode);
      if (status === 404) return new ServerDeviceListResult(false, 'HTTP 404');
      const bodyText = String(response.result);
      if (status < 200 || status >= 300) {
        return new ServerDeviceListResult(false, ServerProApi.httpError(bodyText, status));
      }
      if (bodyText.trim().length === 0 || bodyText.trim().toLowerCase() === 'null') {
        return new ServerDeviceListResult(true, '地址簿为空');
      }
      const body = JSON.parse(bodyText) as DevicePageBody;
      if (body.error) return new ServerDeviceListResult(false, body.error);
      let peers: PeerBody[] = [];
      if (typeof body.data === 'string') {
        const decoded = JSON.parse(body.data) as LegacyAddressBookBody;
        peers = decoded.peers ? decoded.peers : [];
      }
      return new ServerDeviceListResult(true, `已同步 ${peers.length} 个地址簿设备`,
        ServerProApi.toDevices(peers));
    } catch (error) {
      return new ServerDeviceListResult(false, `地址簿同步失败：${String(error)}`);
    } finally {
      request.destroy();
    }
  }

  private static async getPersonalAddressBook(profile: ServerProfile,
    accessToken: string): Promise<ServerDeviceListResult> {
    const request = http.createHttp();
    try {
      const profileResponse = await request.request(`${profile.normalizedApiServer()}/api/ab/personal`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: '',
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000,
        usingCache: false
      });
      const profileStatus = Number(profileResponse.responseCode);
      if (profileStatus < 200 || profileStatus >= 300) {
        return new ServerDeviceListResult(false,
          ServerProApi.httpError(String(profileResponse.result), profileStatus));
      }
      const profileBody = JSON.parse(String(profileResponse.result)) as DevicePageBody;
      if (!profileBody.guid || profileBody.guid.length === 0) {
        return new ServerDeviceListResult(false, '服务器未返回个人地址簿标识');
      }
      const path = `/api/ab/peers?current=1&pageSize=100&ab=${encodeURIComponent(profileBody.guid)}`;
      return await ServerProApi.getPeerPage(profile, path, accessToken, '地址簿', http.RequestMethod.POST);
    } catch (error) {
      return new ServerDeviceListResult(false, `地址簿同步失败：${String(error)}`);
    } finally {
      request.destroy();
    }
  }

  private static async getPeerPage(profile: ServerProfile, path: string, accessToken: string,
    label: string, method: http.RequestMethod = http.RequestMethod.GET): Promise<ServerDeviceListResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${profile.normalizedApiServer()}${path}`, {
        method: method,
        header: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: method === http.RequestMethod.POST ? '' : undefined,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000,
        usingCache: false
      });
      const status = Number(response.responseCode);
      const bodyText = String(response.result);
      if (status < 200 || status >= 300) {
        return new ServerDeviceListResult(false, ServerProApi.httpError(bodyText, status));
      }
      const body = JSON.parse(bodyText) as DevicePageBody;
      if (body.error) return new ServerDeviceListResult(false, body.error);
      const peers = Array.isArray(body.data) ? body.data : [];
      return new ServerDeviceListResult(true, `已同步 ${peers.length} 个${label}`,
        ServerProApi.toDevices(peers), body.total ? body.total : peers.length);
    } catch (error) {
      return new ServerDeviceListResult(false, `${label}同步失败：${String(error)}`);
    } finally {
      request.destroy();
    }
  }

  private static httpError(bodyText: string, status: number): string {
    try {
      const body = JSON.parse(bodyText) as DevicePageBody;
      return body.error ? body.error : (body.message ? body.message : `HTTP ${status}`);
    } catch (_) {
      return `HTTP ${status}`;
    }
  }

  private static toDevices(peers: PeerBody[]): RemoteDevice[] {
    const devices: RemoteDevice[] = [];
    peers.forEach((peer: PeerBody) => {
      const id = peer.id ? peer.id : '';
      if (id.length === 0) return;
      const info = peer.info;
      const hostname = peer.alias ? peer.alias : (peer.hostname ? peer.hostname :
        (info && info.device_name ? info.device_name : '远程设备'));
      const platform = peer.platform ? peer.platform :
        (info && info.os ? info.os.split(' / ')[0] : 'RustDesk');
      devices.push(new RemoteDevice(id, hostname, platform, peer.status === 1,
        false, peer.status === 1 ? '在线' : '离线', ServerProApi.platformColor(platform)));
    });
    return devices;
  }

  private static platformColor(platform: string): string {
    const value = platform.toLowerCase();
    if (value.includes('mac')) return '#D58E7A';
    if (value.includes('win')) return '#9388D8';
    if (value.includes('linux')) return '#D49A4B';
    if (value.includes('android')) return '#68B877';
    return '#69A8E8';
  }
}
