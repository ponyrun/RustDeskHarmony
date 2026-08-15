import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { asset } from '@kit.AssetStoreKit';
import { RemoteDevice } from '../model/RemoteModels';

const STORE_NAME: string = 'rustdesk_recent_hosts';
const IDS_KEY: string = 'host_ids';

export class RecentHostStore {
  private store: preferences.Preferences;

  constructor(context: common.UIAbilityContext) {
    this.store = preferences.getPreferencesSync(context, { name: STORE_NAME });
  }

  load(): RemoteDevice[] {
    const result: RemoteDevice[] = [];
    try {
      const ids = (this.store.getSync(IDS_KEY, '') as string).split(',')
        .filter((id: string) => id.length > 0);
      ids.forEach((id: string) => {
        result.push(new RemoteDevice(id,
          this.store.getSync(`host_${id}_name`, '远程设备') as string,
          this.store.getSync(`host_${id}_platform`, 'RustDesk') as string,
          true, this.store.getSync(`host_${id}_favorite`, true) as boolean,
          this.store.getSync(`host_${id}_last`, '最近连接') as string,
          this.store.getSync(`host_${id}_color`, '#69A8E8') as string));
      });
    } catch (_) {
      return [];
    }
    return result;
  }

  save(device: RemoteDevice, password: string): boolean {
    const id = device.id.replace(/\s/g, '');
    if (id.length === 0) return false;
    try {
      const ids = (this.store.getSync(IDS_KEY, '') as string).split(',')
        .filter((value: string) => value.length > 0 && value !== id);
      ids.unshift(id);
      this.store.putSync(IDS_KEY, ids.slice(0, 20).join(','));
      this.store.putSync(`host_${id}_name`, device.name);
      this.store.putSync(`host_${id}_platform`, device.platform);
      this.store.putSync(`host_${id}_last`, '刚刚');
      this.store.putSync(`host_${id}_color`, device.color);
      if (!this.store.hasSync(`host_${id}_favorite`)) {
        this.store.putSync(`host_${id}_favorite`, device.favorite);
      }
      this.store.flushSync();
      this.savePassword(id, password);
      return true;
    } catch (_) {
      return false;
    }
  }

  password(remoteId: string): string {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, this.utf8(this.alias(remoteId)));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const records = asset.querySync(query);
      if (records.length === 0) return '';
      const secret = records[0].get(asset.Tag.SECRET) as Uint8Array;
      return this.decodeUtf8(secret);
    } catch (_) {
      return '';
    }
  }

  clearPassword(remoteId: string): void {
    this.savePassword(remoteId.replace(/\s/g, ''), '');
  }

  remove(remoteId: string): boolean {
    const id = remoteId.replace(/\s/g, '');
    try {
      const ids = (this.store.getSync(IDS_KEY, '') as string).split(',')
        .filter((value: string) => value.length > 0 && value !== id);
      this.store.putSync(IDS_KEY, ids.join(','));
      this.store.deleteSync(`host_${id}_name`);
      this.store.deleteSync(`host_${id}_platform`);
      this.store.deleteSync(`host_${id}_last`);
      this.store.deleteSync(`host_${id}_color`);
      this.store.deleteSync(`host_${id}_favorite`);
      this.store.flushSync();
      this.clearPassword(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  setFavorite(remoteId: string, favorite: boolean): boolean {
    const id = remoteId.replace(/\s/g, '');
    try {
      this.store.putSync(`host_${id}_favorite`, favorite);
      this.store.flushSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  clearAll(): void {
    const devices = this.load();
    devices.forEach((device: RemoteDevice) => this.clearPassword(device.id));
    try {
      this.store.clearSync();
      this.store.flushSync();
    } catch (_) {
    }
  }

  private savePassword(remoteId: string, password: string): void {
    const alias = this.utf8(this.alias(remoteId));
    try {
      const old: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      old.set(asset.Tag.ALIAS, alias);
      asset.removeSync(old);
    } catch (_) {
    }
    if (password.length === 0) return;
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, alias);
    attributes.set(asset.Tag.SECRET, this.utf8(password));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attributes.set(asset.Tag.AUTH_TYPE, asset.AuthType.NONE);
    try {
      asset.addSync(attributes);
    } catch (_) {
    }
  }

  private alias(remoteId: string): string {
    return `rustdesk-host-${remoteId.replace(/\s/g, '')}`;
  }

  private utf8(value: string): Uint8Array {
    const encoded = encodeURIComponent(value);
    const bytes: number[] = [];
    for (let index = 0; index < encoded.length; index += 1) {
      if (encoded.charAt(index) === '%' && index + 2 < encoded.length) {
        bytes.push(parseInt(encoded.substring(index + 1, index + 3), 16));
        index += 2;
      } else {
        bytes.push(encoded.charCodeAt(index));
      }
    }
    return new Uint8Array(bytes);
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
