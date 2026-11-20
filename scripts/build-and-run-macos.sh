#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_PACKAGE="$REPOSITORY_ROOT/swift/Apps/AmcamImagingApp"
readonly APP_PRODUCT="amcam-imaging"
readonly BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
readonly APP_NAME="Amcam Imaging.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "make run requires macOS; SwiftUI applications cannot be launched on this host." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  cat >&2 <<'MESSAGE'
Swift is not installed or is not on PATH.
Install Apple's Command Line Tools (not the full Xcode application):
  xcode-select --install
Then verify with:
  swift --version
MESSAGE
  exit 1
fi

echo "Using Swift toolchain:"
swift --version

# Build every repository package explicitly. The two backend implementations
# are intentionally not linked into the app package; building them here keeps
# make run a complete source-build check of the library set as well.
packages=(
  "GenTLABI"
  "GenTLAPI"
  "GenTLNative"
  "AmcamCameraModel"
  "AmcamGenTL"
  "GenTLRouter"
)

for package in "${packages[@]}"; do
  package_path="$REPOSITORY_ROOT/swift/Packages/$package"
  echo
  echo "==> Building $package ($BUILD_CONFIGURATION)"
  swift build \
    --package-path "$package_path" \
    --configuration "$BUILD_CONFIGURATION"
done

echo
echo "==> Building $APP_PRODUCT ($BUILD_CONFIGURATION)"
swift build \
  --package-path "$APP_PACKAGE" \
  --configuration "$BUILD_CONFIGURATION" \
  --product "$APP_PRODUCT"

bin_path="$(swift build \
  --package-path "$APP_PACKAGE" \
  --configuration "$BUILD_CONFIGURATION" \
  --show-bin-path)"
executable="$bin_path/$APP_PRODUCT"
if [[ ! -x "$executable" ]]; then
  echo "SwiftPM reported a successful build but the executable is missing: $executable" >&2
  exit 1
fi

destination="${APP_DESTINATION:-$REPOSITORY_ROOT/.build/$APP_NAME}"
app_bundle="$destination"
mkdir -p "$app_bundle/Contents/MacOS"

cp "$executable" "$app_bundle/Contents/MacOS/$APP_PRODUCT"
cat > "$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>amcam-imaging</string>
  <key>CFBundleIdentifier</key><string>com.amscope.imaging</string>
  <key>CFBundleName</key><string>Amcam Imaging</string>
  <key>CFBundleDisplayName</key><string>Amcam Imaging</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"

if [[ "${BUILD_ONLY:-0}" == "1" ]]; then
  echo "Build completed: $app_bundle"
  exit 0
fi

echo
echo "Launching $app_bundle"
open "$app_bundle"
