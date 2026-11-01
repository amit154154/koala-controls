# Development

[← Overview](../README.md)

## Structure

```text
Sources/                 native Swift host and shared action engine
Resources/               koala art, sounds, AppleScripts and phone client
Resources/PhoneRemote/   local PWA (HTML/CSS/vanilla JS)
VSCodeExtension/         optional SSH terminal-workspace helper
Tools/                   launcher packaging, installation and sound generation
Tests/                   native and JavaScript regression coverage
Examples/                optional integration examples, no personal state
docs/                    product guides and screenshots
```

There is no Xcode project or Swift package dependency graph. `Sources/App.swift` is the host entry point; `Tools/TVLauncher.swift` is a separate tiny executable.

Key native modules:

- Inputs: `Devices`, `NativeShortcuts`, `PadInputWitness`, `LaptopShortcuts`, `CornerShortcuts`.
- Actions/layouts: `GroveActions`, `DeskSetup`, `WindowSnapper`, `MobileSpaces`, `MediaLauncher`, `MediaTiling`.
- Feedback: `ShortcutFeedback`, `CompanionScenes`, `CompanionSoundPicker`, `Adventure` and companion views.
- Phone: `PhoneRemote`, `RemoteTLS`, `RemoteProtocol`, `RemoteActions`.
- TV: `TVMode`, `TVView`, `TVDesktopView`, `TVOpenDiscovery`, `TVPlayerFullscreen`, `TVSessionLayout`, `TVDisplayAutomation`.
- Audio/experimental captions: `TVAudio`, `CaptionAudioTap`, `TVLiveCaptions`, `TVCaptionCues`.

The phone UI embeds `body.html` inside `index.html`: keep them synchronized. `tv.js` uses the same typed server command path as native TV controls. Do not add arbitrary code-execution endpoints.

## Build and test

```sh
./build.sh --build-only
./scripts/test.sh
```

The build uses whole-module optimization and a local module cache. Do not change compiler inputs mid-build. Code signing is configurable and contains no author's signing fingerprint. CI uses a macOS 26 runner; local SDK availability still matters.

Focused tests cover fullscreen routing/policy and remote command validation, TV connection/blackout policy, phone controls and the optional VS Code extension. Historical regression files are included for deeper work; some require explicit fixtures, local library/artwork, or a suitable app bundle. Read them before running them. Avoid tests that move a user's live windows or launch games unexpectedly.

Use real display/player checks for UI behavior. An AX call returning success does not prove fullscreen video is visible. The GDN path uses verified button focus plus a keyboard event; mouse coordinates of hidden controls were unreliable.

## Public edition boundaries

The initial public snapshot came from the working 1.20.0 host. Portability changes include: generic starter actions; no saved TV identity/autostart; optional Connect config under app support; no machine-specific certificate fingerprint; original synthesized sounds in place of commercial samples; no user's settings, peers or credentials.

The original personal app may continue evolving independently. Source history starts clean here; do not pull in old build directories, private handoff files or runtime snapshots. The MIT license covers original code; see third-party notices for identities/logos/character references.

## Distribution

Create a fresh local build, run tests, verify signatures and package both apps with their full Resources. Never ship local TLS identity, pairing files or settings. `scripts/package-release.py` makes an Apple Silicon archive, VSIX and checksums without reading the app-support folder. Public binary builds are ad-hoc signed and not notarized; a future notarized release needs an appropriate Developer ID/notary workflow. Do not claim notarization based only on `codesign --verify`.
