#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY="Shennagyp/AMSCOPE_DRIVER"
readonly BRANCH="macos-version-optimization"
readonly API_ROOT="https://api.github.com/repos/${REPOSITORY}"
readonly RELEASE_TAG_PREFIX="macos-build-"
readonly APP_ASSET="Amcam-Imaging-macos-arm64.zip"
readonly PROBE_ASSET="amcam-camera-probe-macos-arm64.zip"

mode="${1:-app}"
case "$mode" in
  app) asset_name="$APP_ASSET" ;;
  probe) asset_name="$PROBE_ASSET" ;;
  *)
    echo "Usage: $0 [app|probe]" >&2
    exit 2
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This package can only run on macOS." >&2
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This build requires an Apple Silicon Mac (arm64)." >&2
  exit 1
fi
major_version="$(sw_vers -productVersion | cut -d. -f1)"
if (( major_version < 13 )); then
  echo "This build requires macOS 13 or later." >&2
  exit 1
fi
for tool in curl python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required command not found: $tool" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/amscope-driver.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
api_headers=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
  -H "User-Agent: AMSCOPE_DRIVER-release-launcher"
)

echo "Finding the latest public macOS release asset '$asset_name'..."
releases_json="$work_dir/releases.json"
if ! curl -fsSL "${api_headers[@]}" "$API_ROOT/releases?per_page=100" -o "$releases_json"; then
  echo "Could not query public GitHub releases." >&2
  echo "Check network access or GitHub's anonymous API rate limit; no login is required." >&2
  exit 1
fi

asset_url="$(python3 - "$releases_json" "$RELEASE_TAG_PREFIX" "$asset_name" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    releases = json.load(source)

prefix, expected_name = sys.argv[2], sys.argv[3]
for release in releases:
    if release.get("draft") or not release.get("tag_name", "").startswith(prefix):
        continue
    for asset in release.get("assets", []):
        if asset.get("name") == expected_name and asset.get("state") == "uploaded":
            print(asset["browser_download_url"])
            raise SystemExit(0)
raise SystemExit(1)
PY
)" || {
  echo "No published '$asset_name' was found in the latest 100 macOS build releases." >&2
  echo "The newest workflow must finish successfully and publish its release assets first." >&2
  exit 1
}

archive="$work_dir/$asset_name"
echo "Downloading public release asset..."
if ! curl -fLsS "$asset_url" -o "$archive"; then
  echo "Release asset download failed. Check that the repository release is public and the asset exists." >&2
  exit 1
fi

expanded="$work_dir/expanded"
mkdir -p "$expanded"
ditto -x -k "$archive" "$expanded"

if [[ "$mode" == "app" ]]; then
  app_path="$(find "$expanded" -type d -name 'Amcam Imaging.app' -print -quit)"
  if [[ -z "$app_path" ]]; then
    echo "The release ZIP did not contain 'Amcam Imaging.app'." >&2
    find "$expanded" -maxdepth 4 -print >&2
    exit 1
  fi
  destination="${APP_DESTINATION:-$HOME/Applications/Amcam Imaging.app}"
  mkdir -p "$(dirname "$destination")"
  if [[ -e "$destination" ]]; then rm -rf "$destination"; fi
  ditto "$app_path" "$destination"
  xattr -dr com.apple.quarantine "$destination" 2>/dev/null || true
  echo "Launching: $destination"
  open "$destination"
else
  probe_path="$(find "$expanded" -type f -name 'amcam-camera-probe' -print -quit)"
  if [[ -z "$probe_path" ]]; then
    echo "The release ZIP did not contain amcam-camera-probe." >&2
    find "$expanded" -maxdepth 4 -print >&2
    exit 1
  fi
  chmod +x "$probe_path"
  echo "Running camera probe. Pass extra arguments through PROBE_ARGS, e.g. PROBE_ARGS='--help'."
  # Intentional word splitting permits conventional command-line arguments.
  # shellcheck disable=SC2086
  "$probe_path" ${PROBE_ARGS:-}
fi
