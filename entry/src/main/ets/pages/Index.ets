import {
  ConnectRequest,
  ConnectionState,
  LayoutMode,
  RemoteDevice,
  ServerProfile,
  ServerValidation
} from '../model/RemoteModels';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { RemoteCore, RemoteCoreFactory, RemoteCursorImage } from '../services/RemoteCore';
import { ServerProfileStore } from '../services/ServerProfileStore';
import { RecentHostStore } from '../services/RecentHostStore';
import { ServerDeviceListResult, ServerLoginResult, ServerProApi } from '../services/ServerProApi';
import { LanDiscoveryService } from '../services/LanDiscoveryService';
import { PrivacyConsentStore } from '../services/PrivacyConsentStore';

const BLUE: string = '#2196F3';
const CYAN: string = '#08B6E8';
const BACKGROUND: string = '#F4F5FA';
const SURFACE: string = '#FFFFFF';
const INPUT: string = '#F0F1F5';
const TEXT: string = '#17181A';
const MUTED: string = '#929397';
const DIVIDER: string = '#EBECF0';
const GREEN: string = '#27C75A';
const DANGER: string = '#DC4C58';

class RemoteCursorVisual {
  id: string;
  pixelMap: image.PixelMap;
  hotX: number;
  hotY: number;
  width: number;
  height: number;

  constructor(id: string, pixelMap: image.PixelMap, hotX: number, hotY: number,
    width: number, height: number) {
    this.id = id;
    this.pixelMap = pixelMap;
    this.hotX = hotX;
    this.hotY = hotY;
    this.width = width;
    this.height = height;
  }
}

@Entry
@Component
struct Index {
  @State private viewportWidth: number = 390;
  @State private currentPage: string = 'connect';
  @State private selectedMode: string = 'favorite';
  @State private selectedDeviceId: string = '';
  @State private remoteId: string = '';
  @State private password: string = '';
  @State private rememberConnectionPassword: boolean = true;
  @State private showServerDialog: boolean = false;
  @State private showLoginDialog: boolean = false;
  @State private showDeviceMenu: boolean = false;
  @State private showConnectionDialog: boolean = false;
  @State private showPrivacyDialog: boolean = false;
  @State private privacyAccepted: boolean = false;
  @State private privacyActionStatus: string = '';
  @State private deviceSearchVisible: boolean = false;
  @State private deviceSearchText: string = '';
  @State private deviceSelectionMode: boolean = false;
  @State private selectedDeviceIds: string[] = [];
  @State private deviceSortMode: string = 'recent';
  @State private deviceListStatus: string = '';
  @State private deviceListLoading: boolean = false;
  @State private pendingRemoteId: string = '';
  @State private pendingDeviceName: string = '';
  @State private sessionDeviceName: string = '远程设备';
  @State private connectionDialogStatus: string = '';
  @State private profileName: string = 'RustDesk Server Pro';
  @State private idServer: string = '';
  @State private relayServer: string = '';
  @State private apiServer: string = '';
  @State private serverPublicKey: string = '';
  @State private useWebSocket: boolean = false;
  @State private allowUnsafeTls: boolean = false;
  @State private udpPunch: boolean = false;
  @State private ipv6P2p: boolean = false;
  @State private askRemark: boolean = false;
  @State private keepScreenOn: boolean = true;
  @State private serverUsername: string = '';
  @State private serverPassword: string = '';
  @State private serverStatus: string = '尚未配置 Server Pro';
  @State private serverLoginOk: boolean = false;
  @State private accessToken: string = '';
  @State private connectionState: ConnectionState = ConnectionState.Idle;
  @State private statusMessage: string = '准备连接';
  @State private showKeyboard: boolean = false;
  @State private clipboardComposeMode: boolean = false;
  @State private showControlPanel: boolean = false;
  @State private sessionPanel: string = 'none';
  @State private sessionKeysExpanded: boolean = false;
  @State private sessionInputMode: string = 'touch';
  @State private sessionScaleMode: string = 'fit';
  @State private sessionQuality: string = 'balanced';
  @State private sessionCodec: string = 'auto';
  @State private sessionCursorSize: number = 1;
  @State private canvasZoom: number = 1;
  @State private canvasOffsetX: number = 0;
  @State private canvasOffsetY: number = 0;
  @State private sessionCtrl: boolean = false;
  @State private sessionAlt: boolean = false;
  @State private sessionShift: boolean = false;
  @State private sessionMeta: boolean = false;
  @State private chatText: string = '';
  @State private chatMessages: Array<string> = [];
  @State private showVirtualMouse: boolean = false;
  @State private virtualMouseX: number = 0;
  @State private virtualMouseY: number = 0;
  @State private virtualLeftHeld: boolean = false;
  @State private virtualRightHeld: boolean = false;
  @State private videoSurfaceGeneration: number = 0;
  @State private sessionAreaWidth: number = 1;
  @State private sessionAreaHeight: number = 1;
  @State private remoteAspectRatio: number = 16 / 9;
  @State private remoteCursorX: number = 0;
  @State private remoteCursorY: number = 0;
  @State private remoteCursorVisible: boolean = false;
  @State private remoteCursorPixelMap: image.PixelMap | undefined = undefined;
  @State private remoteCursorHotX: number = 0;
  @State private remoteCursorHotY: number = 0;
  @State private remoteCursorWidth: number = 18;
  @State private remoteCursorHeight: number = 18;
  @State private qualityFps: number = 0;
  @State private qualityFrames: number = 0;
  @State private qualityVideoWidth: number = 0;
  @State private qualityVideoHeight: number = 0;
  @State private qualityDecoder: string = '等待视频';
  @State private keyboardText: string = '';
  @State private browseMode: boolean = false;
  @State private showRemoteCursor: boolean = false;
  @State private followRemoteCursor: boolean = false;
  @State private followWindowFocus: boolean = false;
  @State private showQualityMonitor: boolean = false;
  @State private mute: boolean = false;
  @State private disableClipboard: boolean = false;
  @State private lockAfterSession: boolean = false;
  @State private privacyMode: boolean = false;
  @State private trueColor: boolean = false;
  @State private reverseWheel: boolean = false;
  @State private swapMouseButtons: boolean = false;
  @State private keepTerminal: boolean = false;

  private core: RemoteCore = RemoteCoreFactory.create();
  private videoSurfaceController: XComponentController = new XComponentController();
  private lastVideoSurfaceId: string = '';
  private videoStatusTimer: number = -1;
  private qualityLastFrames: number = 0;
  private videoRecoveryTimer: number = -1;
  private reconnectTimer: number = -1;
  private reconnectAttempts: number = 0;
  private activeConnectionPassword: string = '';
  private activeRememberPassword: boolean = true;
  private readonly remoteKeyboardGuard: string = '\u200B';
  private directKeyboardForwardedText: string = '';
  private needsReconnect: boolean = false;
  private pageVisible: boolean = true;
  private manualDisconnect: boolean = false;
  private sessionWasConnected: boolean = false;
  private touchDragging: boolean = false;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private mouseModeLastX: number = 0;
  private mouseModeLastY: number = 0;
  private mouseModeMoved: boolean = false;
  private lastPointerX: number = 0;
  private lastPointerY: number = 0;
  private twoFingerScroll: boolean = false;
  private twoFingerMoved: boolean = false;
  private suppressSingleTouch: boolean = false;
  private twoFingerStartX: number = 0;
  private twoFingerStartY: number = 0;
  private twoFingerCenterX: number = 0;
  private twoFingerCenterY: number = 0;
  private lastScrollY: number = 0;
  private pinchStartDistance: number = 0;
  private pinchStartZoom: number = 1;
  private pinchActive: boolean = false;
  private twoFingerLastViewX: number = 0;
  private twoFingerLastViewY: number = 0;
  private remoteCursorId: string = '';
  private remoteCursorCache: Array<RemoteCursorVisual> = [];
  private lastLocalCursorUpdate: number = 0;
  private virtualMousePositioned: boolean = false;
  private virtualMouseGestureActive: boolean = false;
  private virtualMouseGestureMoved: boolean = false;
  private virtualMouseStartX: number = 0;
  private virtualMouseStartY: number = 0;
  private virtualMouseLastX: number = 0;
  private virtualMouseLastY: number = 0;
  private virtualMouseZone: string = 'move';
  private virtualMouseHoldTimer: number = -1;
  @State private devices: RemoteDevice[] = [];
  @State private lanDevices: RemoteDevice[] = [];
  @State private addressBookDevices: RemoteDevice[] = [];
  @State private serverDevices: RemoteDevice[] = [];
  private lanDiscovery: LanDiscoveryService = new LanDiscoveryService();

  private receiveRemoteCursorImage(cursor: RemoteCursorImage): void {
    try {
      const rgba = new Uint8Array(cursor.colors);
      let hasVisiblePixel = false;
      for (let index = 3; index < rgba.length; index += 4) {
        if (rgba[index] !== 0) {
          hasVisiblePixel = true;
          break;
        }
      }
      if (!hasVisiblePixel) return;
      const pixelMap = image.createPixelMapSync(cursor.colors, {
        size: { width: cursor.width, height: cursor.height },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false
      });
      for (let index = this.remoteCursorCache.length - 1; index >= 0; index -= 1) {
        if (this.remoteCursorCache[index].id === cursor.id) {
          this.remoteCursorCache[index].pixelMap.release();
          this.remoteCursorCache.splice(index, 1);
        }
      }
      const visual = new RemoteCursorVisual(cursor.id, pixelMap, cursor.hotX, cursor.hotY,
        cursor.width, cursor.height);
      this.remoteCursorCache.push(visual);
      while (this.remoteCursorCache.length > 32) {
        const expired = this.remoteCursorCache.shift();
        if (expired !== undefined) expired.pixelMap.release();
      }
      if (this.remoteCursorId.length === 0 || this.remoteCursorId === cursor.id) {
        this.applyRemoteCursorVisual(visual);
      }
    } catch (_) {
      // Keep the last valid cursor instead of making it disappear on a malformed cursor packet.
    }
  }

  private selectRemoteCursor(id: string): void {
    this.remoteCursorId = id;
    for (let index = 0; index < this.remoteCursorCache.length; index += 1) {
      if (this.remoteCursorCache[index].id === id) {
        this.applyRemoteCursorVisual(this.remoteCursorCache[index]);
        return;
      }
    }
  }

  private applyRemoteCursorVisual(visual: RemoteCursorVisual): void {
    this.remoteCursorPixelMap = visual.pixelMap;
    this.remoteCursorHotX = visual.hotX;
    this.remoteCursorHotY = visual.hotY;
    this.remoteCursorWidth = visual.width;
    this.remoteCursorHeight = visual.height;
    this.remoteCursorVisible = true;
  }

  private sendMouseClick(button: number, count: number = 1): void {
    const downMask = (button << 3) | 1;
    const upMask = (button << 3) | 2;
    for (let index = 0; index < count; index += 1) {
      this.core.sendPointer(this.lastPointerX, this.lastPointerY, downMask);
      this.core.sendPointer(this.lastPointerX, this.lastPointerY, upMask);
    }
  }

  private setVirtualMouseButton(button: number, pressed: boolean): void {
    if (button === 1) this.virtualLeftHeld = pressed;
    if (button === 2) this.virtualRightHeld = pressed;
    const mask = (button << 3) | (pressed ? 1 : 2);
    this.core.sendPointer(this.lastPointerX, this.lastPointerY, mask);
  }

  private moveVirtualPointer(deltaX: number, deltaY: number): void {
    this.lastPointerX = Math.max(0, Math.min(this.videoRenderWidth() - 1,
      this.lastPointerX + deltaX));
    this.lastPointerY = Math.max(0, Math.min(this.videoRenderHeight() - 1,
      this.lastPointerY + deltaY));
    this.updateLocalRemoteCursor(this.lastPointerX, this.lastPointerY);
    const heldMask = this.virtualLeftHeld ? 8 : (this.virtualRightHeld ? 16 : 0);
    this.core.sendPointer(this.lastPointerX, this.lastPointerY, heldMask);
  }

  private scrollVirtualMouse(direction: number): void {
    const adjusted = this.reverseWheel ? -direction : direction;
    this.core.sendPointer(0, adjusted * 120, 4);
  }

  private clearVirtualMouseHoldTimer(): void {
    if (this.virtualMouseHoldTimer >= 0) {
      clearTimeout(this.virtualMouseHoldTimer);
      this.virtualMouseHoldTimer = -1;
    }
  }

  private virtualMouseTouchZone(x: number, y: number): string {
    if (y < 44 && x > 154) return 'close';
    if (y >= 44 && y < 126) {
      if (x < 75) return 'left';
      if (x > 121) return 'right';
      if (y < 71) return 'wheel_up';
      if (y < 99) return 'middle';
      return 'wheel_down';
    }
    return 'move';
  }

  private startVirtualMouseHold(zone: string): void {
    this.clearVirtualMouseHoldTimer();
    if (zone !== 'left' && zone !== 'right') return;
    this.virtualMouseHoldTimer = setTimeout(() => {
      this.virtualMouseHoldTimer = -1;
      if (!this.virtualMouseGestureActive || this.virtualMouseGestureMoved || this.virtualMouseZone !== zone) return;
      this.setVirtualMouseButton(zone === 'left' ? 1 : 2, true);
    }, 420);
  }

  private moveVirtualMouseAndPointer(deltaX: number, deltaY: number): void {
    this.moveVirtualPointer(deltaX, deltaY);
    this.positionVirtualMouseNearCursor();
  }

  private activateVirtualMouseZone(zone: string): void {
    if (zone === 'close') {
      this.closeVirtualMouse();
    } else if (zone === 'left') {
      this.sendMouseClick(1);
    } else if (zone === 'right') {
      this.sendMouseClick(2);
    } else if (zone === 'middle') {
      this.sendMouseClick(4);
    } else if (zone === 'wheel_up') {
      this.scrollVirtualMouse(-1);
    } else if (zone === 'wheel_down') {
      this.scrollVirtualMouse(1);
    }
  }

  private virtualMouseTouch(event: TouchEvent): void {
    const points = event.changedTouches.length > 0 ? event.changedTouches : event.touches;
    if (points.length === 0) return;
    const point = points[0];
    if (event.type === TouchType.Down) {
      this.virtualMouseGestureActive = true;
      this.virtualMouseGestureMoved = false;
      this.virtualMouseStartX = point.windowX;
      this.virtualMouseStartY = point.windowY;
      this.virtualMouseLastX = point.windowX;
      this.virtualMouseLastY = point.windowY;
      this.virtualMouseZone = this.virtualMouseTouchZone(point.x, point.y);
      this.startVirtualMouseHold(this.virtualMouseZone);
    } else if (event.type === TouchType.Move && this.virtualMouseGestureActive) {
      const totalX = point.windowX - this.virtualMouseStartX;
      const totalY = point.windowY - this.virtualMouseStartY;
      if (!this.virtualMouseGestureMoved && totalX * totalX + totalY * totalY >= 16) {
        this.virtualMouseGestureMoved = true;
        this.clearVirtualMouseHoldTimer();
      }
      const deltaX = point.windowX - this.virtualMouseLastX;
      const deltaY = point.windowY - this.virtualMouseLastY;
      this.virtualMouseLastX = point.windowX;
      this.virtualMouseLastY = point.windowY;
      if (this.virtualMouseGestureMoved && Math.abs(deltaX) + Math.abs(deltaY) > 0) {
        this.moveVirtualMouseAndPointer(deltaX, deltaY);
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.clearVirtualMouseHoldTimer();
      if (this.virtualLeftHeld) {
        this.setVirtualMouseButton(1, false);
      } else if (this.virtualRightHeld) {
        this.setVirtualMouseButton(2, false);
      } else if (event.type === TouchType.Up && !this.virtualMouseGestureMoved) {
        this.activateVirtualMouseZone(this.virtualMouseZone);
      }
      this.virtualMouseGestureActive = false;
      this.virtualMouseGestureMoved = false;
    }
    event.stopPropagation();
  }

  private openVirtualMouse(): void {
    this.positionVirtualMouseNearCursor();
    this.virtualMousePositioned = true;
    this.showVirtualMouse = true;
    this.showRemoteCursor = true;
    this.showControlPanel = false;
    this.showKeyboard = false;
    this.clipboardComposeMode = false;
  }

  private positionVirtualMouseNearCursor(): void {
    this.ensureVirtualMouseVisible();
    this.virtualMouseX = this.virtualMouseAnchorX();
    this.virtualMouseY = this.virtualMouseAnchorY();
  }

  private ensureVirtualMouseVisible(): void {
    const minimumCursorX = Math.max(4, this.remoteCursorHotX * this.sessionCursorSize + 4);
    const minimumCursorY = Math.max(4, this.remoteCursorHotY * this.sessionCursorSize + 4);
    const maximumCursorX = Math.max(minimumCursorX, this.sessionAreaWidth - 196 - 34 - 4);
    const maximumCursorY = Math.max(minimumCursorY, this.sessionAreaHeight - 232 - 24 - 4);
    const cursorScreenX = this.videoOffsetX() + this.remoteCursorX * this.videoRenderWidth();
    const cursorScreenY = this.videoOffsetY() + this.remoteCursorY * this.videoRenderHeight();
    if (cursorScreenX < minimumCursorX) this.canvasOffsetX += minimumCursorX - cursorScreenX;
    if (cursorScreenX > maximumCursorX) this.canvasOffsetX -= cursorScreenX - maximumCursorX;
    if (cursorScreenY < minimumCursorY) this.canvasOffsetY += minimumCursorY - cursorScreenY;
    if (cursorScreenY > maximumCursorY) this.canvasOffsetY -= cursorScreenY - maximumCursorY;
  }

  private virtualMouseAnchorX(): number {
    return this.videoOffsetX() + this.remoteCursorX * this.videoRenderWidth() + 34;
  }

  private virtualMouseAnchorY(): number {
    return this.videoOffsetY() + this.remoteCursorY * this.videoRenderHeight() + 24;
  }

  private closeVirtualMouse(): void {
    this.clearVirtualMouseHoldTimer();
    if (this.virtualLeftHeld) this.setVirtualMouseButton(1, false);
    if (this.virtualRightHeld) this.setVirtualMouseButton(2, false);
    this.virtualMouseGestureActive = false;
    this.virtualMouseGestureMoved = false;
    this.showVirtualMouse = false;
    this.clampCanvasOffset();
  }

  private videoRenderWidth(): number {
    const availableAspect = this.sessionAreaWidth / this.sessionAreaHeight;
    const fitted = availableAspect > this.remoteAspectRatio ?
      this.sessionAreaHeight * this.remoteAspectRatio : this.sessionAreaWidth;
    if (this.sessionScaleMode === 'original' && this.qualityVideoWidth > 0) {
      return this.qualityVideoWidth;
    }
    if (this.sessionScaleMode === 'custom') return fitted * this.canvasZoom;
    return fitted;
  }

  private videoRenderHeight(): number {
    const availableAspect = this.sessionAreaWidth / this.sessionAreaHeight;
    const fitted = availableAspect > this.remoteAspectRatio ?
      this.sessionAreaHeight : this.sessionAreaWidth / this.remoteAspectRatio;
    if (this.sessionScaleMode === 'original' && this.qualityVideoHeight > 0) {
      return this.qualityVideoHeight;
    }
    if (this.sessionScaleMode === 'custom') return fitted * this.canvasZoom;
    return fitted;
  }

  private videoOffsetX(): number {
    return (this.sessionAreaWidth - this.videoRenderWidth()) / 2 + this.canvasOffsetX;
  }

  private videoOffsetY(): number {
    return (this.sessionAreaHeight - this.videoRenderHeight()) / 2 + this.canvasOffsetY;
  }

  private clampCanvasOffset(): void {
    const maxOffsetX = Math.max(0, (this.videoRenderWidth() - this.sessionAreaWidth) / 2);
    const maxOffsetY = Math.max(0, (this.videoRenderHeight() - this.sessionAreaHeight) / 2);
    this.canvasOffsetX = Math.max(-maxOffsetX, Math.min(maxOffsetX, this.canvasOffsetX));
    this.canvasOffsetY = Math.max(-maxOffsetY, Math.min(maxOffsetY, this.canvasOffsetY));
    if (this.showVirtualMouse) this.ensureVirtualMouseVisible();
  }

  private panCanvas(deltaX: number, deltaY: number): void {
    this.canvasOffsetX += deltaX;
    this.canvasOffsetY += deltaY;
    this.clampCanvasOffset();
  }

  private videoPointerX(x: number): number {
    return Math.max(0, Math.min(this.videoRenderWidth() - 1, x - this.videoOffsetX()));
  }

  private videoPointerY(y: number): number {
    return Math.max(0, Math.min(this.videoRenderHeight() - 1, y - this.videoOffsetY()));
  }

  private updateLocalRemoteCursor(x: number, y: number): void {
    const width = this.videoRenderWidth();
    const height = this.videoRenderHeight();
    if (width <= 0 || height <= 0) return;
    this.remoteCursorX = Math.max(0, Math.min(1, x / width));
    this.remoteCursorY = Math.max(0, Math.min(1, y / height));
    this.remoteCursorVisible = true;
    this.lastLocalCursorUpdate = Date.now();
    if (this.showVirtualMouse && !this.virtualMouseGestureActive) {
      this.positionVirtualMouseNearCursor();
    }
  }

  private updateVideoViewport(): void {
    this.core.setVideoViewport(this.videoRenderWidth(), this.videoRenderHeight());
  }

  private sessionModifiers(): Array<number> {
    const modifiers: Array<number> = [];
    if (this.sessionAlt) modifiers.push(1);
    if (this.sessionCtrl) modifiers.push(4);
    if (this.sessionMeta) modifiers.push(23);
    if (this.sessionShift) modifiers.push(29);
    return modifiers;
  }

  private clearSessionModifiers(): void {
    this.sessionCtrl = false;
    this.sessionAlt = false;
    this.sessionShift = false;
    this.sessionMeta = false;
  }

  private handleSessionKey(label: string, code: number): void {
    if (label === 'Ctrl') {
      this.sessionCtrl = !this.sessionCtrl;
      return;
    }
    if (label === 'Alt') {
      this.sessionAlt = !this.sessionAlt;
      return;
    }
    if (label === 'Shift') {
      this.sessionShift = !this.sessionShift;
      return;
    }
    if (label === 'Cmd') {
      this.sessionMeta = !this.sessionMeta;
      return;
    }
    if (label === 'Fn') {
      this.statusMessage = 'Fn 组合键已就绪，请选择功能键';
      return;
    }
    if (label === '固定') {
      this.statusMessage = '快捷键栏已固定';
      return;
    }
    this.core.sendShortcut(code, this.sessionModifiers());
    this.clearSessionModifiers();
  }

  private sendNamedShortcut(text: string, modifier: number): void {
    this.core.sendTextShortcut(text, [modifier]);
    this.clearSessionModifiers();
  }

  private toggleSessionPanel(panel: string): void {
    this.sessionPanel = this.sessionPanel === panel ? 'none' : panel;
    this.showControlPanel = false;
    this.clipboardComposeMode = false;
    if (panel !== 'keyboard') {
      this.showKeyboard = false;
      this.sessionKeysExpanded = false;
    }
  }

  private sendChatMessage(): void {
    const value = this.chatText.trim();
    if (value.length === 0) return;
    this.core.sendChatText(value);
    this.chatMessages.push(`我：${value}`);
    this.chatMessages = this.chatMessages.slice();
    this.chatText = '';
  }

  private resetSessionCanvas(): void {
    this.remoteAspectRatio = this.core.videoAspectRatio() > 0 ? this.core.videoAspectRatio() : 16 / 9;
    this.sessionScaleMode = 'fit';
    this.canvasZoom = 1;
    this.canvasOffsetX = 0;
    this.canvasOffsetY = 0;
    this.updateVideoViewport();
    this.core.refreshVideo();
    this.statusMessage = '画布已重置并请求远端刷新';
    this.sessionPanel = 'none';
  }

  private setSessionInputMode(mode: string): void {
    this.sessionInputMode = mode;
    if (mode === 'mouse') {
      this.showRemoteCursor = true;
      if (!this.showVirtualMouse) this.openVirtualMouse();
      this.sessionPanel = 'input';
    } else {
      if (this.showVirtualMouse) this.closeVirtualMouse();
      this.showRemoteCursor = false;
      this.remoteCursorVisible = false;
      this.sessionPanel = 'input';
    }
  }

  private openClipboardComposer(): void {
    if (this.connectionState !== ConnectionState.Connected) return;
    this.keyboardText = '';
    this.clipboardComposeMode = true;
    this.showKeyboard = true;
    this.sessionKeysExpanded = true;
    this.showControlPanel = false;
    this.statusMessage = '请在输入框中粘贴文本，再发送到远端剪贴板';
    setTimeout(() => focusControl.requestFocus('sessionClipboardInput'), 80);
  }

  private openDirectRemoteKeyboard(): void {
    if (this.connectionState !== ConnectionState.Connected) return;
    this.sessionPanel = 'none';
    this.clipboardComposeMode = false;
    this.keyboardText = this.remoteKeyboardGuard;
    this.directKeyboardForwardedText = '';
    this.showKeyboard = true;
    this.sessionKeysExpanded = true;
    this.showControlPanel = false;
    this.statusMessage = '手机输入法已直连远端；输入、删除和回车会立即生效';
    setTimeout(() => focusControl.requestFocus('sessionKeyboardInput'), 80);
  }

  private toggleDirectRemoteKeyboard(): void {
    if (this.showKeyboard && !this.clipboardComposeMode) {
      this.showKeyboard = false;
      this.sessionKeysExpanded = false;
      this.keyboardText = '';
      this.directKeyboardForwardedText = '';
      return;
    }
    this.openDirectRemoteKeyboard();
  }

  private submitKeyboardText(sendReturn: boolean): void {
    if (this.clipboardComposeMode) {
      if (this.keyboardText.length === 0) return;
      this.core.sendClipboardText(this.keyboardText);
      this.statusMessage = `已向远端发送剪贴板文本（${this.keyboardText.length} 字符）`;
    } else {
      if (sendReturn) this.core.sendKey(27, true);
    }
    this.keyboardText = '';
  }

  private handleDirectKeyboardChange(value: string): void {
    this.keyboardText = value;
    if (this.clipboardComposeMode) return;
    const current = value.split(this.remoteKeyboardGuard).join('');
    const previous = this.directKeyboardForwardedText;
    if (current === previous) return;

    let commonLength = 0;
    const comparableLength = Math.min(current.length, previous.length);
    while (commonLength < comparableLength && current.charCodeAt(commonLength) ===
      previous.charCodeAt(commonLength)) {
      commonLength += 1;
    }

    // Deletion itself is forwarded by onDidDelete. For replacement/composition,
    // first remove the replaced suffix and then send the newly committed text.
    if (!previous.startsWith(current) && commonLength < previous.length) {
      const removed = previous.substring(commonLength);
      const deleteCount = this.textCodePointCount(removed);
      for (let index = 0; index < deleteCount; index += 1) this.core.sendKey(2, true);
    }
    if (commonLength < current.length) {
      this.core.sendText(current.substring(commonLength));
    }
    this.directKeyboardForwardedText = current;

    if (current.length > 128) {
      setTimeout(() => {
        this.directKeyboardForwardedText = '';
        this.keyboardText = this.remoteKeyboardGuard;
      }, 0);
    }
  }

  private textCodePointCount(value: string): number {
    let count = 0;
    let index = 0;
    while (index < value.length) {
      const first = value.charCodeAt(index);
      if (first >= 0xD800 && first <= 0xDBFF && index + 1 < value.length) {
        const second = value.charCodeAt(index + 1);
        index += second >= 0xDC00 && second <= 0xDFFF ? 2 : 1;
      } else {
        index += 1;
      }
      count += 1;
    }
    return count;
  }

  private handleDirectKeyboardDelete(info: DeleteValue): void {
    if (this.clipboardComposeMode) return;
    const deleted = info.deleteValue.split(this.remoteKeyboardGuard).join('');
    const count = Math.max(1, this.textCodePointCount(deleted));
    for (let index = 0; index < count; index += 1) this.core.sendKey(2, true);
    const remaining = this.keyboardText.split(this.remoteKeyboardGuard).join('');
    this.directKeyboardForwardedText = remaining;
    setTimeout(() => {
      this.keyboardText = this.remoteKeyboardGuard;
      focusControl.requestFocus('sessionKeyboardInput');
    }, 0);
  }

  private handleDirectKeyboardSubmit(): void {
    if (this.clipboardComposeMode) return;
    this.core.sendKey(27, true);
    this.keyboardText = this.remoteKeyboardGuard;
    this.directKeyboardForwardedText = '';
    setTimeout(() => focusControl.requestFocus('sessionKeyboardInput'), 0);
  }

  private async receiveRemoteClipboard(text: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.statusMessage = `已接收远端剪贴板文本（${text.length} 字符）`;
    } catch (_) {
      this.statusMessage = '远端剪贴板文本写入本机失败';
    }
  }

  aboutToAppear(): void {
    this.core.setClipboardListener((text: string) => this.receiveRemoteClipboard(text));
    this.core.setChatListener((text: string) => {
      this.chatMessages.push(`远端：${text}`);
      this.chatMessages = this.chatMessages.slice();
    });
    this.core.setCursorListener((x: number, y: number) => {
      if (Date.now() - this.lastLocalCursorUpdate < 150) return;
      this.remoteCursorX = Math.max(0, Math.min(1, x));
      this.remoteCursorY = Math.max(0, Math.min(1, y));
      this.lastPointerX = this.remoteCursorX * this.videoRenderWidth();
      this.lastPointerY = this.remoteCursorY * this.videoRenderHeight();
      this.remoteCursorVisible = true;
      if (this.showVirtualMouse && !this.virtualMouseGestureActive) {
        this.positionVirtualMouseNearCursor();
      }
    });
    this.core.setCursorImageListener((cursor: RemoteCursorImage) => this.receiveRemoteCursorImage(cursor));
    this.core.setCursorIdListener((id: string) => this.selectRemoteCursor(id));
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const privacyStore = new PrivacyConsentStore(context);
    this.privacyAccepted = privacyStore.accepted();
    this.showPrivacyDialog = !this.privacyAccepted;
    this.devices = new RecentHostStore(context).load();
    const profile = new ServerProfileStore(context).load();
    this.applyProfile(profile);
    if (profile.configured()) {
      this.serverStatus = `已配置：${profile.idServer}`;
    }
  }

  aboutToDisappear(): void {
    this.manualDisconnect = true;
    this.lanDiscovery.close();
    this.stopReconnectTimer();
    this.core.setClipboardListener(undefined);
    this.core.setChatListener(undefined);
    this.core.setCursorListener(undefined);
    this.core.setCursorImageListener(undefined);
    this.core.setCursorIdListener(undefined);
    this.stopVideoStatusMonitor();
    this.stopVideoRecovery();
    this.core.disconnect();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.stopReconnectTimer();
    this.stopVideoRecovery();
    if (this.currentPage === 'session') this.core.setVideoSurface('');
  }

  onPageShow(): void {
    this.pageVisible = true;
    if (this.currentPage !== 'session') return;
    this.videoSurfaceGeneration += 1;
    if (this.needsReconnect) {
      this.scheduleReconnect(100);
    } else {
      this.startVideoRecovery(0);
    }
  }

  private startVideoRecovery(attempt: number): void {
    this.stopVideoRecovery();
    this.videoRecoveryTimer = setTimeout(() => {
      this.videoRecoveryTimer = -1;
      if (this.currentPage !== 'session' || this.connectionState === ConnectionState.Idle ||
        this.connectionState === ConnectionState.Failed) return;
      if (attempt > 0 && this.core.videoRenderedFrames() > 0) {
        this.statusMessage = `画面已恢复：${this.core.videoStatus()}`;
        return;
      }
      try {
        const currentSurfaceId = this.videoSurfaceController.getXComponentSurfaceId();
        const surfaceId = currentSurfaceId.length > 0 ? currentSurfaceId : this.lastVideoSurfaceId;
        if (surfaceId.length > 0) {
          this.lastVideoSurfaceId = surfaceId;
          if (attempt === 0 || attempt === 6) this.core.setVideoSurface(surfaceId);
          this.core.refreshVideo();
          this.statusMessage = `正在恢复远程画面（${attempt + 1}/12）`;
        }
      } catch (_) {
      }
      if (attempt < 11) {
        this.startVideoRecovery(attempt + 1);
      } else {
        this.statusMessage = '画面恢复超时，控制连接仍在线；请再次切换前后台重试';
      }
    }, attempt === 0 ? 150 : 750);
  }

  private stopVideoRecovery(): void {
    if (this.videoRecoveryTimer >= 0) {
      clearTimeout(this.videoRecoveryTimer);
      this.videoRecoveryTimer = -1;
    }
  }

  private applyProfile(profile: ServerProfile): void {
    this.profileName = profile.name;
    this.idServer = profile.idServer;
    this.relayServer = profile.relayServer;
    this.apiServer = profile.apiServer;
    this.serverPublicKey = profile.publicKey;
    this.useWebSocket = profile.useWebSocket;
    this.allowUnsafeTls = profile.allowInsecureApi;
  }

  private activeProfile(): ServerProfile {
    const profile = new ServerProfile();
    profile.name = this.profileName;
    profile.idServer = this.idServer;
    profile.relayServer = this.relayServer;
    profile.apiServer = this.apiServer;
    profile.publicKey = this.serverPublicKey;
    profile.useWebSocket = this.useWebSocket;
    profile.allowInsecureApi = this.allowUnsafeTls;
    return profile;
  }

  private acceptPrivacyPolicy(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new PrivacyConsentStore(context).accept();
    this.privacyAccepted = true;
    this.showPrivacyDialog = false;
  }

  private rejectPrivacyPolicy(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      context.terminateSelf().catch(() => {});
    } catch (_) {
    }
  }

  private requirePrivacyConsent(): boolean {
    if (this.privacyAccepted) return true;
    this.showPrivacyDialog = true;
    return false;
  }

  private clearLocalData(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new RecentHostStore(context).clearAll();
    new ServerProfileStore(context).clear();
    this.devices = [];
    this.addressBookDevices = [];
    this.serverDevices = [];
    this.serverLoginOk = false;
    this.accessToken = '';
    this.serverUsername = '';
    this.applyProfile(new ServerProfile());
    this.serverStatus = '尚未配置 Server Pro';
    this.privacyActionStatus = '本机连接记录、保存密码和服务器配置已清除';
  }

  private saveServerConfig(): void {
    const profile = this.activeProfile();
    const validation: ServerValidation = ServerProfileStore.validate(profile, false);
    if (!validation.valid) {
      this.serverStatus = validation.message;
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const saved = new ServerProfileStore(context).save(profile);
    this.serverStatus = saved ? `配置已保存：${profile.idServer}` : '配置保存失败';
    this.serverLoginOk = false;
    this.accessToken = '';
    if (saved) {
      this.showServerDialog = false;
    }
  }

  private async loginServerPro(): Promise<void> {
    if (!this.requirePrivacyConsent()) return;
    const profile = this.activeProfile();
    const validation: ServerValidation = ServerProfileStore.validate(profile, true);
    if (!validation.valid) {
      this.serverStatus = validation.message;
      return;
    }
    if (this.serverUsername.trim().length === 0 || this.serverPassword.length === 0) {
      this.serverStatus = '请输入 Server Pro 用户名和密码';
      return;
    }
    this.serverStatus = '正在登录 Server Pro…';
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const store = new ServerProfileStore(context);
    store.save(profile);
    const result: ServerLoginResult = await ServerProApi.login(profile, this.serverUsername.trim(),
      this.serverPassword, store.clientUuid());
    this.serverPassword = '';
    this.serverLoginOk = result.success;
    this.accessToken = result.accessToken;
    this.serverStatus = result.message;
    if (result.success) {
      this.showLoginDialog = false;
      this.loadSelectedRemoteSource();
    }
  }

  private logoutServerPro(): void {
    this.serverLoginOk = false;
    this.accessToken = '';
    this.serverPassword = '';
    this.addressBookDevices = [];
    this.serverDevices = [];
    this.serverStatus = '已退出 Server Pro；服务器配置仍保留在本机';
    this.showLoginDialog = false;
  }

  private async selectDeviceMode(mode: string): Promise<void> {
    this.selectedMode = mode;
    this.deviceSelectionMode = false;
    this.selectedDeviceIds = [];
    this.deviceListStatus = '';
    if (mode === 'nearby') {
      await this.discoverLanDevices();
    } else if (mode === 'address' || mode === 'device') {
      if (!this.serverLoginOk || this.accessToken.length === 0) {
        this.serverStatus = '请先登录 Server Pro 以同步设备';
        this.showLoginDialog = true;
        return;
      }
      await this.loadSelectedRemoteSource();
    }
  }

  private async discoverLanDevices(): Promise<void> {
    if (!this.requirePrivacyConsent()) return;
    if (this.deviceListLoading) return;
    this.deviceListLoading = true;
    this.deviceListStatus = '正在搜索局域网内的 RustDesk 设备…';
    try {
      this.lanDevices = await this.lanDiscovery.discover();
      this.deviceListStatus = this.lanDevices.length > 0 ?
        `发现 ${this.lanDevices.length} 台局域网设备` : '未发现设备；请确认远端已允许局域网发现';
    } catch (error) {
      this.deviceListStatus = `局域网搜索失败：${String(error)}`;
    }
    this.deviceListLoading = false;
  }

  private async loadSelectedRemoteSource(): Promise<void> {
    if (!this.serverLoginOk || this.accessToken.length === 0 || this.deviceListLoading) return;
    if (this.selectedMode !== 'address' && this.selectedMode !== 'device') return;
    this.deviceListLoading = true;
    this.deviceListStatus = this.selectedMode === 'address' ? '正在同步 Server Pro 地址簿…' :
      '正在同步 Server Pro 设备…';
    const result: ServerDeviceListResult = this.selectedMode === 'address' ?
      await ServerProApi.addressBook(this.activeProfile(), this.accessToken) :
      await ServerProApi.devices(this.activeProfile(), this.accessToken);
    if (this.selectedMode === 'address') {
      this.addressBookDevices = result.devices;
    } else {
      this.serverDevices = result.devices;
    }
    this.deviceListStatus = result.message;
    this.deviceListLoading = false;
  }

  private sourceDevices(): RemoteDevice[] {
    if (this.selectedMode === 'nearby') return this.lanDevices;
    if (this.selectedMode === 'address') return this.addressBookDevices;
    if (this.selectedMode === 'device') return this.serverDevices;
    if (this.selectedMode === 'favorite') {
      return this.devices.filter((device: RemoteDevice) => device.favorite);
    }
    return this.devices;
  }

  private visibleDevices(): RemoteDevice[] {
    let result = this.sourceDevices().slice();
    const query = this.deviceSearchText.trim().toLowerCase().replace(/\s/g, '');
    if (query.length > 0) {
      result = result.filter((device: RemoteDevice) => {
        return device.id.toLowerCase().replace(/\s/g, '').includes(query) ||
          device.name.toLowerCase().includes(query) || device.platform.toLowerCase().includes(query);
      });
    }
    if (this.deviceSortMode === 'name') {
      result.sort((left: RemoteDevice, right: RemoteDevice) => left.name.localeCompare(right.name));
    } else if (this.deviceSortMode === 'id') {
      result.sort((left: RemoteDevice, right: RemoteDevice) => left.id.localeCompare(right.id));
    } else if (this.deviceSortMode === 'online') {
      result.sort((left: RemoteDevice, right: RemoteDevice) => Number(right.online) - Number(left.online));
    }
    return result;
  }

  private deviceSortLabel(): string {
    if (this.deviceSortMode === 'name') return '名称';
    if (this.deviceSortMode === 'id') return '设备 ID';
    if (this.deviceSortMode === 'online') return '在线优先';
    return '最近连接';
  }

  private cycleDeviceSort(): void {
    if (this.deviceSortMode === 'recent') this.deviceSortMode = 'name';
    else if (this.deviceSortMode === 'name') this.deviceSortMode = 'id';
    else if (this.deviceSortMode === 'id') this.deviceSortMode = 'online';
    else this.deviceSortMode = 'recent';
    this.deviceListStatus = `排序方式：${this.deviceSortLabel()}`;
  }

  private toggleDeviceSelection(id: string): void {
    const selected = this.selectedDeviceIds.includes(id);
    this.selectedDeviceIds = selected ?
      this.selectedDeviceIds.filter((value: string) => value !== id) : this.selectedDeviceIds.concat(id);
    this.selectedDeviceId = id;
  }

  private connectSelectedDevice(): void {
    if (this.selectedDeviceIds.length !== 1) return;
    const id = this.selectedDeviceIds[0];
    const visible = this.visibleDevices();
    for (let index = 0; index < visible.length; index += 1) {
      if (visible[index].id === id) {
        this.deviceSelectionMode = false;
        this.selectedDeviceIds = [];
        this.connect(visible[index]);
        return;
      }
    }
  }

  private deviceConnectable(device: RemoteDevice): boolean {
    return device.id.trim().length > 0;
  }

  private layoutMode(): LayoutMode {
    if (this.viewportWidth < 600) {
      return LayoutMode.Compact;
    }
    if (this.viewportWidth < 960) {
      return LayoutMode.Medium;
    }
    return LayoutMode.Expanded;
  }

  private selectedDevice(): RemoteDevice {
    const sources: RemoteDevice[][] = [this.devices, this.lanDevices, this.addressBookDevices, this.serverDevices];
    for (let sourceIndex = 0; sourceIndex < sources.length; sourceIndex += 1) {
      for (let index = 0; index < sources[sourceIndex].length; index += 1) {
        if (sources[sourceIndex][index].id === this.selectedDeviceId) {
          return sources[sourceIndex][index];
        }
      }
    }
    return this.devices.length > 0 ? this.devices[0] :
      new RemoteDevice('', '远程设备', 'RustDesk', false, false, '', '#69A8E8');
  }

  private editSelectedPassword(): void {
    const device = this.selectedDevice();
    if (device.id.length === 0) return;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new RecentHostStore(context).clearPassword(device.id);
    this.showDeviceMenu = false;
    this.selectedDeviceId = device.id;
    this.pendingRemoteId = device.id.replace(/\s/g, '');
    this.pendingDeviceName = device.name;
    this.password = '';
    this.connectionDialogStatus = '请输入新的远端连接密码';
    this.showConnectionDialog = true;
  }

  private clearSelectedPassword(): void {
    const device = this.selectedDevice();
    if (device.id.length === 0) return;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new RecentHostStore(context).clearPassword(device.id);
    this.showDeviceMenu = false;
    this.statusMessage = `已清除 ${device.name} 的保存密码`;
  }

  private removeSelectedDevice(): void {
    const device = this.selectedDevice();
    if (device.id.length === 0) return;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const store = new RecentHostStore(context);
    store.remove(device.id);
    this.devices = store.load();
    this.selectedDeviceId = this.devices.length > 0 ? this.devices[0].id : '';
    this.showDeviceMenu = false;
  }

  private toggleSelectedFavorite(): void {
    const device = this.selectedDevice();
    if (device.id.length === 0) return;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const store = new RecentHostStore(context);
    if (store.setFavorite(device.id, !device.favorite)) {
      this.devices = store.load();
    }
    this.showDeviceMenu = false;
  }

  private selectedDeviceIsSaved(): boolean {
    for (let index = 0; index < this.devices.length; index += 1) {
      if (this.devices[index].id === this.selectedDeviceId) return true;
    }
    return false;
  }

  private connect(device: RemoteDevice): void {
    if (!this.requirePrivacyConsent()) return;
    const profile = this.activeProfile();
    if (profile.idServer.trim().length > 0 || profile.publicKey.trim().length > 0) {
      const validation: ServerValidation = ServerProfileStore.validateRemoteConnection(profile);
      if (!validation.valid) {
        this.serverStatus = validation.message;
        this.currentPage = 'settings';
        this.showServerDialog = true;
        return;
      }
    }
    this.selectedDeviceId = device.id;
    this.pendingRemoteId = device.id.replace(/\s/g, '');
    this.pendingDeviceName = device.name;
    this.password = '';
    this.connectionDialogStatus = '';
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const savedPassword = new RecentHostStore(context).password(this.pendingRemoteId);
    if (savedPassword.length > 0) {
      this.password = savedPassword;
      this.rememberConnectionPassword = true;
      this.startRemoteConnection(true);
      return;
    }
    this.rememberConnectionPassword = true;
    this.showConnectionDialog = true;
  }

  private startRemoteConnection(usePassword: boolean): void {
    if (this.pendingRemoteId.length === 0) {
      this.connectionDialogStatus = '远程 ID 无效';
      return;
    }
    if (usePassword && this.password.length === 0) {
      this.connectionDialogStatus = '请输入远端 RustDesk 客户端设置的连接密码';
      return;
    }
    const connectionPassword = usePassword ? this.password : '';
    this.activeConnectionPassword = connectionPassword;
    this.activeRememberPassword = usePassword && this.rememberConnectionPassword;
    this.reconnectAttempts = 0;
    this.needsReconnect = false;
    this.manualDisconnect = false;
    this.sessionWasConnected = false;
    this.sessionDeviceName = this.pendingDeviceName.length > 0 ? this.pendingDeviceName : '远程设备';
    this.showConnectionDialog = false;
    this.currentPage = 'session';
    this.connectionState = ConnectionState.Connecting;
    this.statusMessage = usePassword ? '正在使用连接密码建立安全会话' : '正在请求远端手动授权';
    this.openActiveConnection(false);
    this.password = '';
  }

  private openActiveConnection(reconnecting: boolean): void {
    this.connectionState = reconnecting ? ConnectionState.Reconnecting : ConnectionState.Connecting;
    this.statusMessage = reconnecting ? `正在自动重连（第 ${this.reconnectAttempts} 次）` : this.statusMessage;
    this.core.connect(new ConnectRequest(this.pendingRemoteId, this.activeConnectionPassword,
      this.activeProfile()), (state: ConnectionState, message: string) => {
      if (this.manualDisconnect) return;
      if (state === ConnectionState.Connected) {
        this.sessionWasConnected = true;
        this.connectionState = state;
        this.statusMessage = message;
        this.needsReconnect = false;
        this.reconnectAttempts = 0;
        this.stopReconnectTimer();
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const remembered = new RemoteDevice(this.pendingRemoteId, this.sessionDeviceName,
          'RustDesk', true, false, '刚刚', '#69A8E8');
        const store = new RecentHostStore(context);
        store.save(remembered, this.activeRememberPassword ? this.activeConnectionPassword : '');
        this.devices = store.load();
        this.startVideoStatusMonitor();
        this.startVideoRecovery(0);
        return;
      }
      if (state === ConnectionState.Failed || state === ConnectionState.Idle) {
        this.stopVideoStatusMonitor();
        this.stopVideoRecovery();
        if (!this.sessionWasConnected) {
          if (message.includes('密码错误')) {
            const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
            new RecentHostStore(context).clearPassword(this.pendingRemoteId);
            this.currentPage = 'connect';
            this.password = '';
            this.connectionDialogStatus = '保存的密码已失效，请输入远端设备的新密码';
            this.showConnectionDialog = true;
          }
          this.connectionState = ConnectionState.Failed;
          this.statusMessage = message;
          return;
        }
        this.needsReconnect = true;
        this.connectionState = ConnectionState.Reconnecting;
        this.statusMessage = `${message}；等待自动重连`;
        if (this.pageVisible) this.scheduleReconnect(600);
        return;
      }
      this.connectionState = state;
      this.statusMessage = message;
    });
    if (reconnecting) this.startVideoRecovery(0);
  }

  private scheduleReconnect(delay: number): void {
    if (this.reconnectTimer >= 0 || !this.needsReconnect || this.manualDisconnect) return;
    if (this.reconnectAttempts >= 5) {
      this.statusMessage = '自动重连失败，请断开后重新连接';
      return;
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      if (!this.pageVisible || !this.needsReconnect || this.manualDisconnect) return;
      this.reconnectAttempts += 1;
      this.openActiveConnection(true);
    }, delay);
  }

  private stopReconnectTimer(): void {
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  private connectById(): void {
    if (this.remoteId.trim().length === 0) {
      this.statusMessage = '请输入远程设备 ID';
      return;
    }
    const temporary = new RemoteDevice(this.remoteId.trim(), '远程设备', '等待识别', true,
      false, '现在', '#69A8E8');
    this.connect(temporary);
  }

  private disconnect(): void {
    this.manualDisconnect = true;
    this.needsReconnect = false;
    this.stopReconnectTimer();
    this.stopVideoStatusMonitor();
    this.stopVideoRecovery();
    this.closeVirtualMouse();
    this.core.disconnect();
    this.showKeyboard = false;
    this.sessionKeysExpanded = false;
    this.canvasZoom = 1;
    this.sessionScaleMode = 'fit';
    this.canvasOffsetX = 0;
    this.canvasOffsetY = 0;
    this.clipboardComposeMode = false;
    this.showControlPanel = false;
    this.connectionState = ConnectionState.Idle;
    this.currentPage = 'connect';
    this.statusMessage = '连接已断开';
    this.activeConnectionPassword = '';
    this.activeRememberPassword = false;
    this.sessionWasConnected = false;
  }

  private startVideoStatusMonitor(): void {
    this.stopVideoStatusMonitor();
    this.qualityLastFrames = this.core.videoRenderedFrames();
    this.videoStatusTimer = setInterval(() => {
      const status = this.core.videoStatus();
      const frames = this.core.videoRenderedFrames();
      this.qualityFps = frames >= this.qualityLastFrames ? frames - this.qualityLastFrames : frames;
      this.qualityLastFrames = frames;
      this.qualityFrames = frames;
      this.qualityVideoWidth = this.core.videoWidth();
      this.qualityVideoHeight = this.core.videoHeight();
      this.qualityDecoder = status.length > 0 ? status : '等待视频';
      const aspectRatio = this.core.videoAspectRatio();
      if (aspectRatio > 0 && Math.abs(aspectRatio - this.remoteAspectRatio) > 0.001) {
        this.remoteAspectRatio = aspectRatio;
        this.updateVideoViewport();
      }
      if (status.length > 0) this.statusMessage = status;
    }, 1000);
  }

  private stopVideoStatusMonitor(): void {
    if (this.videoStatusTimer >= 0) {
      clearInterval(this.videoStatusTimer);
      this.videoStatusTimer = -1;
    }
  }

  @Builder
  private Icon(symbol: Resource, size: number, color: string) {
    SymbolGlyph(symbol)
      .fontSize(size)
      .fontColor([color])
  }

  @Builder
  private AppHeader(title: string, canBack: boolean) {
    Stack({ alignContent: Alignment.Bottom }) {
      Row() {
        if (canBack) {
          Button() {
            this.Icon($r('sys.symbol.chevron_left'), 27, SURFACE)
          }
          .width(48)
          .height(48)
          .backgroundColor('#00FFFFFF')
          .onClick(() => this.currentPage = 'settings')
        } else {
          Blank().width(48)
        }
        Blank()
        Blank().width(48)
      }
      .width('100%')
      .height(60)
      .padding({ left: 6, right: 6 })

      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(SURFACE)
        .margin({ bottom: 17 })
    }
    .width('100%')
    .height(this.layoutMode() === LayoutMode.Compact ? 112 : 82)
    .backgroundColor(BLUE)
  }

  @Builder
  private BottomNavigation() {
    Row() {
      this.BottomNavItem($r('sys.symbol.computer'), '连接', this.currentPage === 'connect', 'connect')
      this.BottomNavItem($r('sys.symbol.gearshape'), '设置', this.currentPage === 'settings', 'settings')
    }
    .width('100%')
    .height(78)
    .backgroundColor(SURFACE)
    .border({ width: { top: 1 }, color: '#F3F3F3' })
  }

  @Builder
  private BottomNavItem(symbol: Resource, label: string, active: boolean, target: string) {
    Column({ space: 2 }) {
      this.Icon(symbol, 25, active ? '#087CF0' : '#A0A1A3')
      Text(label).fontSize(13).fontColor(active ? '#087CF0' : '#A0A1A3')
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height('100%')
    .onClick(() => this.currentPage = target)
  }

  @Builder
  private RemoteIdBox() {
    Row() {
      Column({ space: 5 }) {
        Text('远程 ID')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(MUTED)
          .width('100%')
        TextInput({ placeholder: '输入远程设备 ID', text: this.remoteId })
          .height(48)
          .padding(0)
          .fontSize(this.remoteId.length > 0 ? 31 : 18)
          .fontWeight(FontWeight.Bold)
          .fontColor(CYAN)
          .placeholderColor('#B5B6BA')
          .backgroundColor('#00FFFFFF')
          .onChange((value: string) => this.remoteId = value)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button() {
        this.Icon($r('sys.symbol.xmark'), 24, '#9A9B9E')
      }
      .width(44)
      .height(52)
      .backgroundColor('#00FFFFFF')
      .onClick(() => this.remoteId = '')

      Button() {
        this.Icon($r('sys.symbol.arrow_right'), 38, '#96979A')
      }
      .width(58)
      .height(58)
      .backgroundColor('#00FFFFFF')
      .onClick(() => this.connectById())
    }
    .width('100%')
    .height(78)
    .padding({ left: 16, right: 10, top: 7, bottom: 6 })
    .borderRadius(14)
    .backgroundColor(INPUT)
  }

  @Builder
  private ModeTabs() {
    Row() {
      this.ModeTab($r('sys.symbol.clock'), 'recent')
      this.ModeTab($r('sys.symbol.star_fill'), 'favorite')
      this.ModeTab($r('sys.symbol.location_north_up_right'), 'nearby')
      this.ModeTab($r('sys.symbol.person_crop_circle_fill_1'), 'address')
      this.ModeTab($r('sys.symbol.computer'), 'device')
      Blank()
      Button() {
        this.Icon($r('sys.symbol.magnifyingglass'), 24, '#858689')
      }.width(42).height(48).backgroundColor(this.deviceSearchVisible ? '#E9F4FE' : '#00FFFFFF')
        .accessibilityDescription('搜索设备')
        .onClick(() => {
          this.deviceSearchVisible = !this.deviceSearchVisible;
          if (!this.deviceSearchVisible) this.deviceSearchText = '';
        })
      Button() {
        this.Icon($r('sys.symbol.checkmark_square'), 22, '#56575A')
      }.width(38).height(48).backgroundColor(this.deviceSelectionMode ? '#E9F4FE' : '#00FFFFFF')
        .accessibilityDescription('选择设备')
        .onClick(() => {
          this.deviceSelectionMode = !this.deviceSelectionMode;
          this.selectedDeviceIds = [];
        })
      Button() {
        this.Icon($r('sys.symbol.line_3_horizontal'), 22, '#56575A')
      }.width(38).height(48).backgroundColor('#00FFFFFF')
        .accessibilityDescription(`排序：${this.deviceSortLabel()}`)
        .onClick(() => this.cycleDeviceSort())
    }
    .width('100%')
    .height(50)
  }

  @Builder
  private ModeTab(symbol: Resource, mode: string) {
    Column() {
      this.Icon(symbol, 24, this.selectedMode === mode ? '#111214' : '#77787B')
      Blank()
        .width(29)
        .height(2)
        .backgroundColor(this.selectedMode === mode ? '#111214' : '#00FFFFFF')
    }
    .justifyContent(FlexAlign.End)
    .width(44)
    .height(50)
    .onClick(() => this.selectDeviceMode(mode))
  }

  @Builder
  private PlatformAvatar(device: RemoteDevice) {
    Stack() {
      this.Icon(device.platform === 'macOS' ? $r('sys.symbol.computer_fill') :
        $r('sys.symbol.computer'), 32, SURFACE)
    }
    .width(48)
    .height(48)
    .borderRadius(6)
    .backgroundColor(device.color)
  }

  @Builder
  private DeviceCard(device: RemoteDevice) {
    Row({ space: 11 }) {
      if (this.deviceSelectionMode) {
        Checkbox({ name: `device-${device.id}`, group: 'deviceSelection' })
          .select(this.selectedDeviceIds.includes(device.id))
          .selectedColor(BLUE)
          .width(28)
          .height(28)
          .onChange(() => this.toggleDeviceSelection(device.id))
      }
      this.PlatformAvatar(device)
      Column({ space: 3 }) {
        Row({ space: 5 }) {
          Blank().width(6).height(6).borderRadius(3).backgroundColor(device.online ? GREEN : MUTED)
          Text(device.id).fontSize(15).fontWeight(FontWeight.Medium).fontColor(TEXT)
        }
        .width('100%')
        Text(device.name)
          .fontSize(14)
          .fontColor('#2A2B2E')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Button() {
        this.Icon($r('sys.symbol.more'), 22, '#303136')
      }
      .width(42)
      .height(56)
      .backgroundColor('#00FFFFFF')
      .onClick(() => {
        this.selectedDeviceId = device.id;
        this.showDeviceMenu = true;
      })
    }
    .width('100%')
    .height(66)
    .padding({ left: 12, right: 5 })
    .borderRadius(5)
    .backgroundColor(this.selectedDeviceIds.includes(device.id) ? '#E6F3FE' : '#F1F2F6')
    .border({ width: this.selectedDeviceIds.includes(device.id) ? 1 : 0, color: BLUE })
    .shadow({ radius: 2, color: '#26000000', offsetX: 0, offsetY: 1 })
    .onClick(() => {
      this.selectedDeviceId = device.id;
      if (this.deviceSelectionMode) {
        this.toggleDeviceSelection(device.id);
      } else if (this.deviceConnectable(device)) {
        this.connect(device);
      }
    })
  }

  @Builder
  private DeviceList() {
    Column({ space: 8 }) {
      if (this.deviceSearchVisible) {
        TextInput({ placeholder: '搜索设备 ID、名称或系统', text: this.deviceSearchText })
          .width('100%').height(42).fontSize(14).backgroundColor(INPUT).borderRadius(10)
          .padding({ left: 13, right: 13 })
          .onChange((value: string) => this.deviceSearchText = value)
      }
      if (this.deviceSelectionMode) {
        Row({ space: 10 }) {
          Text(`已选择 ${this.selectedDeviceIds.length} 台`).fontSize(13).fontColor(TEXT).layoutWeight(1)
          Button('清除').height(34).fontSize(13).fontColor(MUTED).backgroundColor('#00FFFFFF')
            .onClick(() => this.selectedDeviceIds = [])
          Button('连接').height(34).fontSize(13).backgroundColor(BLUE)
            .enabled(this.selectedDeviceIds.length === 1)
            .onClick(() => this.connectSelectedDevice())
        }.width('100%').padding({ left: 4, right: 2 })
      }
      if (this.deviceListStatus.length > 0) {
        Row({ space: 8 }) {
          if (this.deviceListLoading) {
            LoadingProgress().width(16).height(16).color(BLUE)
          }
          Text(this.deviceListStatus).fontSize(12).fontColor(MUTED).layoutWeight(1)
          if (!this.deviceListLoading && (this.selectedMode === 'nearby' ||
            this.selectedMode === 'address' || this.selectedMode === 'device')) {
            Button('刷新').height(32).fontSize(12).fontColor(BLUE).backgroundColor('#00FFFFFF')
              .onClick(() => {
                if (this.selectedMode === 'nearby') this.discoverLanDevices();
                else this.loadSelectedRemoteSource();
              })
          }
        }.width('100%').padding({ left: 4, right: 2 })
      }
      ForEach(this.visibleDevices(), (device: RemoteDevice) => {
        this.DeviceCard(device)
      }, (device: RemoteDevice) => device.id)
      if (!this.deviceListLoading && this.visibleDevices().length === 0) {
        Column({ space: 8 }) {
          this.Icon($r('sys.symbol.computer'), 34, '#B4B6BC')
          Text(this.deviceSearchText.length > 0 ? '没有匹配的设备' :
            (this.selectedMode === 'favorite' ? '暂无收藏设备' : '暂无设备'))
            .fontSize(14).fontColor(MUTED)
        }.width('100%').height(120).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
  }

  @Builder
  private ConnectContent() {
    Column() {
      this.AppHeader('RustDesk', false)
      if (this.layoutMode() === LayoutMode.Compact) {
        Scroll() {
          Column() {
            this.RemoteIdBox()
            this.ModeTabs()
            this.DeviceList()
          }
          .padding({ left: 12, right: 12, top: 10, bottom: 18 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      } else {
        Row({ space: 24 }) {
          Column() {
            this.RemoteIdBox()
            this.ModeTabs()
            Scroll() {
              this.DeviceList()
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
          .width(this.layoutMode() === LayoutMode.Expanded ? 430 : 360)
          .height('100%')
          .padding(20)
          .backgroundColor(SURFACE)

          this.WideDeviceDetail(this.selectedDevice())
        }
        .layoutWeight(1)
        .width('100%')
        .padding(24)
      }
      this.BottomNavigation()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.layoutMode() === LayoutMode.Compact ? SURFACE : BACKGROUND)
  }

  @Builder
  private WideDeviceDetail(device: RemoteDevice) {
    Column({ space: 18 }) {
      this.PlatformAvatar(device)
      Text(device.name).fontSize(25).fontWeight(FontWeight.Bold).fontColor(TEXT)
      Text(device.id).fontSize(18).fontColor(MUTED)
      Row({ space: 6 }) {
        Blank().width(7).height(7).borderRadius(4).backgroundColor(device.online ? GREEN : MUTED)
        Text(device.online ? '在线，可立即连接' : `上次在线：${device.lastSeen}`)
          .fontSize(13).fontColor(device.online ? GREEN : MUTED)
      }
      Divider().color(DIVIDER)
      this.DetailLine('操作系统', device.platform)
      this.DetailLine('连接服务', this.activeProfile().configured() ? 'Server Pro' : '公共服务器')
      this.DetailLine('端到端加密', '已启用')
      Blank()
      Button('远程控制')
        .width('100%')
        .height(48)
        .fontSize(16)
        .backgroundColor(BLUE)
        .borderRadius(12)
        .enabled(this.deviceConnectable(device))
        .onClick(() => this.connect(device))
    }
    .layoutWeight(1)
    .height('100%')
    .padding(30)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .backgroundColor(SURFACE)
  }

  @Builder
  private DetailLine(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor(MUTED)
      Blank()
      Text(value).fontSize(14).fontColor(TEXT)
    }.width('100%')
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontColor('#85868A')
      .width('100%')
      .margin({ left: 18, bottom: 7 })
  }

  @Builder
  private SettingCard(content: WrappedBuilder<[]>) {
    Column() {
      content.builder()
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(SURFACE)
  }

  @Builder
  private SettingAction(symbol: Resource, title: string, subtitle: string, action: string, divider: boolean) {
    Row({ space: 12 }) {
      this.Icon(symbol, 24, '#9A9B9E')
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(TEXT).width('100%')
        if (subtitle.length > 0) {
          Text(subtitle).fontSize(11).fontColor(MUTED).width('100%')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      this.Icon($r('sys.symbol.chevron_right'), 20, '#8D8E92')
    }
    .width('100%')
    .height(subtitle.length > 0 ? 62 : 54)
    .padding({ left: 18, right: 17 })
    .border({ width: { bottom: divider ? 1 : 0 }, color: DIVIDER })
    .onClick(() => {
      if (action === 'server') {
        this.showServerDialog = true;
      } else if (action === 'login') {
        this.showLoginDialog = true;
      } else if (action === 'display') {
        this.currentPage = 'display';
      }
    })
  }

  @Builder
  private ToggleRow(title: string, value: boolean, type: string, divider: boolean) {
    Row() {
      Text(title).fontSize(16).fontColor(TEXT).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(GREEN)
        .onChange((next: boolean) => this.setToggle(type, next))
    }
    .width('100%')
    .height(54)
    .padding({ left: 18, right: 18 })
    .border({ width: { bottom: divider ? 1 : 0 }, color: DIVIDER })
  }

  private setToggle(type: string, value: boolean): void {
    if (type === 'websocket') this.useWebSocket = value;
    if (type === 'tls') this.allowUnsafeTls = value;
    if (type === 'udp') this.udpPunch = value;
    if (type === 'ipv6') this.ipv6P2p = value;
    if (type === 'remark') this.askRemark = value;
    if (type === 'screen') this.keepScreenOn = value;
    if (type === 'browse') this.browseMode = value;
    if (type === 'cursor') this.showRemoteCursor = value;
    if (type === 'followCursor') this.followRemoteCursor = value;
    if (type === 'focus') this.followWindowFocus = value;
    if (type === 'quality') this.showQualityMonitor = value;
    if (type === 'mute') this.mute = value;
    if (type === 'clipboard') this.disableClipboard = value;
    if (type === 'lock') this.lockAfterSession = value;
    if (type === 'privacy') this.privacyMode = value;
    if (type === 'color') this.trueColor = value;
    if (type === 'wheel') this.reverseWheel = value;
    if (type === 'mouse') this.swapMouseButtons = value;
    if (type === 'terminal') this.keepTerminal = value;
  }

  @Builder
  private MainSettingsCard() {
    Column() {
      this.SettingAction($r('sys.symbol.cloud'), 'ID/中继服务器',
        this.activeProfile().configured() ? this.idServer : 'RustDesk 公共服务器', 'server', true)
      this.ToggleRow('使用 WebSocket', this.useWebSocket, 'websocket', true)
      this.ToggleRow('允许 HTTP / 不安全 TLS（仅可信内网）', this.allowUnsafeTls, 'tls', true)
      if (this.allowUnsafeTls) {
        Text('警告：Server Pro 登录凭据可能无法获得传输层保护。请勿用于公共网络。')
          .fontSize(11).fontColor(DANGER).width('100%')
          .padding({ left: 18, right: 18, bottom: 10 })
      }
      this.ToggleRow('启用 UDP 打洞', this.udpPunch, 'udp', true)
      this.ToggleRow('启用 IPv6 P2P 连接', this.ipv6P2p, 'ipv6', true)
      this.ToggleRow('在连接结束时请求备注', this.askRemark, 'remark', true)
      this.ToggleRow('传出会话期间保持屏幕常亮', this.keepScreenOn, 'screen', false)
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(SURFACE)
  }

  @Builder
  private AboutCard() {
    Column() {
      Row({ space: 12 }) {
        this.Icon($r('sys.symbol.info_circle_fill'), 24, '#9A9B9E')
        Text('Version: 1.0.0').fontSize(16).fontColor(TEXT).layoutWeight(1)
        Text('第三方兼容客户端').fontSize(13).fontColor(MUTED)
      }.height(54).padding({ left: 18, right: 18 })
      Divider().color(DIVIDER).margin({ left: 50 })
      Row({ space: 12 }) {
        this.Icon($r('sys.symbol.clock'), 24, '#9A9B9E')
        Text('构建日期').fontSize(16).fontColor(TEXT).layoutWeight(1)
        Text('2026-07-22').fontSize(14).fontColor('#3D3E41')
      }.height(54).padding({ left: 18, right: 18 })
      Divider().color(DIVIDER).margin({ left: 50 })
      Row({ space: 12 }) {
        this.Icon($r('sys.symbol.phone_shield_fill'), 24, '#9A9B9E')
        Text('隐私政策').fontSize(16).fontColor(TEXT).layoutWeight(1)
        this.Icon($r('sys.symbol.chevron_right'), 19, '#8D8E92')
      }.height(54).padding({ left: 18, right: 18 }).onClick(() => this.currentPage = 'privacy')
      Divider().color(DIVIDER).margin({ left: 50 })
      Row({ space: 12 }) {
        this.Icon($r('sys.symbol.doc_text'), 24, '#9A9B9E')
        Text('开源许可与第三方声明').fontSize(16).fontColor(TEXT).layoutWeight(1)
        this.Icon($r('sys.symbol.chevron_right'), 19, '#8D8E92')
      }.height(54).padding({ left: 18, right: 18 }).onClick(() => this.currentPage = 'licenses')
      Divider().color(DIVIDER).margin({ left: 50 })
      Text('本应用是兼容 RustDesk 协议的第三方客户端，并非 RustDesk 官方产品。')
        .fontSize(11).fontColor(MUTED).width('100%').padding({ left: 18, right: 18, top: 12, bottom: 14 })
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(SURFACE)
  }

  @Builder
  private SettingsContent() {
    Column() {
      this.AppHeader('RustDesk', false)
      Scroll() {
        Column() {
          this.SectionTitle('账户')
          Column() {
            this.SettingAction($r('sys.symbol.person_fill'),
              this.serverLoginOk ? `已登录 ${this.serverUsername}` : '登录',
              this.serverLoginOk ? 'Server Pro 地址簿已同步' : '登录 Server Pro 账户', 'login', false)
          }.width('100%').borderRadius(14).backgroundColor(SURFACE)
          .margin({ bottom: 34 })

          this.SectionTitle('设置')
          Column() {
            this.MainSettingsCard()
          }
          .width('100%')
          .margin({ bottom: 34 })

          this.SectionTitle('显示设置')
          Column() {
            this.SettingAction($r('sys.symbol.computer'), '显示设置', '画质、缩放与输入选项', 'display', false)
          }.width('100%').borderRadius(14).backgroundColor(SURFACE)
          .margin({ bottom: 34 })

          this.SectionTitle('关于')
          this.AboutCard()
        }
        .width(this.layoutMode() === LayoutMode.Compact ? '100%' : 680)
        .padding({ left: 15, right: 15, top: 34, bottom: 28 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      this.BottomNavigation()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BACKGROUND)
  }

  @Builder
  private PolicySection(title: string, body: string) {
    Column({ space: 7 }) {
      Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(TEXT).width('100%')
      Text(body).fontSize(14).fontColor('#4A4B4F').lineHeight(22).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 22 })
  }

  @Builder
  private PrivacyPolicyContent() {
    Column() {
      this.AppHeader('隐私政策', true)
      Scroll() {
        Column() {
          Text('RustDesk Harmony 隐私政策')
            .fontSize(24).fontWeight(FontWeight.Bold).fontColor(TEXT).width('100%')
          Text('生效日期：2026-07-22 · 开发者：ponyrun')
            .fontSize(12).fontColor(MUTED).width('100%').margin({ top: 6, bottom: 24 })
          this.PolicySection('产品身份',
            '本应用是兼容 RustDesk 协议的第三方远程桌面客户端，并非 RustDesk 官方产品。')
          this.PolicySection('处理的数据',
            '在你主动使用对应功能时，本应用会处理远端设备 ID、设备名称、服务器地址和公钥、Server Pro 用户名与访问令牌、连接密码、地址簿与局域网设备信息，以及你主动发送或接收的聊天和剪贴板文本。')
          this.PolicySection('处理目的与传输对象',
            '上述数据仅用于建立你指定的远程控制会话、登录你配置的 Server Pro、同步其设备列表、搜索同一局域网内的兼容设备以及完成聊天和剪贴板交换。网络数据发送至你配置或选择的 RustDesk/Server Pro 服务器和远端设备；开发者不运营默认数据收集服务器。')
          this.PolicySection('本地存储与安全',
            '远端 ID、设备名称和服务器配置保存在 HarmonyOS Preferences。只有在你勾选“记住连接密码”时，连接密码才会写入 HarmonyOS Asset Store，并设置为设备解锁后可访问。Server Pro 密码不会持久化，访问令牌只保存在当前进程内存中。')
          this.PolicySection('HTTP 风险',
            '应用默认不允许使用 HTTP 登录 Server Pro。若你主动开启“允许 HTTP / 不安全 TLS”，登录凭据可能缺少传输层保护；该选项仅适用于你信任的隔离内网，不应在公共网络使用。')
          this.PolicySection('系统权限',
            '应用仅声明网络访问权限。应用不会申请受限的剪贴板读取权限；本机到远端的剪贴板发送需要你主动粘贴和确认，远端到本机的文本仅在已建立的会话中写入系统剪贴板。')
          this.PolicySection('保存期限与删除',
            '本地记录保存至你删除对应主机、点击下方清除按钮或卸载应用。Server Pro 中的账户和地址簿数据由你所使用的服务器管理，请通过该服务器管理员提供的方式查询、更正或删除。')
          this.PolicySection('未成年人、变更与联系',
            '本应用不面向未满十四周岁的儿童提供专门服务。政策发生实质变化时会更新生效日期并重新征求同意。你可通过华为应用市场详情页展示的开发者联系方式与开发者联系。')
          if (!this.privacyAccepted) {
            Button('同意隐私政策并继续使用')
              .width('100%').height(48).backgroundColor(BLUE).borderRadius(12).margin({ bottom: 12 })
              .onClick(() => this.acceptPrivacyPolicy())
          }
          Button('清除本机连接记录、保存密码和服务器配置')
            .width('100%').height(48).fontColor(DANGER).backgroundColor('#FFF0F1').borderRadius(12)
            .onClick(() => this.clearLocalData())
          if (this.privacyActionStatus.length > 0) {
            Text(this.privacyActionStatus).fontSize(12).fontColor(GREEN).width('100%').margin({ top: 10 })
          }
        }
        .width(this.layoutMode() === LayoutMode.Compact ? '100%' : 680)
        .padding({ left: 22, right: 22, top: 28, bottom: 38 })
      }.layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor(BACKGROUND)
  }

  @Builder
  private LicensesContent() {
    Column() {
      this.AppHeader('开源许可', true)
      Scroll() {
        Column() {
          Text('开源许可与第三方声明')
            .fontSize(24).fontWeight(FontWeight.Bold).fontColor(TEXT).width('100%').margin({ bottom: 22 })
          this.PolicySection('RustDesk 兼容协议代码',
            '本项目包含或派生自 RustDesk 1.4.7 的协议实现。相关代码按 GNU Affero General Public License v3.0 or later 分发。RustDesk 名称及商标归其权利人所有，本应用并非官方产品。完整许可证见发行源码根目录 LICENSE 和 third_party/rustdesk-upstream/LICENCE。')
          this.PolicySection('libsodium',
            '加密实现使用 libsodium 1.0.20，适用 ISC License。完整许可文本见 third_party/libsodium/LICENSE。')
          this.PolicySection('Zstandard',
            '远程光标解压使用 Zstandard 1.5.7，适用 BSD License。完整许可文本见 third_party/zstd/LICENSE。')
          this.PolicySection('源码获取',
            '与本发行版本对应的完整源码、构建说明和第三方许可文件应随应用市场版本在开发者公开源码页面提供。发行时请将 release-assets/source-code-offer.txt 中的源码地址替换为实际公开地址。')
        }
        .width(this.layoutMode() === LayoutMode.Compact ? '100%' : 680)
        .padding({ left: 22, right: 22, top: 28, bottom: 38 })
      }.layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor(BACKGROUND)
  }

  @Builder
  private PrivacyConsentDialog() {
    Column() {
      Text('隐私保护说明').fontSize(21).fontWeight(FontWeight.Medium).fontColor(TEXT).width('100%')
      Scroll() {
        Text('在你主动连接设备、登录 Server Pro、搜索局域网设备或交换剪贴板前，本应用需要处理远端设备 ID、服务器配置、账户凭据、连接密码和会话文本。连接密码仅在你勾选“记住连接密码”时写入 HarmonyOS 安全资产存储。\n\n本应用是兼容 RustDesk 协议的第三方客户端，并非 RustDesk 官方产品。你可以先阅读完整隐私政策；不同意将退出应用。')
          .fontSize(14).fontColor('#44454A').lineHeight(22).width('100%')
      }.height(220).width('100%').margin({ top: 16, bottom: 10 })
      Button('查看完整隐私政策').width('100%').height(42).fontColor(BLUE).backgroundColor('#00FFFFFF')
        .onClick(() => {
          this.showPrivacyDialog = false;
          this.currentPage = 'privacy';
        })
      Row({ space: 10 }) {
        Button('不同意并退出').layoutWeight(1).height(46).fontColor(MUTED).backgroundColor('#EEF0F4')
          .onClick(() => this.rejectPrivacyPolicy())
        Button('同意并继续').layoutWeight(1).height(46).backgroundColor(BLUE)
          .onClick(() => this.acceptPrivacyPolicy())
      }.width('100%').margin({ top: 8 })
    }
    .width(this.layoutMode() === LayoutMode.Compact ? '88%' : 480)
    .padding(24).borderRadius(22).backgroundColor(SURFACE)
    .shadow({ radius: 24, color: '#55000000', offsetX: 0, offsetY: 12 })
  }

  @Builder
  private ValueRow(title: string, value: string, divider: boolean) {
    Row() {
      Text(title).fontSize(16).fontColor(TEXT).layoutWeight(1)
      Text(value).fontSize(15).fontColor('#3F4043')
      this.Icon($r('sys.symbol.chevron_right'), 18, '#9A9B9E')
    }
    .width('100%').height(54).padding({ left: 18, right: 15 })
    .border({ width: { bottom: divider ? 1 : 0 }, color: DIVIDER })
  }

  @Builder
  private DisplaySettingsContent() {
    Column() {
      this.AppHeader('显示设置', true)
      Scroll() {
        Column() {
          Column() {
            this.ValueRow('默认显示方式', '适应窗口', true)
            this.ValueRow('默认图像质量', '平衡', true)
            this.ValueRow('默认编解码', '自动', false)
          }.width('100%').borderRadius(14).backgroundColor(SURFACE)
          .margin({ bottom: 34 })

          this.SectionTitle('其它默认选项')
          Column() {
            this.ToggleRow('浏览模式', this.browseMode, 'browse', true)
            this.ToggleRow('显示远程光标', this.showRemoteCursor, 'cursor', true)
            this.ToggleRow('跟随远程光标', this.followRemoteCursor, 'followCursor', true)
            this.ToggleRow('跟随远程窗口焦点', this.followWindowFocus, 'focus', true)
            this.ToggleRow('显示质量监测', this.showQualityMonitor, 'quality', true)
            this.ToggleRow('静音', this.mute, 'mute', true)
            this.ToggleRow('禁用剪贴板', this.disableClipboard, 'clipboard', true)
            this.ToggleRow('会话结束后锁定远程电脑', this.lockAfterSession, 'lock', true)
            this.ToggleRow('隐私模式', this.privacyMode, 'privacy', true)
            this.ToggleRow('真彩模式（4:4:4）', this.trueColor, 'color', true)
            this.ToggleRow('鼠标滚轮反向', this.reverseWheel, 'wheel', true)
            this.ToggleRow('交换鼠标左右键', this.swapMouseButtons, 'mouse', true)
            this.ToggleRow('断开连接时保持终端会话', this.keepTerminal, 'terminal', false)
          }.width('100%').borderRadius(14).backgroundColor(SURFACE)
        }
        .width(this.layoutMode() === LayoutMode.Compact ? '100%' : 680)
        .padding({ left: 15, right: 15, top: 32, bottom: 30 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(BACKGROUND)
  }

  @Builder
  private DialogField(label: string, placeholder: string, value: string, type: string) {
    Column({ space: 2 }) {
      Text(label).fontSize(12).fontColor('#B0B1B4').width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .height(38)
        .fontSize(15)
        .fontColor(TEXT)
        .backgroundColor('#00FFFFFF')
        .padding(0)
        .onChange((next: string) => {
          if (type === 'id') this.idServer = next;
          if (type === 'relay') this.relayServer = next;
          if (type === 'api') this.apiServer = next;
          if (type === 'key') this.serverPublicKey = next;
          if (type === 'user') this.serverUsername = next;
          if (type === 'password') this.serverPassword = next;
        })
      Divider().color('#9FA0A3')
    }.width('100%')
  }

  @Builder
  private ServerDialog() {
    Column() {
      Row() {
        Text('ID/中继服务器').fontSize(20).fontWeight(FontWeight.Medium).fontColor(TEXT).layoutWeight(1)
        Button() { this.Icon($r('sys.symbol.clipboard_sharing'), 22, '#A0A1A4') }
          .width(42).height(42).backgroundColor('#00FFFFFF')
        Button() { this.Icon($r('sys.symbol.doc_filled_on_doc'), 22, '#A0A1A4') }
          .width(42).height(42).backgroundColor('#00FFFFFF')
      }.width('100%')
      Column({ space: 14 }) {
        this.DialogField('ID 服务器', 'hbbs.example.com:21116', this.idServer, 'id')
        this.DialogField('中继服务器', 'hbbr.example.com:21117（可选）', this.relayServer, 'relay')
        this.DialogField('API 服务器', 'https://api.example.com', this.apiServer, 'api')
        this.DialogField('Key', '服务器公钥，不是许可证密钥', this.serverPublicKey, 'key')
      }.margin({ top: 28 })
      if (this.serverStatus.length > 0 && !this.serverStatus.startsWith('尚未')) {
        Text(this.serverStatus)
          .fontSize(11)
          .fontColor(this.serverStatus.includes('失败') || this.serverStatus.includes('请输入') ? DANGER : MUTED)
          .width('100%')
          .margin({ top: 10 })
      }
      Row({ space: 12 }) {
        Blank()
        Button('取消').fontSize(16).fontColor(BLUE).backgroundColor('#00FFFFFF')
          .onClick(() => this.showServerDialog = false)
        Button('确认').fontSize(16).fontColor(BLUE).backgroundColor('#00FFFFFF')
          .onClick(() => this.saveServerConfig())
      }.width('100%').margin({ top: 18 })
    }
    .width(this.layoutMode() === LayoutMode.Compact ? '82%' : 520)
    .padding({ left: 24, right: 24, top: 24, bottom: 18 })
    .borderRadius(20)
    .backgroundColor(SURFACE)
    .shadow({ radius: 24, color: '#55000000', offsetX: 0, offsetY: 12 })
  }

  @Builder
  private LoginDialog() {
    Column() {
      Text('登录 Server Pro').fontSize(20).fontWeight(FontWeight.Medium).fontColor(TEXT).width('100%')
      Text('登录后可同步地址簿、设备分组和策略。密码不会保存。')
        .fontSize(12).fontColor(MUTED).width('100%').margin({ top: 7, bottom: 22 })
      Column({ space: 16 }) {
        this.DialogField('用户名', 'Server Pro 用户名', this.serverUsername, 'user')
        Column({ space: 2 }) {
          Text('密码').fontSize(12).fontColor('#B0B1B4').width('100%')
          TextInput({ placeholder: 'Server Pro 密码', text: this.serverPassword })
            .type(InputType.Password)
            .height(38)
            .fontSize(15)
            .fontColor(TEXT)
            .backgroundColor('#00FFFFFF')
            .padding(0)
            .onChange((next: string) => this.serverPassword = next)
          Divider().color('#9FA0A3')
        }.width('100%')
      }
      Text(this.serverStatus).fontSize(11).fontColor(this.serverLoginOk ? GREEN : MUTED)
        .width('100%').margin({ top: 12 })
      Row({ space: 12 }) {
        Blank()
        Button('取消').fontSize(16).fontColor(BLUE).backgroundColor('#00FFFFFF')
          .onClick(() => this.showLoginDialog = false)
        Button('登录').fontSize(16).fontColor(BLUE).backgroundColor('#00FFFFFF')
          .onClick(() => this.loginServerPro())
      }.width('100%').margin({ top: 12 })
      if (this.serverLoginOk) {
        Button('退出当前 Server Pro 账户')
          .width('100%').height(42).fontColor(DANGER).backgroundColor('#00FFFFFF')
          .onClick(() => this.logoutServerPro())
      }
    }
    .width(this.layoutMode() === LayoutMode.Compact ? '82%' : 460)
    .padding(24).borderRadius(20).backgroundColor(SURFACE)
    .shadow({ radius: 24, color: '#55000000', offsetX: 0, offsetY: 12 })
  }

  @Builder
  private ConnectionDialog() {
    Column() {
      Row({ space: 12 }) {
        Stack() {
          this.Icon($r('sys.symbol.computer'), 26, SURFACE)
        }.width(46).height(46).borderRadius(12).backgroundColor(BLUE)
        Column({ space: 3 }) {
          Text('连接远程桌面').fontSize(20).fontWeight(FontWeight.Medium).fontColor(TEXT)
          Text(`${this.pendingDeviceName} · ${this.pendingRemoteId}`)
            .fontSize(12).fontColor(MUTED).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')

      Text('连接密码')
        .fontSize(13).fontColor(MUTED).width('100%').margin({ top: 24, bottom: 6 })
      TextInput({ placeholder: '输入远端 RustDesk 客户端设置的密码', text: this.password })
        .type(InputType.Password)
        .height(48)
        .fontSize(16)
        .fontColor(TEXT)
        .placeholderColor('#A7A8AC')
        .backgroundColor(INPUT)
        .borderRadius(11)
        .padding({ left: 14, right: 14 })
        .onChange((value: string) => {
          this.password = value;
          this.connectionDialogStatus = '';
        })

      Row({ space: 8 }) {
        Checkbox({ name: 'rememberRemotePassword', group: 'connection' })
          .select(this.rememberConnectionPassword)
          .selectedColor(BLUE)
          .onChange((value: boolean) => this.rememberConnectionPassword = value)
        Text('记住连接密码')
          .fontSize(14).fontColor(TEXT).layoutWeight(1)
      }.width('100%').height(42).margin({ top: 5 })
      Text(this.rememberConnectionPassword ?
        '密码将在设备解锁后由 HarmonyOS 安全资产存储保护，可在主机菜单中清除。' :
        '密码仅用于本次端到端加密认证，本次连接结束后不保存。')
        .fontSize(11).fontColor(MUTED).width('100%')
      if (this.connectionDialogStatus.length > 0) {
        Text(this.connectionDialogStatus)
          .fontSize(12).fontColor(DANGER).width('100%').margin({ top: 9 })
      }

      Button('使用密码连接')
        .width('100%').height(48).margin({ top: 20 })
        .fontSize(16).fontWeight(FontWeight.Medium)
        .backgroundColor(BLUE).borderRadius(12)
        .onClick(() => this.startRemoteConnection(true))
      Button('不输入密码，请求远端授权')
        .width('100%').height(44).margin({ top: 7 })
        .fontSize(14).fontColor(BLUE).backgroundColor('#00FFFFFF')
        .onClick(() => {
          this.password = '';
          this.startRemoteConnection(false);
        })
      Button('取消')
        .width('100%').height(40)
        .fontSize(14).fontColor(MUTED).backgroundColor('#00FFFFFF')
        .onClick(() => {
          this.password = '';
          this.showConnectionDialog = false;
        })
    }
    .width(this.layoutMode() === LayoutMode.Compact ? '88%' : 460)
    .padding({ left: 24, right: 24, top: 24, bottom: 14 })
    .borderRadius(22).backgroundColor(SURFACE)
    .shadow({ radius: 24, color: '#55000000', offsetX: 0, offsetY: 12 })
  }

  @Builder
  private DeviceMenu() {
    Column() {
      Text(this.selectedDevice().name).fontSize(18).fontWeight(FontWeight.Medium).fontColor(TEXT)
        .width('100%').padding({ bottom: 14 })
      Button('远程控制').width('100%').height(46).backgroundColor(BLUE)
        .onClick(() => { this.showDeviceMenu = false; this.connect(this.selectedDevice()); })
      Button('重新输入连接密码').width('100%').height(46).fontColor(BLUE).backgroundColor('#00FFFFFF')
        .onClick(() => this.editSelectedPassword())
      if (this.selectedDeviceIsSaved()) {
        Button('清除保存的连接密码').width('100%').height(46).fontColor(BLUE).backgroundColor('#00FFFFFF')
          .onClick(() => this.clearSelectedPassword())
        Button(this.selectedDevice().favorite ? '取消收藏' : '添加到收藏')
          .width('100%').height(46).fontColor(BLUE).backgroundColor('#00FFFFFF')
          .onClick(() => this.toggleSelectedFavorite())
        Button('删除保存的主机').width('100%').height(46).fontColor(DANGER).backgroundColor('#00FFFFFF')
          .onClick(() => this.removeSelectedDevice())
      }
      Button('取消').width('100%').height(46).fontColor(MUTED).backgroundColor('#00FFFFFF')
        .onClick(() => this.showDeviceMenu = false)
    }
    .width(this.layoutMode() === LayoutMode.Compact ? '88%' : 420)
    .padding(20).borderRadius(18).backgroundColor(SURFACE)
  }

  @Builder
  private SessionKeyButton(label: string, code: number, active: boolean = false) {
    Button(label)
      .height(34).layoutWeight(1).fontSize(11).fontWeight(FontWeight.Medium)
      .fontColor(SURFACE).backgroundColor(active ? '#0E72D8' : '#00000000').borderRadius(8)
      .onClick(() => this.handleSessionKey(label, code))
  }

  @Builder
  private SessionShortcutButton(label: string, text: string, modifier: number) {
    Button(label)
      .height(34).layoutWeight(1).fontSize(11).fontWeight(FontWeight.Medium)
      .fontColor(SURFACE).backgroundColor('#00000000').borderRadius(8)
      .onClick(() => this.sendNamedShortcut(text, modifier))
  }

  @Builder
  private SessionFunctionKeys() {
    Column({ space: 3 }) {
      Row({ space: 2 }) {
        this.SessionKeyButton('Ctrl', 4, this.sessionCtrl)
        this.SessionKeyButton('Alt', 1, this.sessionAlt)
        this.SessionKeyButton('Shift', 29, this.sessionShift)
        this.SessionKeyButton('Cmd', 23, this.sessionMeta)
        this.SessionKeyButton('Fn', 0)
        this.SessionKeyButton('固定', 0)
        Button('•••').height(34).layoutWeight(1).fontSize(12).fontColor(SURFACE)
          .backgroundColor('#0E61B8').borderRadius(8)
          .onClick(() => this.toggleSessionPanel('display'))
      }.width('100%')
      Row({ space: 2 }) {
        this.SessionKeyButton('Esc', 8)
        this.SessionKeyButton('Tab', 31)
        this.SessionKeyButton('主页', 21)
        this.SessionKeyButton('End', 7)
        this.SessionKeyButton('Ins', 58)
        this.SessionKeyButton('Del', 5)
        this.SessionKeyButton('PgUp', 26)
        this.SessionKeyButton('PgDn', 25)
        this.SessionKeyButton('Enter', 27)
      }.width('100%')
      Row({ space: 2 }) {
        this.SessionKeyButton('‹', 22)
        this.SessionKeyButton('⌃', 32)
        this.SessionKeyButton('⌄', 6)
        this.SessionKeyButton('›', 28)
        this.SessionShortcutButton('Cmd+C', 'c', 23)
        this.SessionShortcutButton('Cmd+V', 'v', 23)
        this.SessionShortcutButton('Cmd+S', 's', 23)
      }.width('100%')
    }
    .width('100%').height(116).padding({ left: 6, right: 6, top: 5, bottom: 5 })
    .backgroundColor('#070809')
  }

  @Builder
  private SessionBottomToolbar() {
    Row() {
      Button() { this.Icon($r('sys.symbol.xmark'), 23, SURFACE) }
        .height(66).layoutWeight(1).backgroundColor('#00000000').onClick(() => this.disconnect())
      Button() { this.Icon($r('sys.symbol.computer'), 23, SURFACE) }
        .height(66).layoutWeight(1).backgroundColor(this.sessionPanel === 'display' ? '#0868CC' : '#00000000')
        .onClick(() => this.toggleSessionPanel('display'))
      Button() { this.Icon($r('sys.symbol.keyboard'), 23, SURFACE) }
        .height(66).layoutWeight(1).backgroundColor(this.showKeyboard ? '#0868CC' : '#00000000')
        .onClick(() => this.toggleDirectRemoteKeyboard())
      Button() {
        this.Icon($r('sys.symbol.location_north_up_right'), 23, SURFACE)
      }
        .height(66).layoutWeight(1)
        .backgroundColor(this.sessionPanel === 'input' ? '#0868CC' : '#00000000')
        .onClick(() => this.toggleSessionPanel('input'))
      Button() { this.Icon($r('sys.symbol.message'), 23, SURFACE) }
        .height(66).layoutWeight(1)
        .backgroundColor(this.sessionPanel === 'chat' ? '#0868CC' : '#00000000')
        .onClick(() => this.toggleSessionPanel('chat'))
      Button() { this.Icon($r('sys.symbol.more'), 23, SURFACE) }
        .height(66).layoutWeight(1).backgroundColor(this.sessionPanel === 'more' ? '#0868CC' : '#00000000')
        .onClick(() => this.toggleSessionPanel('more'))
      Button() {
        this.Icon($r('sys.symbol.chevron_left'), 22, SURFACE)
      }
        .height(66).layoutWeight(1).backgroundColor('#00000000')
        .rotate({ angle: -90 })
        .onClick(() => {
          this.showKeyboard = false;
          this.sessionKeysExpanded = false;
          this.sessionPanel = 'none';
        })
    }
    .width('100%').height(66).backgroundColor('#0A7BF5')
  }

  @Builder
  private SessionInputSheet() {
    Column({ space: 14 }) {
      Row() {
        Button('鼠标模式').height(48).layoutWeight(1).fontSize(16)
          .fontColor(this.sessionInputMode === 'mouse' ? SURFACE : '#E2E2E2')
          .backgroundColor(this.sessionInputMode === 'mouse' ? '#0A7BF5' : '#A4A5A7')
          .borderRadius({ topLeft: 12, bottomLeft: 12 })
          .onClick(() => this.setSessionInputMode('mouse'))
        Button('触屏模式').height(48).layoutWeight(1).fontSize(16)
          .fontColor(this.sessionInputMode === 'touch' ? SURFACE : '#E2E2E2')
          .backgroundColor(this.sessionInputMode === 'touch' ? '#0A7BF5' : '#A4A5A7')
          .borderRadius({ topRight: 12, bottomRight: 12 })
          .onClick(() => this.setSessionInputMode('touch'))
      }.width('100%')
      Row({ space: 10 }) {
        Checkbox({ name: 'remoteCursor', group: 'sessionInput' }).select(this.showRemoteCursor)
          .selectedColor('#0A7BF5').onChange((value: boolean) => this.showRemoteCursor = value)
        Text('显示远程光标').fontSize(15).fontColor(SURFACE)
      }.width('100%')
      Row({ space: 10 }) {
        Checkbox({ name: 'virtualMouse', group: 'sessionInput' }).select(this.showVirtualMouse)
          .selectedColor('#0A7BF5').onChange((value: boolean) => {
            if (value) this.openVirtualMouse(); else this.closeVirtualMouse();
            this.sessionPanel = 'input';
          })
        Text('显示悬浮虚拟鼠标').fontSize(15).fontColor(SURFACE)
      }.width('100%')
      Text('远程光标大小').width('100%').fontSize(14).fontColor('#E8E8E8')
      Row({ space: 10 }) {
        Text('小').fontSize(13).fontColor('#D6D6D6')
        Slider({ value: this.sessionCursorSize, min: 0.6, max: 1.8, step: 0.1 })
          .layoutWeight(1).selectedColor('#2196F3')
          .onChange((value: number) => this.sessionCursorSize = value)
        Text('大').fontSize(13).fontColor('#D6D6D6')
      }.width('100%')
      Row() {
        Column({ space: 4 }) {
          Text('单指轻触').fontSize(12).fontColor('#0A8BFF')
          Text('鼠标左键').fontSize(14).fontColor('#D6D6D6')
        }.layoutWeight(1)
        Column({ space: 4 }) {
          Text('单指长按').fontSize(12).fontColor('#0A8BFF')
          Text('鼠标右键').fontSize(14).fontColor('#D6D6D6')
        }.layoutWeight(1)
        Column({ space: 4 }) {
          Text(this.sessionInputMode === 'mouse' ? '双击并移动' : '单指移动').fontSize(12).fontColor('#0A8BFF')
          Text('鼠标拖动').fontSize(14).fontColor('#D6D6D6')
        }.layoutWeight(1)
      }.width('100%')
      Row() {
        Column({ space: 4 }) {
          Text('三指垂直滑动').fontSize(12).fontColor('#0A8BFF')
          Text('鼠标滚轮').fontSize(14).fontColor('#D6D6D6')
        }.layoutWeight(1)
        Column({ space: 4 }) {
          Text('双指移动').fontSize(12).fontColor('#0A8BFF')
          Text('移动画布').fontSize(14).fontColor('#D6D6D6')
        }.layoutWeight(1)
        Column({ space: 4 }) {
          Text('双指缩放').fontSize(12).fontColor('#0A8BFF')
          Text('缩放画布').fontSize(14).fontColor('#D6D6D6')
        }.layoutWeight(1)
      }.width('100%')
    }
    .width('100%').height(345).padding({ left: 28, right: 28, top: 20, bottom: 16 })
    .backgroundColor('#EE444444')
    .position({ x: 0, y: Math.max(0, this.sessionAreaHeight - 345) }).zIndex(4)
    .onTouch((event: TouchEvent) => event.stopPropagation())
  }

  private selectSessionOption(group: string, value: string): void {
    if (group === 'scale') {
      this.sessionScaleMode = value;
      if (value === 'fit') {
        this.canvasZoom = 1;
        this.canvasOffsetX = 0;
        this.canvasOffsetY = 0;
      }
      if (value === 'custom' && this.canvasZoom <= 1) this.canvasZoom = 1.35;
      this.clampCanvasOffset();
      this.updateVideoViewport();
    }
    if (group === 'quality') this.sessionQuality = value;
    if (group === 'codec') this.sessionCodec = value;
  }

  @Builder
  private SessionRadioRow(label: string, group: string, value: string, selected: boolean) {
    Row() {
      Text(label).fontSize(16).fontColor('#F3F3F5').layoutWeight(1)
      Radio({ value: value, group: group }).checked(selected).width(28).height(28)
        .onChange((checked: boolean) => { if (checked) this.selectSessionOption(group, value); })
    }.width('100%').height(48).onClick(() => this.selectSessionOption(group, value))
  }

  @Builder
  private SessionDisplayPanel() {
    Column({ space: 4 }) {
      Text('安全连接').fontSize(30).fontColor('#4FA75D')
      Text('加密中继连接 (TCP)').fontSize(14).fontColor('#ECECF0')
      Divider().color('#45464B').margin({ top: 8, bottom: 4 })
      Scroll() {
        Column() {
          this.SessionRadioRow('原始尺寸', 'scale', 'original', this.sessionScaleMode === 'original')
          this.SessionRadioRow('适应窗口', 'scale', 'fit', this.sessionScaleMode === 'fit')
          this.SessionRadioRow('自定义缩放', 'scale', 'custom', this.sessionScaleMode === 'custom')
          Divider().color('#45464B')
          this.SessionRadioRow('画质最优化', 'quality', 'best', this.sessionQuality === 'best')
          this.SessionRadioRow('平衡', 'quality', 'balanced', this.sessionQuality === 'balanced')
          this.SessionRadioRow('速度最优化', 'quality', 'speed', this.sessionQuality === 'speed')
          this.SessionRadioRow('自定义', 'quality', 'custom', this.sessionQuality === 'custom')
          Divider().color('#45464B')
          this.SessionRadioRow('自动 (H265)', 'codec', 'auto', this.sessionCodec === 'auto')
          this.SessionRadioRow('VP8', 'codec', 'vp8', this.sessionCodec === 'vp8')
          this.SessionRadioRow('VP9', 'codec', 'vp9', this.sessionCodec === 'vp9')
          this.SessionRadioRow('H265', 'codec', 'h265', this.sessionCodec === 'h265')
          Divider().color('#45464B')
          Row() {
            Text('分辨率').fontSize(16).fontColor('#F3F3F5').layoutWeight(1)
            Text(`${this.qualityVideoWidth} × ${this.qualityVideoHeight}`).fontSize(13).fontColor('#AEB1B8')
          }.height(52).width('100%')
          Divider().color('#45464B')
          Row() {
            Text('显示远程光标').fontSize(16).fontColor('#F3F3F5').layoutWeight(1)
            Checkbox({ name: 'displayCursor', group: 'displayPanel' }).select(this.showRemoteCursor)
              .selectedColor('#0A7BF5').onChange((value: boolean) => this.showRemoteCursor = value)
          }.height(52).width('100%')
          Row() {
            Text('显示质量监测').fontSize(16).fontColor('#F3F3F5').layoutWeight(1)
            Checkbox({ name: 'qualityMonitor', group: 'displayPanel' }).select(this.showQualityMonitor)
              .selectedColor('#0A7BF5').onChange((value: boolean) => this.showQualityMonitor = value)
          }.height(52).width('100%')
          Row() {
            Text('鼠标滚轮反向').fontSize(16).fontColor('#F3F3F5').layoutWeight(1)
            Checkbox({ name: 'reverseWheel', group: 'displayPanel' }).select(this.reverseWheel)
              .selectedColor('#0A7BF5').onChange((value: boolean) => this.reverseWheel = value)
          }.height(52).width('100%')
        }.width('100%')
      }.layoutWeight(1).width('100%')
      Button('完成').width('100%').height(42).backgroundColor('#0A7BF5')
        .onClick(() => this.sessionPanel = 'none')
    }
    .width(this.layoutMode() === LayoutMode.Compact ? '82%' : 500)
    .height('88%').padding(22).borderRadius(22).backgroundColor('#FA18191E')
    .position({ x: this.layoutMode() === LayoutMode.Compact ? '9%' : (this.sessionAreaWidth - 500) / 2, y: '6%' })
    .zIndex(5).onTouch((event: TouchEvent) => event.stopPropagation())
  }

  @Builder
  private SessionMorePanel() {
    Column() {
      Button('发送剪贴板内容').width('100%').height(48).fontColor(SURFACE).backgroundColor('#00000000')
        .onClick(() => { this.sessionPanel = 'none'; this.openClipboardComposer(); })
      Button('重置画布').width('100%').height(48).fontColor(SURFACE).backgroundColor('#00000000')
        .onClick(() => this.resetSessionCanvas())
      Button('锁定远程电脑').width('100%').height(48).fontColor(SURFACE).backgroundColor('#00000000')
        .onClick(() => { this.core.sendKey(101, true); this.sessionPanel = 'none'; })
      Button('刷新画面').width('100%').height(48).fontColor(SURFACE).backgroundColor('#00000000')
        .onClick(() => { this.core.refreshVideo(); this.sessionPanel = 'none'; })
    }
    .width(270).padding(14).borderRadius(15).backgroundColor('#F526272D')
    .position({ x: Math.max(12, this.sessionAreaWidth - 286), y: Math.max(10, this.sessionAreaHeight - 330) })
    .zIndex(5).onTouch((event: TouchEvent) => event.stopPropagation())
  }

  @Builder
  private SessionChatPanel() {
    Column() {
      Row() {
        Text('聊天消息').fontSize(18).fontWeight(FontWeight.Medium).fontColor(SURFACE).layoutWeight(1)
        Button('×').width(40).height(40).fontSize(22).backgroundColor('#00000000')
          .onClick(() => this.sessionPanel = 'none')
      }.width('100%').height(52).padding({ left: 14, right: 4 }).backgroundColor('#2497ED')
      List({ space: 8 }) {
        ForEach(this.chatMessages, (message: string) => {
          ListItem() {
            Text(message).width('100%').padding(10).fontSize(14).fontColor('#ECEEF4')
              .borderRadius(10).backgroundColor(message.startsWith('我：') ? '#354D70' : '#303138')
          }
        })
      }.layoutWeight(1).width('100%').padding(12)
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入聊天消息', text: this.chatText })
          .layoutWeight(1).height(44).fontColor(SURFACE).placeholderColor('#8C8E95')
          .backgroundColor('#27282E').border({ width: 2, color: '#2497ED' }).borderRadius(12)
          .onChange((value: string) => this.chatText = value).onSubmit(() => this.sendChatMessage())
        Button('发送').width(62).height(44).backgroundColor('#2497ED').onClick(() => this.sendChatMessage())
      }.width('100%').padding(10)
    }
    .width(this.layoutMode() === LayoutMode.Compact ? '86%' : 520).height('70%')
    .border({ width: 1, color: '#A5A7AD' }).backgroundColor('#FA18191E')
    .position({ x: this.layoutMode() === LayoutMode.Compact ? '7%' : (this.sessionAreaWidth - 520) / 2, y: '8%' })
    .zIndex(5).onTouch((event: TouchEvent) => event.stopPropagation())
  }

  @Builder
  private VirtualMousePanel() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Text('拖动任意位置移动').fontSize(10).fontColor('#F1F3F7')
          Blank()
          Text('×').fontSize(22).fontColor(SURFACE).width(34).textAlign(TextAlign.Center)
        }
        .width('100%').height(38).padding({ left: 12 })
        .borderRadius({ topLeft: 22, topRight: 22, bottomLeft: 6, bottomRight: 6 })
        .backgroundColor('#99646A75')
        Row() {
          Column() {
            Text('左键').fontSize(13).fontWeight(FontWeight.Medium).fontColor(SURFACE)
          }
          .height(82).layoutWeight(1).justifyContent(FlexAlign.Center)
          .borderRadius({ topLeft: 58, topRight: 5, bottomLeft: 5, bottomRight: 5 })
          .backgroundColor(this.virtualLeftHeld ? '#CC2196F3' : '#99898C92')
          Column({ space: 1 }) {
            Text('▲').fontSize(12).fontColor(SURFACE).height(27)
            Text('●').fontSize(11).fontColor(SURFACE).height(27)
            Text('▼').fontSize(12).fontColor(SURFACE).height(27)
          }
          .width(46).height(82).alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
          .backgroundColor('#A8666970')
          Column() {
            Text('右键').fontSize(13).fontWeight(FontWeight.Medium).fontColor(SURFACE)
          }
          .height(82).layoutWeight(1).justifyContent(FlexAlign.Center)
          .borderRadius({ topLeft: 5, topRight: 58, bottomLeft: 5, bottomRight: 5 })
          .backgroundColor(this.virtualRightHeld ? '#CC2196F3' : '#99898C92')
        }.width('100%').height(82)
        Column({ space: 7 }) {
          Text('移动鼠标').fontSize(13).fontWeight(FontWeight.Medium).fontColor(SURFACE)
          Text('轻点按键 · 长按后拖拽').fontSize(10).fontColor('#E0E3E8')
          Text('•••').fontSize(22).fontColor('#F0F1F4')
        }
        .width('100%').height(108).justifyContent(FlexAlign.Center)
        .borderRadius({ topLeft: 5, topRight: 5, bottomLeft: 58, bottomRight: 58 })
        .backgroundColor('#997B7E85')
      }
      .width(184).height(228)
      .opacity(0.76)
      .hitTestBehavior(HitTestMode.None)
    }
    .width(196).height(232).padding(6).borderRadius(26).backgroundColor('#44181D26')
    .position({ x: this.virtualMouseAnchorX(), y: this.virtualMouseAnchorY() })
    .zIndex(5)
    .onTouch((event: TouchEvent) => this.virtualMouseTouch(event))
  }

  @Builder
  private SessionPage() {
    Column() {
      if (this.sessionKeysExpanded) {
        this.SessionFunctionKeys()
      }
      Stack({ alignContent: Alignment.Center }) {
        XComponent({
          id: `rustdesk_remote_surface_${this.videoSurfaceGeneration}`,
          type: XComponentType.SURFACE,
          controller: this.videoSurfaceController
        })
          .width(this.videoRenderWidth())
          .height(this.videoRenderHeight())
          .translate({ x: this.canvasOffsetX, y: this.canvasOffsetY })
          .onLoad(() => {
            const surfaceId = this.videoSurfaceController.getXComponentSurfaceId();
            this.lastVideoSurfaceId = surfaceId;
            this.core.setVideoSurface(surfaceId);
            this.core.refreshVideo();
          })
        if (this.showRemoteCursor && this.remoteCursorVisible && this.remoteCursorPixelMap !== undefined) {
          Image(this.remoteCursorPixelMap)
            .width(this.remoteCursorWidth * this.sessionCursorSize)
            .height(this.remoteCursorHeight * this.sessionCursorSize)
            .objectFit(ImageFit.Fill).interpolation(ImageInterpolation.None)
            .draggable(false)
            .position({
              x: this.videoOffsetX() + this.remoteCursorX * this.videoRenderWidth() -
                this.remoteCursorHotX * this.sessionCursorSize,
              y: this.videoOffsetY() + this.remoteCursorY * this.videoRenderHeight() -
                this.remoteCursorHotY * this.sessionCursorSize
            })
            .zIndex(1)
            .hitTestBehavior(HitTestMode.None)
        }
        if (this.showQualityMonitor) {
          Column({ space: 3 }) {
            Row() {
              Text('实时质量').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#F4F7FC')
              Blank()
              Text(`${this.qualityFps} FPS`).fontSize(12).fontWeight(FontWeight.Bold).fontColor(GREEN)
            }.width('100%')
            Text(`${this.qualityVideoWidth} × ${this.qualityVideoHeight}  ·  ${this.qualityFrames} 帧`)
              .width('100%').fontSize(11).fontColor('#CDD6E7')
            Text(this.qualityDecoder)
              .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontSize(10).fontColor('#AAB6CB')
          }
          .width(190).padding(10).borderRadius(12).backgroundColor('#D91A2232')
          .position({ x: Math.max(8, this.sessionAreaWidth - 198), y: 10 })
          .zIndex(1)
          .hitTestBehavior(HitTestMode.None)
        }
        if (this.connectionState !== ConnectionState.Connected) {
          Column({ space: 14 }) {
            this.Icon($r('sys.symbol.computer'), 64, '#8EA3E8')
            Text(this.statusMessage)
              .fontSize(17).fontColor('#E8ECF5')
            LoadingProgress().width(28).height(28).color('#8EA3E8')
          }.alignItems(HorizontalAlign.Center)
        }
        if (this.showVirtualMouse && this.connectionState === ConnectionState.Connected) {
          this.VirtualMousePanel()
        }
        if (this.showKeyboard && this.clipboardComposeMode) {
          Row({ space: 7 }) {
            TextInput({
              placeholder: '长按此处，粘贴剪贴板文本',
              text: this.keyboardText
            })
              .layoutWeight(1).height(44).fontSize(15)
              .backgroundColor(SURFACE).borderRadius(10)
              .id('sessionClipboardInput')
              .onChange((value: string) => this.keyboardText = value)
              .onSubmit(() => this.submitKeyboardText(false))
            Button('发到剪贴板')
              .width(90).height(44).fontSize(13).backgroundColor(BLUE)
              .onClick(() => this.submitKeyboardText(false))
          }
          .width('94%').padding(7).borderRadius(14).backgroundColor('#DD1A2232')
          .position({ x: '3%', y: Math.max(8, this.sessionAreaHeight - 64) })
          .zIndex(6)
          .onTouch((event: TouchEvent) => event.stopPropagation())
        }
        if (this.showKeyboard && !this.clipboardComposeMode) {
          TextInput({ text: this.keyboardText })
            .id('sessionKeyboardInput')
            .width(1).height(1)
            .fontSize(1).fontColor('#00000000').caretColor('#00000000')
            .backgroundColor('#00000000').borderWidth(0).opacity(0.01)
            .position({ x: 1, y: Math.max(1, this.sessionAreaHeight - 2) })
            .zIndex(6)
            .selectionMenuHidden(true)
            .enableKeyboardOnFocus(true)
            .onChange((value: string) => this.handleDirectKeyboardChange(value))
            .onDidDelete((info: DeleteValue) => this.handleDirectKeyboardDelete(info))
            .onSubmit(() => this.handleDirectKeyboardSubmit())
        }
        if (this.sessionPanel !== 'none') {
          Column() {}
            .width('100%').height('100%').backgroundColor('#26000000').zIndex(3)
            .onClick(() => this.sessionPanel = 'none')
            .onTouch((event: TouchEvent) => event.stopPropagation())
        }
        if (this.sessionPanel === 'input') {
          this.SessionInputSheet()
        } else if (this.sessionPanel === 'display') {
          this.SessionDisplayPanel()
        } else if (this.sessionPanel === 'more') {
          this.SessionMorePanel()
        } else if (this.sessionPanel === 'chat') {
          this.SessionChatPanel()
        }
      }
      .layoutWeight(1).width('100%').backgroundColor('#121926').clip(true)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width);
        const height = Number(newArea.height);
        this.sessionAreaWidth = Math.max(1, width);
        this.sessionAreaHeight = Math.max(1, height);
        this.clampCanvasOffset();
        if (this.virtualMousePositioned) {
          this.virtualMouseX = Math.max(6, Math.min(this.sessionAreaWidth - 196, this.virtualMouseX));
          this.virtualMouseY = Math.max(6, Math.min(this.sessionAreaHeight - 232, this.virtualMouseY));
        }
        this.updateVideoViewport();
        if (this.lastPointerX === 0 && this.lastPointerY === 0) {
          this.lastPointerX = this.videoRenderWidth() / 2;
          this.lastPointerY = this.videoRenderHeight() / 2;
        }
      })
      .onTouch((event: TouchEvent) => {
        if (this.suppressSingleTouch && this.twoFingerScroll &&
          (event.type === TouchType.Up || event.type === TouchType.Cancel)) {
          if (event.type === TouchType.Up && !this.twoFingerMoved && !this.pinchActive) {
            this.core.sendPointer(this.twoFingerCenterX, this.twoFingerCenterY, 17);
            this.core.sendPointer(this.twoFingerCenterX, this.twoFingerCenterY, 18);
          }
          this.twoFingerScroll = false;
          this.twoFingerMoved = false;
          this.pinchActive = false;
          this.pinchStartDistance = 0;
          if (event.touches.length === 0) this.suppressSingleTouch = false;
          return;
        }
        if (event.touches.length >= 2) {
          if (!this.suppressSingleTouch) {
            this.suppressSingleTouch = true;
            if (this.touchDragging) {
              this.core.sendPointer(this.touchStartX, this.touchStartY, 10);
              this.touchDragging = false;
            }
          }
          const viewCenterX = (event.touches[0].x + event.touches[1].x) / 2;
          const viewCenterY = (event.touches[0].y + event.touches[1].y) / 2;
          const centerX = this.videoPointerX(viewCenterX);
          const centerY = this.videoPointerY(viewCenterY);
          const fingerDeltaX = event.touches[0].x - event.touches[1].x;
          const fingerDeltaY = event.touches[0].y - event.touches[1].y;
          const fingerDistance = Math.sqrt(fingerDeltaX * fingerDeltaX + fingerDeltaY * fingerDeltaY);
          this.twoFingerCenterX = centerX;
          this.twoFingerCenterY = centerY;
          if (!this.twoFingerScroll || event.type === TouchType.Down) {
            this.twoFingerScroll = true;
            this.twoFingerMoved = false;
            this.pinchActive = false;
            this.pinchStartDistance = Math.max(1, fingerDistance);
            this.pinchStartZoom = this.canvasZoom;
            this.twoFingerLastViewX = viewCenterX;
            this.twoFingerLastViewY = viewCenterY;
            this.twoFingerStartX = centerX;
            this.twoFingerStartY = centerY;
            this.lastScrollY = centerY;
          } else if (event.type === TouchType.Move) {
            if (!this.pinchActive && Math.abs(fingerDistance - this.pinchStartDistance) >= 12) {
              this.pinchActive = true;
              this.twoFingerMoved = true;
            }
            if (this.pinchActive) {
              const nextZoom = Math.max(1, Math.min(4,
                this.pinchStartZoom * fingerDistance / this.pinchStartDistance));
              const panDeltaX = viewCenterX - this.twoFingerLastViewX;
              const panDeltaY = viewCenterY - this.twoFingerLastViewY;
              if (Math.abs(nextZoom - this.canvasZoom) >= 0.005) {
                this.canvasZoom = nextZoom;
                this.sessionScaleMode = nextZoom <= 1.001 ? 'fit' : 'custom';
                if (nextZoom <= 1.001) {
                  this.canvasOffsetX = 0;
                  this.canvasOffsetY = 0;
                } else {
                  this.clampCanvasOffset();
                }
                this.updateVideoViewport();
              }
              if (nextZoom > 1.001 && Math.abs(panDeltaX) + Math.abs(panDeltaY) >= 1) {
                this.panCanvas(panDeltaX, panDeltaY);
              }
              this.twoFingerLastViewX = viewCenterX;
              this.twoFingerLastViewY = viewCenterY;
              return;
            }
            if (this.canvasZoom > 1.001 && this.sessionScaleMode === 'custom') {
              const panDeltaX = viewCenterX - this.twoFingerLastViewX;
              const panDeltaY = viewCenterY - this.twoFingerLastViewY;
              if (Math.abs(panDeltaX) + Math.abs(panDeltaY) >= 1) {
                this.twoFingerMoved = true;
                this.panCanvas(panDeltaX, panDeltaY);
                this.twoFingerLastViewX = viewCenterX;
                this.twoFingerLastViewY = viewCenterY;
              }
              return;
            }
            const deltaY = centerY - this.lastScrollY;
            if (!this.twoFingerMoved) {
              const totalX = centerX - this.twoFingerStartX;
              const totalY = centerY - this.twoFingerStartY;
              this.twoFingerMoved = totalX * totalX + totalY * totalY >= 256;
            }
            if (this.twoFingerMoved && Math.abs(deltaY) >= 1) {
              this.core.sendPointer(0, deltaY * 3, 4);
              this.lastScrollY = centerY;
            }
          }
          return;
        }
        if (this.suppressSingleTouch) {
          this.twoFingerScroll = false;
          this.twoFingerMoved = false;
          if ((event.type === TouchType.Up || event.type === TouchType.Cancel) && event.touches.length === 0) {
            this.suppressSingleTouch = false;
            return;
          } else if (event.type === TouchType.Down && event.touches.length === 1) {
            this.suppressSingleTouch = false;
          } else {
            return;
          }
        }
        if (this.twoFingerScroll) {
          this.twoFingerScroll = false;
          return;
        }
        const points = event.changedTouches.length > 0 ? event.changedTouches : event.touches;
        if (points.length === 0 || this.connectionState !== ConnectionState.Connected) return;
        const point = points[0];
        if (this.sessionInputMode === 'mouse') {
          if (event.type === TouchType.Down) {
            this.mouseModeLastX = point.x;
            this.mouseModeLastY = point.y;
            this.mouseModeMoved = false;
          } else if (event.type === TouchType.Move) {
            const deltaX = point.x - this.mouseModeLastX;
            const deltaY = point.y - this.mouseModeLastY;
            if (deltaX * deltaX + deltaY * deltaY >= 1) {
              this.mouseModeMoved = true;
              this.moveVirtualPointer(deltaX * 1.45, deltaY * 1.45);
              this.mouseModeLastX = point.x;
              this.mouseModeLastY = point.y;
            }
          } else if (event.type === TouchType.Up) {
            if (!this.mouseModeMoved) this.sendMouseClick(1);
            this.mouseModeMoved = false;
          } else if (event.type === TouchType.Cancel) {
            this.mouseModeMoved = false;
          }
          return;
        }
        const pointX = this.videoPointerX(point.x);
        const pointY = this.videoPointerY(point.y);
        if (event.type === TouchType.Down) {
          this.touchStartX = pointX;
          this.touchStartY = pointY;
          this.lastPointerX = pointX;
          this.lastPointerY = pointY;
          this.touchDragging = false;
          this.updateLocalRemoteCursor(pointX, pointY);
          this.core.sendPointer(pointX, pointY, 0);
        } else if (event.type === TouchType.Move) {
          const deltaX = pointX - this.touchStartX;
          const deltaY = pointY - this.touchStartY;
          if (!this.touchDragging && deltaX * deltaX + deltaY * deltaY >= 100) {
            this.touchDragging = true;
            this.core.sendPointer(this.touchStartX, this.touchStartY, 9);
          }
          if (this.touchDragging) {
            this.lastPointerX = pointX;
            this.lastPointerY = pointY;
            this.updateLocalRemoteCursor(pointX, pointY);
            this.core.sendPointer(pointX, pointY, 8);
          }
        } else if (event.type === TouchType.Up) {
          this.lastPointerX = pointX;
          this.lastPointerY = pointY;
          this.updateLocalRemoteCursor(pointX, pointY);
          if (this.touchDragging) {
            this.core.sendPointer(pointX, pointY, 10);
          } else {
            this.core.sendPointer(pointX, pointY, 9);
            this.core.sendPointer(pointX, pointY, 10);
          }
          this.touchDragging = false;
        } else if (event.type === TouchType.Cancel) {
          if (this.touchDragging) this.core.sendPointer(pointX, pointY, 10);
          this.touchDragging = false;
        }
      })
      this.SessionBottomToolbar()
    }.width('100%').height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.currentPage === 'session') {
        this.SessionPage()
      } else if (this.currentPage === 'display') {
        this.DisplaySettingsContent()
      } else if (this.currentPage === 'privacy') {
        this.PrivacyPolicyContent()
      } else if (this.currentPage === 'licenses') {
        this.LicensesContent()
      } else if (this.currentPage === 'settings') {
        this.SettingsContent()
      } else {
        this.ConnectContent()
      }

      if (this.showPrivacyDialog || this.showServerDialog || this.showLoginDialog || this.showDeviceMenu ||
        this.showConnectionDialog) {
        Column() {}
          .width('100%').height('100%').backgroundColor('#5C000000')
          .onClick(() => {
            if (this.showPrivacyDialog) return;
            this.showServerDialog = false;
            this.showLoginDialog = false;
            this.showDeviceMenu = false;
            this.showConnectionDialog = false;
            this.password = '';
          })
        if (this.showPrivacyDialog) {
          this.PrivacyConsentDialog()
        } else if (this.showServerDialog) {
          this.ServerDialog()
        } else if (this.showLoginDialog) {
          this.LoginDialog()
        } else if (this.showConnectionDialog) {
          this.ConnectionDialog()
        } else {
          this.DeviceMenu()
        }
      }
    }
    .width('100%').height('100%').backgroundColor(BACKGROUND)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.viewportWidth = Number(newValue.width);
    })
  }
}
