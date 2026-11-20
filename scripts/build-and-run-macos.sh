#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_PACKAGE="$REPOSITORY_ROOT/swift/Apps/AmcamImagingApp"
readonly APP_PRODUCT="amcam-imaging"
readonly BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
readonly APP_NAME="Amcam Imaging.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "make run requires macOS; AppKit applications cannot be launched on this host." >&2
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
  "AmcamImagingCore"
  "AmcamImagingRuntime"
  "AmcamImagingGenTLAdapter"
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

# Vendor SDKs are deployment inputs, never user-selected files. Each vendor
# owns a directory under vendor/<vendor>/<platform>/ in the source checkout.
vendor_source="$REPOSITORY_ROOT/vendor"
vendor_destination="$app_bundle/Contents/Frameworks/Vendors"
rm -rf "$vendor_destination"
mkdir -p "$vendor_destination"

if [[ -d "$vendor_source" ]]; then
  cp -R "$vendor_source/." "$vendor_destination/"
fi

# Support the established AmScope SDK deployment convention and standard
# machine-local installation paths. The source file is never modified.
amcam_sdk_source="${AMCAM_SDK_SOURCE:-}"
if [[ -z "$amcam_sdk_source" ]]; then
  for candidate in \
    "$vendor_source/amcam/macos/libamcam.dylib" \
    "$HOME/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib" \
    "/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib" \
    "/Library/Frameworks/libamcam.dylib" \
    "/usr/local/lib/libamcam.dylib" \
    "/opt/homebrew/lib/libamcam.dylib"; do
    if [[ -f "$candidate" ]]; then
      amcam_sdk_source="$candidate"
      break
    fi
  done
fi

embedded_amcam_sdk="$vendor_destination/amcam/macos/libamcam.dylib"
if [[ -n "$amcam_sdk_source" ]]; then
  if [[ ! -f "$amcam_sdk_source" ]]; then
    echo "AMCAM_SDK_SOURCE does not identify a file: $amcam_sdk_source" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$embedded_amcam_sdk")"
  if [[ "$(cd "$(dirname "$amcam_sdk_source")" && pwd)" != "$(cd "$(dirname "$embedded_amcam_sdk")" && pwd)" ]]; then
    cp "$amcam_sdk_source" "$embedded_amcam_sdk"
  fi
elif [[ "${REQUIRE_AMCAM_SDK:-0}" == "1" ]]; then
  echo "AmScope SDK required but libamcam.dylib was not found." >&2
  echo "Place it at vendor/amcam/macos/libamcam.dylib or set AMCAM_SDK_SOURCE." >&2
  exit 1
else
  echo "AmScope SDK not found; the application will launch with the provider unavailable."
fi

if [[ -f "$embedded_amcam_sdk" ]]; then
  app_architectures="$(lipo -archs "$executable")"
  sdk_architectures="$(lipo -archs "$embedded_amcam_sdk")"
  for architecture in $app_architectures; do
    if ! [[ " $sdk_architectures " == *" $architecture "* ]]; then
      echo "AmScope SDK architecture mismatch: app requires $architecture; SDK contains: $sdk_architectures" >&2
      exit 1
    fi
  done
fi

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

# Sign each packaged vendor dylib before signing the containing application.
while IFS= read -r -d '' library; do
  codesign --force --sign - "$library"
  codesign --verify --strict "$library"
done < <(find "$vendor_destination" -type f -name '*.dylib' -print0)

codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"

if [[ "${BUILD_ONLY:-0}" == "1" ]]; then
  echo "Build completed: $app_bundle"
  exit 0
fi

echo
echo "Launching $app_bundle"
open "$app_bundle"
