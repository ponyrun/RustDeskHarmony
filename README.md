# RustDesk Harmony

Native HarmonyOS 6 controller client targeting phone, foldable, tablet and PC/2-in-1 form factors.

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

HTTPS is the default. HTTP or an insecure TLS fallback is available only after the user explicitly enables the warning-labelled trusted-LAN option. It must not be used on public networks.

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
- **API Server** — an `https://` URL used for Pro account login and, later, address books/policies.
- **Key** — the server public key from `id_ed25519.pub` or the Pro console, not the Pro license key.
- **WebSocket** — enable only when the reverse proxy exposes the Server Pro WebSocket routes.

Server endpoints and the public key are persisted in Harmony Preferences. Passwords and access tokens are not persisted.

The Server Pro configuration is available from **Settings → ID/Relay Server**. Account authentication is available from **Settings → Login** after the server endpoints and public key have been saved.

## Open in DevEco Studio

1. Open this directory in DevEco Studio 6.1 or newer.
2. Install the HarmonyOS 6.0.0 (API 20) or newer SDK when prompted.
3. Let DevEco synchronize Hvigor dependencies.
4. Select the `entry` module and a phone, tablet or 2-in-1 emulator/device.
5. Run the `default` product.

The project targets and remains compatible with HarmonyOS 6.0.0 (API 20). Its ArkTS, native ARM64 library, resources and signed debug HAP packaging were verified with the SDK bundled in DevEco Studio 6.1.

## Verified build

The following stages currently pass: profile merge, SysCap pre-check, resource compilation, ArkTS compilation, native CMake/Ninja build, JavaScript build, HAP packaging, validation and debug signing.

## Native crypto

`entry/src/main/cpp/remote_crypto.cpp` is built as an ARM64 N-API library. It verifies Ed25519 identities, creates Curve25519 session material, performs RustDesk secretbox packet encryption/decryption, calculates the password challenge, and owns the HarmonyOS hardware video decoder and render Surface. Session keys and decoded video buffers never need to cross into ArkTS. x86_64 native output is still required for emulator/PC coverage.

## Licensing

This distribution is licensed under AGPL-3.0-or-later because it contains or derives from upstream RustDesk protocol code. See `LICENSE` and `THIRD_PARTY_NOTICES.md`. Each published HAP must provide a public, version-pinned copy of the complete corresponding source. A closed-source commercial release requires a separate licensing and trademark review.

RustDesk Harmony is an independent third-party client compatible with the RustDesk protocol and is not an official RustDesk product. RustDesk names and trademarks belong to their respective owner.
