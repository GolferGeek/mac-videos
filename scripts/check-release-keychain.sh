#!/bin/zsh
# Copy the exported app; replace only its executable with a synthetic-service probe.
# This never reads/writes the actual client/grant/pending services.
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="${1:?Usage: scripts/check-release-keychain.sh EXPORTED_APP ARCHIVE_BUILD_PRODUCTS}"
framework_products="${2:?Provide the archive's BuildProductsPath/Release directory}"
identity='Developer ID Application: Matthew Weber (227GEZ2676)'
scratch="$(mktemp -d "$PWD/.build/release-keychain.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
app="$scratch/mac-videos.app"
ditto "$source_app" "$app"
codesign -d --entitlements :- "$source_app" >"$scratch/entitlements.plist" 2>/dev/null
binary="$app/Contents/MacOS/mac-videos"
# The exported universal framework supplies both slices. Tests run on this host.
xcrun swiftc -parse-as-library scripts/keychain-smoke.swift \
    -F "$framework_products" -F "$app/Contents/Frameworks" -framework MacVideosCore \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$binary"
sign_probe() {
    codesign --force --options runtime --timestamp --sign "$identity" \
        --entitlements "$scratch/entitlements.plist" "$app"
}
sign_probe
"$binary" --write --require-data-protection
# A different Developer ID app with no access-group entitlement must be denied.
mv "$app/Contents/embedded.provisionprofile" "$scratch/profile"
codesign --force --options runtime --timestamp --sign "$identity" \
    --identifier io.golfergeek.mac-videos.tests.untrusted "$binary"
denied_status=0
denied_output="$("$binary" --require-data-protection 2>&1)" || denied_status=$?
[[ "$denied_status" == 1 && "$denied_output" == 'Keychain synthetic round trip: FAIL' ]] || {
    echo 'FAIL: untrusted probe must run and report a Keychain access failure'; exit 1
}
mv "$scratch/profile" "$app/Contents/embedded.provisionprofile"
sign_probe
"$binary" --require-data-protection
echo 'Provisioned data protection Keychain create/update/relaunch/delete and other-app denial: PASS'
