#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
derived="${MAC_VIDEOS_BUILD_DIR:-$PWD/.build}"
xcodebuild -project MacVideos.xcodeproj -scheme MacVideos -configuration Debug -derivedDataPath "$derived" build
app_plist="$derived/Build/Products/Debug/mac-videos.app/Contents/Info.plist"
for usage_key in NSCameraUsageDescription NSMicrophoneUsageDescription NSScreenCaptureUsageDescription; do
    [[ -n "$(/usr/libexec/PlistBuddy -c "Print :$usage_key" "$app_plist")" ]]
done
for camera_key in NSCameraUseExternalDeviceType NSCameraUseContinuityCameraDeviceType; do
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$camera_key" "$app_plist")" == "true" ]]
done
codesign --verify --deep --strict "$derived/Build/Products/Debug/mac-videos.app"
echo "App privacy metadata and local signature: PASS"
xcodebuild -project MacVideos.xcodeproj -scheme MacVideos -configuration Debug -derivedDataPath "$derived" test
