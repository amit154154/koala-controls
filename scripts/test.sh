#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests build/module-cache
swiftc -Onone -swift-version 5 -parse-as-library -module-cache-path build/module-cache   Sources/TVPlayerFullscreen.swift Sources/RemoteProtocol.swift Tests/TVFullscreenRegression.swift -o build/tests/fullscreen
build/tests/fullscreen
swiftc -Onone -swift-version 5 -parse-as-library -module-cache-path build/module-cache   Sources/TVDisplayAutomation.swift Sources/RemoteProtocol.swift Tests/TVConnectionRegression.swift -o build/tests/connection
build/tests/connection
node Tests/phone-tv-av.test.js Resources/PhoneRemote
node Tests/phone-chords.test.js Resources/PhoneRemote
node --test VSCodeExtension/test/*.test.js
python3 - <<'PYTHON'
from pathlib import Path
import plistlib
r=Path('Resources/PhoneRemote')
assert (r/'body.html').read_text() in (r/'index.html').read_text()
p=plistlib.loads(Path('Resources/TVAutoDisplay.plist').read_bytes())
assert not p['automatic'] and not p['blankMac'] and not p['displayUUID']
print('Portable TV defaults and embedded phone markup verified.')
PYTHON
