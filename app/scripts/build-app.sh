#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
# --dist builds an Apple silicon (arm64) bundle and zips it for sharing. Intel is not built: macOS is ending
# support for Intel-based apps and the MLX and GPU features are Apple silicon only.
build_args=(-c release)
[[ "${1:-}" == "--dist" ]] && build_args+=(--arch arm64)
swift build $build_args
binary_dir="$(swift build $build_args --show-bin-path)"
app_dir="$PWD/dist/arbiter-activity-monitor.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/arbiter-activity-monitor" "$app_dir/Contents/MacOS/arbiter-activity-monitor"
swift scripts/create-icon.swift "$PWD/dist/ArbiterActivityMonitor.iconset"
iconutil -c icns "$PWD/dist/ArbiterActivityMonitor.iconset" -o "$app_dir/Contents/Resources/ArbiterActivityMonitor.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>arbiter-activity-monitor</string>
<key>CFBundleIdentifier</key><string>local.arbiter.system</string>
<key>CFBundleName</key><string>ARBITER Activity Monitor</string>
<key>CFBundleDisplayName</key><string>ARBITER Activity Monitor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>ArbiterActivityMonitor</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticTermination</key><false/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
print "Built $app_dir"
if [[ "${1:-}" == "--dist" ]]; then
  zip_path="$PWD/dist/ARBITER-Activity-Monitor-0.1.0-macos-arm64.zip"
  rm -f "$zip_path"
  ditto -c -k --keepParent "$app_dir" "$zip_path"
  print "Packaged $zip_path"
fi
