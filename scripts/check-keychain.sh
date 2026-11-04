#!/bin/zsh
# Disposable synthetic service only. Run after check.sh builds MacVideosCore.
set -euo pipefail
cd "$(dirname "$0")/.."
derived="${MAC_VIDEOS_BUILD_DIR:-$PWD/.build}"
probe="$derived/keychain-smoke"
identity='Apple Development: MATT Weber (Q95DF7CUGG)'
compile_probe() {
    xcrun swiftc -parse-as-library "$1" -F "$derived/Build/Products/Debug" -framework MacVideosCore \
        -Xlinker -rpath -Xlinker "$derived/Build/Products/Debug" -o "$probe"
}
sign_probe() { codesign --force --sign "$identity" --identifier "$1" "$probe"; }
compile_probe scripts/keychain-smoke.swift
sign_probe io.golfergeek.mac-videos.tests.smoke
"$probe" --write
# Different app identity at the trusted path must not read the item.
sign_probe io.golfergeek.mac-videos.tests.untrusted
if "$probe"; then
    echo 'FAIL: another signed app read the test item'
    exit 1
fi
# New executable bytes, same app identity and path: simulate a signed update.
python3 - "$derived/keychain-smoke-updated.swift" <<'PY'
from pathlib import Path
import sys
source = Path('scripts/keychain-smoke.swift').read_text()
Path(sys.argv[1]).write_text(source.replace('round trip: PASS', 'round trip: PASS (signed replacement)'))
PY
compile_probe "$derived/keychain-smoke-updated.swift"
sign_probe io.golfergeek.mac-videos.tests.smoke
"$probe"
echo 'Keychain create/update/relaunch/delete, signed update and other-app denial: PASS'
