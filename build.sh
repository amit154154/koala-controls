#!/bin/bash
# Build without changing the installed app. Installation is explicitly opt-in.
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:---build-only}"
if [[ "$MODE" != --build-only && "$MODE" != --install ]]; then
  echo 'Usage: ./build.sh [--build-only | --install]'; exit 2
fi
command -v swiftc >/dev/null || { echo 'Install Xcode / Apple Command Line Tools first.'; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 is required to package the launcher.'; exit 1; }
ARCH="${KOALA_ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH"; exit 1;; esac
# Prefer an existing stable identity; no developer's certificate is hardcoded.
SIGN_IDENTITY="${KOALA_SIGN_IDENTITY:-${MINI_KEYBOARD_SIGN_IDENTITY:-}}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -nE '/Apple Development:|Developer ID Application:/s/^[[:space:]]*[0-9]+\) ([A-F0-9]+).*/\1/p' | head -1)"
  SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi
if [[ "$SIGN_IDENTITY" == - ]]; then
  echo 'Using local ad-hoc signing. Rebuilt apps may need refreshed macOS permissions.'
fi
OUT='build/Mini Keyboard.app'
# Recreate only this script's generated output; stale resources must not ship.
python3 - <<'PY'
from pathlib import Path
import shutil
p=Path('build/Mini Keyboard.app/Contents')
if p.exists():shutil.rmtree(p)
p.mkdir(parents=True)
PY
mkdir -p "$OUT/Contents/MacOS" build/module-cache
swiftc -O -whole-module-optimization -swift-version 5 -target "$ARCH-apple-macosx13.0" \
  -module-cache-path build/module-cache -parse-as-library Sources/*.swift -o "$OUT/Contents/MacOS/MiniKeyboard"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
ditto Resources "$OUT/Contents/Resources"
rm -f "$OUT/Contents/Resources/Info.plist"
codesign --force --sign "$SIGN_IDENTITY" "$OUT"
codesign --verify --deep --strict "$OUT"
python3 Tools/build_tv.py 'build/Koala TV.app' "$SIGN_IDENTITY"
echo 'Built build/Mini Keyboard.app and build/Koala TV.app'
if [[ "$MODE" == --install ]]; then
  python3 Tools/install.py
fi
