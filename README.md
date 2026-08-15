# RustDesk Harmony

[简体中文](#简体中文) · [English](#english)

面向 HarmonyOS 6 的原生 RustDesk 控制端，支持手机、折叠屏、平板和 PC/二合一设备。

Native HarmonyOS 6 RustDesk controller for phones, foldables, tablets, and PC/2-in-1 devices.

---

## 简体中文

### 项目简介

RustDesk Harmony 是一个可运行的 HarmonyOS 原生远程桌面控制端，已接入真实 RustDesk 加密协议、Server Pro、自建服务器、硬件视频解码和远程输入控制。它是兼容 RustDesk 协议的独立第三方客户端，并非 RustDesk 官方产品。

### 当前能力

- HarmonyOS 6.0.0 / API 20 Stage 模型工程。
- 支持 `phone`、`tablet` 和 `2in1`，并适配手机、折叠屏、平板及 PC 响应式布局。
- 通过真实 `hbbs`/`hbbr` TCP 连接完成设备发现、打洞、中继和加密会话。
- 支持 Server Pro 的 ID Server、中继服务器、API Server、公钥、WebSocket 和账户登录。
- 支持远端连接密码认证及远端手动授权，成功连接的主机可保存到最近列表。
- 用户选择保存的远控密码仅存放于 HarmonyOS Asset Store。
- 支持 VP8、VP9、H.264 和 H.265，并通过 HarmonyOS `VideoDecoder` 与 ArkUI `XComponent` Surface 渲染。
- 支持点击、拖动、双指滚动、双指右键、双指缩放及放大后的画布移动。
- 支持远端真实光标、悬浮虚拟鼠标和边缘画布跟随。
- 支持鼠标/触控模式、快捷键栏、Ctrl+Alt+Delete、Esc 和 Tab 等控制操作。
- 手机输入法通过 UTF-8 文本序列直接向远端输入，支持退格和回车。
- 支持双向文本剪贴板和聊天，不申请受限的 `READ_PASTEBOARD` 权限。
- 支持应用前后台切换后的 Surface、硬件解码器和远端画面恢复。

### 安全与隐私

- 远端密码不会写入 HarmonyOS Preferences，也不会显示在设备列表中。
- Server Pro 登录密码不持久化，访问令牌仅保存在内存中。
- 会话密钥保留在原生模块内，并在连接关闭时清除。
- 首次使用网络功能前展示隐私说明；可部署的隐私政策位于 `release-assets/privacy-policy.html`。
- Git 仓库不包含证书、签名口令、HAP/APP 安装包或本机 SDK 路径。

### Server Pro 配置

在应用“设置”中填写：

- **ID Server**：`hbbs` 域名或 IP，可带 `21116` 端口，不填写协议头。
- **中继服务器**：可选的 `hbbr` 地址，通常由 ID Server 自动返回。
- **API Server**：用于 Server Pro 登录及设备列表的 `https://` 或 `http://` 地址。
- **Key**：`id_ed25519.pub` 或 Pro 控制台中的服务器公钥，不是 Pro 授权码。
- **WebSocket**：仅在反向代理已配置对应 WebSocket 路由时启用。

应用支持 HTTPS 和 HTTP，不会强制把 HTTP 改写为 HTTPS。HTTP 不提供传输层机密性，只应在可信隔离网络中使用。

### 在 DevEco Studio 中运行

1. 使用 DevEco Studio 6.1 或更高版本打开工程。
2. 安装 HarmonyOS 6.0.0（API 20）或更高版本 SDK。
3. 等待 DevEco 完成 Hvigor 依赖同步。
4. 在“项目结构 → 签名配置”中配置自己的调试或发布证书。
5. 选择 `entry` 模块、`default` Product 和目标设备后运行。

仓库中的 `build-profile.json5` 不包含签名秘密，因此默认生成无签名 HAP；真机安装前需要在本机 DevEco Studio 中配置签名。

### 已验证状态

已通过 Profile 合并、SysCap 检查、资源编译、ArkTS 编译、CMake/Ninja 原生构建、JavaScript 构建、HAP 打包和本机调试签名。ARM64 真机功能已验证；模拟器和 HarmonyOS PC 的 x86_64 原生输出仍需继续完善。

核心代码与固定依赖：

- ArkTS 协议入口：`entry/src/main/ets/services/RemoteCore.ets`
- 原生加密与视频模块：`entry/src/main/cpp/remote_crypto.cpp`
- RustDesk 1.4.7：`third_party/rustdesk-upstream`
- 对应 `hbb_common` 提交：`df6badca5bf81b4e9836256cf8e31c993ad70dd1`
- libsodium 1.0.20：`third_party/libsodium`
- Zstandard 1.5.7：`third_party/zstd`

### 许可证与商标

本项目包含或派生自 RustDesk 协议相关代码，因此以 AGPL-3.0-or-later 发布。详情请参阅 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`。发布 HAP 时应同时提供与版本对应的完整源代码。

RustDesk Harmony 是兼容 RustDesk 协议的独立第三方客户端，不是 RustDesk 官方产品。RustDesk 名称及商标归其权利人所有。闭源商业发布前应另行完成许可证和商标审查。

---

## English

## Current milestone

This repository contains a runnable HarmonyOS controller with real encrypted RustDesk protocol, video rendering and interactive input integration.

- HarmonyOS 6.0.0 / API 20 stage-model project.
- `phone`, `tablet` and `2in1` deployment targets.
- Responsive compact, medium and expanded layouts.
- iOS RustDesk-inspired native UI: blue app bar, remote-ID entry, device-mode tabs, favorite device cards and two-item bottom navigation.
- Grouped settings, display preferences, Server Pro modal and account login modal using Harmony system symbols and native controls.
- Phone layouts closely follow the supplied iOS reference while foldable, tablet and PC/2-in-1 layouts expand into a two-column workspace.
- Device list, ID connection form, session lifecycle UI and touch/desktop control surfaces.
- Per-session connection dialog with encrypted-password login or explicit passwordless remote approval. Password persistence is user-controlled; remembered passwords are stored only in HarmonyOS Asset Store.
- Persisted RustDesk Server Pro profiles with ID, relay, API, public key and WebSocket options.
- Real Server Pro account authentication request through `POST <API Server>/api/login`.
- ArkTS `RemoteCore` backed by real hbbs/hbbr TCP connections and RustDesk framing.
- ARM64 N-API crypto module linked against pinned libsodium 1.0.20 source.

The Server Pro login button performs a real HTTPS/HTTP API request. The password is never persisted and the returned access token is kept only in memory.

Both HTTPS and HTTP endpoints are supported, and HTTP is not rewritten to HTTPS. The warning-labelled trusted-LAN option must be enabled before HTTP login. HTTP must not be used on public networks.

Successfully connected remote hosts are kept in the recent-host list. Their IDs and display metadata use Harmony Preferences, while reusable connection passwords are stored separately in HarmonyOS Asset Store with unlocked-device accessibility; passwords are never written to Preferences or rendered in the device list.

The first run presents a privacy notice before network features are used. The complete in-app policy describes Server Pro login, remote IDs, local discovery, clipboard/chat transfer and retained credentials. A deployable policy page is provided at `release-assets/privacy-policy.html`.

The controller opens a real TCP connection to `hbbs`, sends the RustDesk 1.4.7 `PunchHoleRequest`, validates the Server Pro-signed peer identity, requests an `hbbr` relay, validates the peer's second signed identity, and performs the Curve25519/XSalsa20-Poly1305 session-key handshake. It decrypts the peer password challenge and sends the matching double-SHA-256 encrypted login request. Secret session keys stay inside the native module and are wiped when the session closes.

The controller parses RustDesk VP8, VP9, H.264 and H.265 frame groups, feeds encoded frames to the HarmonyOS system `VideoDecoder`, and renders decoded output directly to an ArkUI `XComponent` Surface. H.264 is preferred during codec negotiation for broad hardware compatibility, with the other codecs retained as fallbacks. Live-device H.265 rendering has been verified. Tap, thresholded drag, two-finger trackpad scrolling and two-finger-tap right click are mapped to encrypted RustDesk mouse events with remote-resolution coordinate conversion. Multi-touch remains locked until every finger is released so the end of a scroll cannot leak into a left click. RustDesk `CursorData`, `CursorId` and `CursorPosition` messages are decoded into cached HarmonyOS RGBA PixelMaps so the viewer uses the remote machine's actual cursor shape and hotspot. A movable floating virtual mouse adds relative pointer movement, press-and-hold left/right buttons, middle click, and discrete wheel scrolling without obscuring the session toolbar. The session control panel also exposes explicit left-click, double-click, right-click, Escape, Tab and Ctrl+Alt+Delete actions at the most recent pointer position. The session keyboard bar sends UTF-8 sequences plus Backspace and Return control keys. Text clipboard exchange is bidirectional without requesting the restricted `READ_PASTEBOARD` permission: local-to-remote transfer uses a user-paste text composer, while uncompressed legacy and multi-clipboard text received from the peer is written to the local pasteboard. Server `TestDelay` packets are echoed over the encrypted channel to maintain session liveness and video QoS.

When the application returns from the background, it releases the stale Surface, retries acquisition of the foreground XComponent Surface, recreates the hardware decoder, requests a RustDesk video refresh and waits for the new key frame before resuming rendering. The encrypted control session remains connected throughout this process.

Pinned protocol sources are stored under `third_party/rustdesk-upstream`: RustDesk `1.4.7` and its matching `hbb_common` commit `df6badca5bf81b4e9836256cf8e31c993ad70dd1`. Zstandard `1.5.7` is pinned under `third_party/zstd` and statically linked only for bounded remote-cursor RGBA decompression.

## Server Pro configuration

Open Settings and provide:

- **ID Server** — the `hbbs` host/IP, optionally with port `21116`, without a URL scheme.
- **Relay Server** — optional `hbbr` override; normally inferred by the ID server.
- **API Server** — an `https://` or `http://` URL used for Pro account login and, later, address books/policies.
- **Key** — the server public key from `id_ed25519.pub` or the Pro console, not the Pro license key.
- **WebSocket** — enable only when the reverse proxy exposes the Server Pro WebSocket routes.

Server endpoints and the public key are persisted in Harmony Preferences. Passwords and access tokens are not persisted.

The Server Pro configuration is available from **Settings → ID/Relay Server**. Account authentication is available from **Settings → Login** after the server endpoints and public key have been saved.

## Open in DevEco Studio

1. Open this directory in DevEco Studio 6.1 or newer.
2. Install the HarmonyOS 6.0.0 (API 20) or newer SDK when prompted.
3. Let DevEco synchronize Hvigor dependencies.
4. Configure your own debug or release certificate under **Project Structure → Signing Configs**.
5. Select the `entry` module, the `default` product and a phone, tablet or 2-in-1 device, then run the app.

The committed `build-profile.json5` contains no signing secrets, so command-line builds produce an unsigned HAP by default. Configure signing locally before installation on a physical device.

The project targets and remains compatible with HarmonyOS 6.0.0 (API 20). Its ArkTS, native ARM64 library, resources and signed debug HAP packaging were verified with the SDK bundled in DevEco Studio 6.1.

## Verified build

The following stages currently pass: profile merge, SysCap pre-check, resource compilation, ArkTS compilation, native CMake/Ninja build, JavaScript build, HAP packaging, validation and debug signing.

## Native crypto

`entry/src/main/cpp/remote_crypto.cpp` is built as an ARM64 N-API library. It verifies Ed25519 identities, creates Curve25519 session material, performs RustDesk secretbox packet encryption/decryption, calculates the password challenge, and owns the HarmonyOS hardware video decoder and render Surface. Session keys and decoded video buffers never need to cross into ArkTS. x86_64 native output is still required for emulator/PC coverage.

## Licensing

This distribution is licensed under AGPL-3.0-or-later because it contains or derives from upstream RustDesk protocol code. See `LICENSE` and `THIRD_PARTY_NOTICES.md`. Each published HAP must provide a public, version-pinned copy of the complete corresponding source. A closed-source commercial release requires a separate licensing and trademark review.

RustDesk Harmony is an independent third-party client compatible with the RustDesk protocol and is not an official RustDesk product. RustDesk names and trademarks belong to their respective owner.
