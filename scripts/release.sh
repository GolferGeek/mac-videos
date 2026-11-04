#!/bin/zsh
# Build and notarize locally. Publishing/installing remain explicit separate actions.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: scripts/release.sh VERSION [BUILD_NUMBER]}"
build_number="${2:-$(awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)}"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo 'Expected a numeric X.Y.Z version'; exit 1; }
[[ "$build_number" =~ '^[1-9][0-9]{0,3}$' ]] || { echo 'Expected a positive build number up to 9999'; exit 1; }
identity='Developer ID Application: Matthew Weber (227GEZ2676)'
security find-identity -v -p codesigning | /usr/bin/grep -Fq "$identity" || { echo 'Developer ID Application certificate/private key missing'; exit 1; }
xcrun notarytool history --keychain-profile mac-videos-notary --output-format json >/dev/null
output="$PWD/.build/releases/$version-$build_number"
[[ ! -e "$output" ]] || { echo 'Output already exists; choose a new incrementing build number'; exit 1; }
mkdir -p "$output"
trap 'echo "Release failed. Inspect logs in $output; no download is ready to publish." >&2' ZERR
xcodebuild -project MacVideos.xcodeproj -scheme MacVideos -configuration Release \
    -derivedDataPath "$output/derived" -archivePath "$output/MacVideos.xcarchive" \
    -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic 'CODE_SIGN_IDENTITY=Apple Development' \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' archive >"$output/archive.log" 2>&1
xcodebuild -exportArchive -archivePath "$output/MacVideos.xcarchive" \
    -exportPath "$output/export" -exportOptionsPlist scripts/ExportOptions.plist \
    -allowProvisioningUpdates >"$output/export.log" 2>&1
app="$output/export/mac-videos.app"
plist="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "$build_number" ]]
lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/mac-videos"
lipo -verify_arch arm64 x86_64 "$app/Contents/Frameworks/MacVideosCore.framework/MacVideosCore"
codesign --verify --deep --strict "$app"
codesign -dv --verbose=4 "$app" 2>"$output/signature.txt"
/usr/bin/grep -Fq "Authority=$identity" "$output/signature.txt"
/usr/bin/grep -Fq 'flags=0x10000(runtime)' "$output/signature.txt"
[[ -f "$app/Contents/embedded.provisionprofile" ]]
codesign -d --entitlements :- "$app" >"$output/entitlements.plist" 2>/dev/null
python3 - "$output/entitlements.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: ent = plistlib.load(f)
assert ent['keychain-access-groups'] == ['227GEZ2676.io.golfergeek.mac-videos']
assert ent['com.apple.security.device.camera'] is True
assert ent['com.apple.security.device.audio-input'] is True
assert not ent.get('com.apple.security.get-task-allow', False)
assert not ent.get('com.apple.security.cs.disable-library-validation', False)
PY
./scripts/check-release-keychain.sh "$app" \
    "$output/derived/Build/Intermediates.noindex/ArchiveIntermediates/MacVideos/BuildProductsPath/Release" >"$output/keychain-check.log" 2>&1
zip="$output/mac-videos-$version-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/submission.zip"
xcrun notarytool submit "$output/submission.zip" --keychain-profile mac-videos-notary \
    --wait --output-format json >"$output/notary-result.json"
python3 - "$output/notary-result.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f: result = json.load(f)
assert result['status'] == 'Accepted', 'Notarization did not accept the app; inspect notary-result.json'
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl -a -vv --type execute "$app"
# Only this ZIP contains the stapled app. Never publish submission.zip.
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd "$output" && shasum -a 256 "${zip:t}" >SHA256SUMS.txt)
echo "Verified release: $zip"
