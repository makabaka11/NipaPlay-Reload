#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
flutter_sdk_path="${FLUTTER_ROOT:-$project_root/.dart_tool/ios-flutter-sdk}"
framework_root="$flutter_sdk_path/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64"
plugin_root="$project_root/packages/adaptive_platform_ui/macos"
native_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/nipaplay-native-controls.XXXXXX")"
trap 'rm -rf "$native_test_dir"' EXIT

# One compilation unit permits focused tests of the private AppKit control
# without starting the app or changing user settings.
cat "$plugin_root/Classes/AdaptivePlatformUiPlugin.swift" \
    "$plugin_root/Tests/MediaControlSmoke.swift" > "$native_test_dir/main.swift"
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target "$(uname -m)-apple-macos12.0" \
  -module-cache-path "$native_test_dir/module-cache" \
  -F "$framework_root" -framework FlutterMacOS \
  -Xlinker -rpath -Xlinker "$framework_root" \
  "$native_test_dir/main.swift" -o "$native_test_dir/check"
"$native_test_dir/check"
