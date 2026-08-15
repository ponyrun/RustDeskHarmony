**Design QA**

- source visual reference: iOS RustDesk bottom-toolbar screenshot supplied during design review
- implementation screenshot path: unavailable for the revised connected-session state — the HAP was installed successfully, but the HarmonyOS device is locked and rejects application launch in developer mode
- viewport: intended HarmonyOS phone portrait viewport; exact device viewport unavailable in this QA run
- state: connected remote desktop with the full-width blue bottom toolbar visible
- full-view comparison evidence: the supplied screenshot shows five white system symbols mixed with two text controls. The implementation replaces the input-mode and chat text controls with matching HarmonyOS system symbols, but the revised connected-session state could not be captured while the device remained locked
- focused region comparison evidence: blocked for shortcut density, bottom toolbar, input sheet, display dialog, more menu, and chat dialog because no revised device capture exists

**Findings**

- [P1] Revised native UI has not been visually verified on a device
  Location: remote session screen.
  Evidence: the signed HAP builds and installs successfully, but Ability Manager reports error `10106102` because the device screen is locked in developer mode.
  Impact: typography, density, safe-area placement, overlay sizing, and responsive behavior cannot be judged from source code alone.
  Fix: reconnect the HarmonyOS device, install the signed HAP, enter a remote session, capture the primary screen and each overlay, then compare them against the reference screenshots.

**Required fidelity surfaces**

- Fonts and typography: ArkUI sizes and weights were mapped to the source hierarchy; rendered font metrics remain unverified.
- Spacing and layout rhythm: structure and component dimensions were implemented; device safe-area and compact-height behavior remain unverified.
- Colors and visual tokens: near-black shortcut area, charcoal overlays, white labels, and RustDesk blue toolbar were mapped; rendered opacity remains unverified.
- Image quality and asset fidelity: the remote desktop remains the native decoded XComponent surface; standard HarmonyOS symbols are used for toolbar controls. No custom raster asset replacement was introduced.
- Copy and content: Chinese labels and option groups follow the supplied iOS screenshots, with HarmonyOS-specific wording for the floating virtual mouse.

**Implementation Checklist**

- Reconnect device and install `entry-default-signed.hap`.
- Capture connected session, input sheet, display settings, more menu, chat, and keyboard states.
- Fix any P0/P1/P2 visual mismatch and repeat comparison.

**Comparison history**

- Iteration 1: source visual opened; implementation rebuilt successfully; rendered comparison blocked because the connected device changed from online to offline before installation.
- Iteration 2: HAP installed successfully on device. Default app screen was captured, but the device left the session and disconnected while entering the saved remote host, so the required connected-session before/after capture remains unavailable.
- Iteration 3: text-only input-mode and chat toolbar controls were replaced with native line symbols and the HAP was installed. Visual comparison remains blocked because the device is locked and cannot launch the revised session UI.

**Open Questions**

- None in product scope; only the missing online device blocks visual validation.

**Follow-up Polish**

- Re-evaluate the compact-screen shortcut label sizes after a device capture.

final result: blocked
