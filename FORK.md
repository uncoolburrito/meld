# Meld Fork Documentation

This document tracks all modifications made to upstream [Kaset](https://github.com/sozercan/kaset) files to minimize merge surface and guide future upstream merges.

## Upstream Base
- **Upstream Repository**: `https://github.com/sozercan/kaset.git`
- **Initial Fork Commit**: Upstream `main` at time of Phase 0 initialization.

## Branching Model
- `main`: Pristine mirror of `sozercan/kaset`. Upstream merges land here. Nothing else ever does.
- `meld-main`: Long-lived integration branch, created off `phase-0`. All phase branches merge here. `main` merges INTO `meld-main` when pulling upstream, never the reverse.
- `phase-N`: Feature branches off `meld-main`, PR'd into `meld-main`.

## Modified Upstream Files

### Phase 0: Fork, Rename & Baseline
- `Package.swift`: Renamed package, targets, and products to Meld; updated resource paths to Meld.sdef.
- `Info.plist`: Replaced bundle identifier with `com.uncoolburrito.meld`, registered `meld://` scheme, set `Meld.sdef`.
- `Meld.entitlements`: (Replaced `Kaset.entitlements`) Added Spotify scripting target entitlements for sandboxed AppleScript.
- `LICENSE`: Added copyright notice for Ramiz while preserving original sozercan copyright.
- `README.md`: Rebranded documentation and added attribution to upstream Kaset.
- `Sources/Meld/MeldApp.swift`: (Renamed from `KasetApp.swift`) Updated main app entry point struct and logging to Meld.
- `Sources/Meld/AppDelegate.swift`: Renamed notification identifier `.kasetOpenURLs` to `.meldOpenURLs`.
- `Sources/Meld/Resources/Meld.sdef`: (Replaced `Kaset.sdef`) Updated scripting suite and command identifiers to Meld.
- `Sources/Meld/Services/Scripting/ScriptCommands.swift`: Renamed AppleScript `@objc` command handler classes to Meld.
- `Sources/Meld/Services/URLHandler.swift`: Updated URL parsing to handle `meld://` scheme.
- `Sources/Meld/Services/WebKit/WebKitManager+Cookies.swift`: Updated Application Support cookie path from Kaset to Meld.
- `Sources/Meld/Utilities/DiagnosticsLogger.swift`: Updated logging subsystem to `com.uncoolburrito.meld`.
- `Sources/Meld/Services/Player/NowPlayingManager.swift`: Updated claim identifier to `com.uncoolburrito.meld`.
- `Sources/Meld/Services/Audio/ProcessTapHelper.swift`: Updated aggregate audio UID to `com.uncoolburrito.meld`.
- `Sources/Meld/Services/Scrobbling/KeychainCredentialStore.swift`: Updated default keychain prefix to `com.uncoolburrito.meld`.
- `Sources/APIExplorer/main.swift`: Updated cookie path and app references to Meld.
- `Scripts/build-app.sh`: Updated bundle naming, bundle ID, and resource packaging paths to Meld.
- `Scripts/compile_and_run.sh`: Updated app and process targets to Meld.
- `Scripts/benchmark-xctest.sh`: Updated test bundle targets to MeldTests.
- `Scripts/verify-release-app.sh`: Updated bundle ID check to `com.uncoolburrito.meld`.
- `Tests/MeldTests/*`: (Renamed from `Tests/KasetTests`) Updated test imports to `@testable import Meld`.
