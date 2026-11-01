# Install on a new Mac

[← Overview](../README.md)

## 1. Choose your installation path

### Download the Apple Silicon apps

Download the app archive and `SHA256SUMS` from [Releases](https://github.com/amit154154/koala-controls/releases). Compare the archive checksum with `shasum -a 256 <archive>`, extract it, and copy **Mini Keyboard.app** and **Koala TV.app** to `/Applications`. Launch Mini Keyboard first.

The downloadable build is ad-hoc signed, **not Developer ID notarized**. macOS can show an unverified-developer warning. If you trust the source/release, use the normal macOS Privacy & Security → Open Anyway approval flow. Do not disable Gatekeeper or run random quarantine-removal commands. [Apple's distribution guidance](https://developer.apple.com/developer-id/) explains the distinction. Building locally is another option.

### Build locally

Requirements: recent Xcode / Command Line Tools with macOS 26+ SDK, Python 3, and Git. Use `xcode-select --install` if command-line tools are absent; if the SDK is too old, install a newer Xcode. Check with `xcrun --show-sdk-version` and `swiftc --version`.

```sh
git clone https://github.com/amit154154/koala-controls.git
cd koala-controls
./build.sh --build-only
```

Output: `build/Mini Keyboard.app` and `build/Koala TV.app`. No package manager or third-party Swift dependencies are needed. The public release is tested on Apple Silicon. Intel builds can be attempted with `KOALA_ARCH=x86_64` but are not verified.

The script automatically uses an available Apple Development / Developer ID identity, otherwise local ad-hoc signing. To choose explicitly:

```sh
KOALA_SIGN_IDENTITY="YOUR_CERTIFICATE_NAME_OR_FINGERPRINT" ./build.sh --build-only
```

Keep that same identity for later updates. Ad-hoc rebuilds can require fresh permission approval. Do not reset privacy permissions as a routine install step.

Quit Mini Keyboard normally, then:

```sh
python3 Tools/install.py
open "/Applications/Mini Keyboard.app"
```

The installer preserves settings and pairing, replaces only app Contents, saves rollback backups in `build/backups`, and rolls both apps back if installation fails. It refuses to install over a running host. `./build.sh --install` is the build-and-install equivalent.

## 2. Approve the permissions you use

| Permission | Why | Needed for |
| --- | --- | --- |
| Accessibility | Send shortcuts and position/control windows | Window actions, laptop shortcuts, TV control |
| Input Monitoring | Read the selected pad's mapped inputs | USB mini keyboard |
| Automation → Google Chrome | Reuse/select media and visualization tabs | Chrome integrations |
| Local Network | Serve your paired phone over local HTTPS | Koala Remote |
| Bluetooth | Connect supported paired headphones | Optional audio controls |
| System audio capture | Transcribe selected app playback locally | Optional experimental captions |

Open **System Settings → Privacy & Security**, add the installed **Mini Keyboard.app** to Accessibility and Input Monitoring, and enable it. Only enable other prompts when using the corresponding feature. The TV launcher delegates permissions to the host.

## 3. Set up only what you need

- **Keyboard:** choose your USB pad under Setup, run Learn all keys, review assignments, and Apply shortcuts. Consumer-key/firmware differences can require manual learning. The original tested pad is USB vendor `0x1189`, product `0x8842`; other pads are not guaranteed.
- **Laptop only:** enable Command + Option shortcuts under Setup. No USB pad is required.
- **TV only:** open Koala TV, choose the external display, then open/resume a service. No pad or iPhone is required.
- **iPhone:** follow [pairing instructions](PHONE-REMOTE.md). Each new Mac creates its own local trust identity.
- **Optional integrations:** see [the keyboard guide](MINI-KEYBOARD.md) for Connect, Koala Viz and the VS Code extension.

## 4. Moving your setup

Your assignments are in `~/Library/Application Support/Mini Keyboard/settings.json`. You may copy that file yourself to a new Mac while the app is closed. Recheck selected hardware and learn inputs if the pad differs. The Adventure directory can also be copied if you want your local progress.

Do not publish this folder or copy old TLS private keys merely to avoid pairing. Pair the phone with the new Mac normally, reapprove macOS permissions, and remember the new TV from TV settings. Screen IDs and TV UUIDs are machine/setup-specific.
