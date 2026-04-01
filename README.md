# GlucoPilot

**Real-time Dexcom CGM glucose readings in your macOS menu bar.**

GlucoPilot is a lightweight macOS menu bar app for people with Type 1 diabetes who want always-visible access to their blood sugar. It pulls live glucose data from the Dexcom Share API and displays the current value and trend directly in the menu bar — no need to reach for your phone or open the Dexcom app.

## Features

- **Menu bar display** — live glucose value + trend arrow (e.g., `135 ↗`)
- **Color-coded status** — red (low, <70 mg/dL), yellow (high, >180 mg/dL), green (in range)
- **Glucose history chart** — interactive chart with 1H, 3H, 6H, and 12H views with target zone overlay (70–180 mg/dL)
- **30-second auto-refresh** with stale reading detection
- **Multi-region support** — Dexcom Share US, US1, Outside US, and Japan endpoints
- **Nightscout remote bolus** — deliver insulin boluses via Nightscout with TOTP authentication
- **Privacy mode** — hide the glucose value and show only the trend arrow
- **Secure storage** — all credentials stored in macOS Keychain; nothing written to disk in plaintext

## Tech Stack

Swift 5 · SwiftUI · AppKit · Swift Charts · Swift Concurrency (actors) · macOS Keychain · TOTP/HMAC-SHA1

**Requires:** macOS 13.0+, Xcode 15+

## Setup

### Dexcom Share

1. Open the Dexcom app on your phone and enable **Share** under Settings.
2. Create a **follower account** (a separate Dexcom account that follows the primary account). GlucoPilot authenticates as the follower.
3. Launch GlucoPilot, open **Settings**, and enter the follower account username and password.
4. Select the correct **region** for your Dexcom account.

### Nightscout (optional)

To enable remote bolus delivery through Loop:

1. In Settings, enter your **Nightscout URL** and **API secret**.
2. Configure a **TOTP secret** (shared with your Nightscout instance) for two-factor authentication on bolus commands.

## Build

```bash
git clone https://github.com/casey-dunham/GlucoPilot.git
cd GlucoPilot
open DexcomMenuBar.xcodeproj
```

Build and run from Xcode (⌘R). The app runs as a menu bar agent — no Dock icon or main window.

## Security

All credentials (Dexcom username/password, Nightscout API secret, TOTP secret) are stored exclusively in the macOS Keychain. No sensitive data is written to preferences files, plists, or disk.

## License

MIT
