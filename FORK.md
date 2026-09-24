# Meld Fork Documentation

This document tracks all modifications made to upstream [Kaset](https://github.com/sozercan/kaset) files to minimize merge surface and guide future upstream merges.

## Upstream Base
- **Upstream Repository**: `https://github.com/sozercan/kaset.git`
- **Initial Fork Commit**: Upstream `main` at time of Phase 0 initialization.

## Branching Model
- `main`: Pristine mirror of `sozercan/kaset`. Upstream merges land here. Nothing else ever does.
- `meld-main`: Long-lived integration branch, created off `phase-0`. All phase branches merge here. `main` merges INTO `meld-main` when pulling upstream, never the reverse.
- `phase-N`: Feature branches off `meld-main`, PR'd into `meld-main`.

### Branch Protection on `main`
- **Rules Enforced**: Require a pull request before merging, block force pushes, block deletions.
- **Purpose**: Enforces the pristine `main` policy at the platform level so a mis-targeted PR or direct push cannot alter `main` by accident.
- **Protocol**: If branch protection ever blocks merging upstream into `main`, report it to Ramiz rather than attempting any platform or Git workarounds.

## Modified Upstream Files

### Phase 0: Fork, Rename & Baseline
- `Package.swift`: Renamed package, targets, and products to Meld; updated resource paths to Meld.sdef.
- `Info.plist`: Replaced bundle identifier with `com.uncoolburrito.meld`, registered `meld://` scheme, set `Meld.sdef`. Intentionally omitted Sparkle auto-update feed keys (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, etc.) because this personal fork does not publish an auto-update appcast or hold upstream's Ed25519 signing key; attempting upstream auto-updates would fail signature verification or attempt to overwrite Meld with Kaset.
- `Meld.entitlements`: (Replaced `Kaset.entitlements`) Updated Sparkle Mach service lookup identifiers to `com.uncoolburrito.meld-spks` and `com.uncoolburrito.meld-spki`.
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

### App Icon: Custom Branding
- `Sources/Meld/Resources/Assets.xcassets/AppIcon.appiconset`: Added full 10-representation macOS AppIcon asset catalog (16x16 to 1024x1024) generated from custom Meld artwork. Uses full-bleed crop (700x700 centered at 512, 494) for 128x128 and larger, and tight crop (320x320 centered at 504, 525) for 16x16 and 32x32 slots to preserve legibility of the glowing note between fingertips.
- `Sources/Meld/Resources/AppIcon.icon`: Removed. Replaced with pure `AppIcon.appiconset` to enable slot-specific tuning (Icon Composer bundles apply a single uniform raster across all resolutions and cannot render distinct crops for small slots).
- `Scripts/build-app.sh`: Updated to compile `Assets.xcassets` directly with `actool` and improved `DEVELOPER_DIR` fallback to avoid overriding active Xcode selections on CI runners.

### CI & Workflows
- `.github/workflows/release.yml.disabled`: Renamed from `release.yml` and disabled. The upstream release pipeline publishes to `sozercan`'s Homebrew tap and Sparkle appcast with upstream signing identities, neither of which are ours. It will need a full rewrite before any public release, rather than a string rename.

## Public Release Constraints & Roadmap Decisions

These constraints are documented now to take the cheap path before release rather than expensive refactors afterward.

### 1. Immutable Bundle Identifier
- **Identifier**: `com.uncoolburrito.meld`
- **Rule**: Never change the bundle identifier. Application code signing, Sparkle update tracking, sandboxed Application Support containers, and user defaults are all permanently keyed off this identifier. Changing it post-release will orphan user data, logins, and cookies.

### 2. Spotify Client ID Architecture (Before Phase 4)
- **Constraint**: Spotify Developer Mode limits apps to 5 authenticated users and requires the application owner to hold Spotify Premium. Extended Quota Mode requires an approved organization.
- **Design Rule**: Design the Spotify client ID and client secret as user-supplied settings from day one in `SettingsManager` (with local developer default values). Retrofitting user-provided credentials post-release would require migration scripts, settings UI rewrites, and docs. Implementing it as a user-configurable preference in Phase 4 costs nothing up front.

### 3. Sparkle Auto-Update (Pre-Release Gate)
- **Constraint**: Shipping a public v1 without functional auto-update permanently strands initial users (adding update machinery in v2 only benefits users who manually install v2+).
- **Pre-Release Checklist**:
  1. Generate dedicated Ed25519 keypair for Meld.
  2. Stand up and host `appcast.xml` feed on a reliable domain/release asset.
  3. Re-enable Sparkle keys in `Info.plist`.
  4. Rewrite `.github/workflows/release.yml` to sign with the new key and publish to the appcast.

### 4. Themes & Customization Architecture (Phase 6 Roadmap & Prerequisites)
- **Planned Feature**: A theme picker in Settings. Apple Music's pink-red remains the default.
  - Static options (Light / Dark hex pairs):
    - **Ultramarine**: `#2F4B8C` (light) / `#3A5DA8` (dark)
    - **Vermilion**: `#C0392B` (light) / `#D4462A` (dark)
    - **Verdigris**: `#3E7A6B` (light) / `#4A8C7A` (dark)
    - **Gold**: `#A67C00` (light) / `#D4AF37` (dark)
  - **Dynamic Theme**: Accent rests at Gold, fades to Verdigris when `audioSource == .spotify`, and fades to Vermilion when `audioSource == .music` (slow ambient crossfade of 600–800ms).
  - *Note for Phase 6*: Dynamic theme keys off `audioSource`, which also shifts when external Spotify playback is detected (e.g. playing from speaker fades UI green even while viewing YouTube Music tab). Confirm exact cross-tab intent during Phase 6 sign-off.
- **Prerequisites Required Before Phase 6**:
  - **Phase 3 Injectable Tint**: Compiled asset catalog `AccentColor` cannot be swapped dynamically at runtime. When touching accent-coloured UI in Phase 3, route it through a single injectable tint environment value at the root view hierarchy rather than querying asset catalogs directly. Avoid adding new direct reads of `AccentColor` anywhere in the codebase.
  - **Explicit Light & Dark Pairs**: Every theme colour must be defined as an explicit Light and Dark pair (e.g. Gold on white is unreadable without a darkened light-mode variant).



