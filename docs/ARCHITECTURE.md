# Architecture

## Layers

1. **ArkUI shell** — responsive navigation, device list, connection form, session toolbar and input surfaces.
2. **ArkTS `RemoteCore` contract** — stable application-facing session API. `RendezvousRemoteCore` implements hbbs lookup, hbbr relay establishment, peer handshake and encrypted login; it never fabricates a connected state.
3. **Native bridge** — the N-API/C++ crypto adapter owns private session keys and exposes only verification, handshake material, packet transforms and password hashing.
4. **Rust core** — rendezvous, relay/direct transport, crypto, peer protocol, decode queues and input encoding.
5. **Harmony adapters** — AVCodec/NativeWindow rendering, pasteboard, files, keyboard, mouse, touch and pen input.

## Server Pro

`ServerProfile` carries the exact client-side routing inputs used by RustDesk Server Pro: ID server, optional relay, API server, server public key and WebSocket preference. Public configuration is stored through Harmony Preferences; login passwords are transient and access tokens remain in memory.

`ServerProApi` implements account authentication against `/api/login`. Address book, accessible-device and policy synchronization will reuse its bearer token after their response models are confirmed against a live licensed Server Pro instance. The rendezvous/relay path is separate from the HTTP API and is live through encrypted peer login.

## Device strategy

The application uses window width rather than a hard-coded product name:

- `< 600 vp`: compact phone/folded layout and touch-first session controls.
- `600–959 vp`: tablet/unfolded layout with list and detail panes.
- `>= 960 vp`: PC/large-window layout with a navigation rail, three-pane home and session inspector.

The same UI therefore reacts correctly to folding, rotation, split screen and PC window resizing without restarting the session.

## Protocol integration seam

The upstream RustDesk code must be reviewed and integrated as source under AGPL-3.0-or-later. It should sit behind an internal Rust trait and must not leak upstream types through the C ABI. This isolates ArkTS from upstream refactors and permits deterministic ABI tests.

Transport milestones are intentionally narrow:

1. Self-hosted hbbs TCP connection, RustDesk framing, ID lookup and failure parsing — implemented.
2. Server and peer Signed-ID validation, hbbr relay, peer key exchange and encrypted login request — implemented, awaiting live-device compatibility testing.
3. Login-response state and direct-to-Surface HarmonyOS hardware video decode — implemented, awaiting live-device compatibility testing.
4. Touch pointer packets and input-coordinate mapping — implemented, awaiting live-device interaction testing.
5. UTF-8 keyboard sequences, Backspace/Return and two-finger trackpad scrolling — implemented, awaiting live-device interaction testing.
6. Full physical-key mapping and multi-monitor transforms — pending.
4. File transfer, address books and account policy features — only after the interactive session is stable.
