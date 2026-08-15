import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'rustdesk_privacy_consent';
const CURRENT_VERSION: string = '2026-07-22';

export class PrivacyConsentStore {
  private store: preferences.Preferences;

  constructor(context: common.UIAbilityContext) {
    this.store = preferences.getPreferencesSync(context, { name: STORE_NAME });
  }

  accepted(): boolean {
    try {
      return (this.store.getSync('accepted_version', '') as string) === CURRENT_VERSION;
    } catch (_) {
      return false;
    }
  }

  accept(): void {
    try {
      this.store.putSync('accepted_version', CURRENT_VERSION);
      this.store.putSync('accepted_at', new Date().toISOString());
      this.store.flushSync();
    } catch (_) {
    }
  }
}
