#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY="Shennagyp/AMSCOPE_DRIVER"
readonly BRANCH="macos-version-optimization"
readonly APP_ARTIFACT="amcam-imaging-macos-arm64"
readonly PROBE_ARTIFACT="amcam-camera-probe-macos-arm64"

mode="${1:-app}"
case "$mode" in
  app) artifact_name="$APP_ARTIFACT" ;;
  probe) artifact_name="$PROBE_ARTIFACT" ;;
  *)
    echo "Usage: $0 [app|probe]" >&2
    exit 2
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This artifact is a macOS executable and can only run on macOS." >&2
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

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required. Install it, then authenticate with: gh auth login" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/amscope-driver.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
artifact_dir="$work_dir/artifact"
mkdir -p "$artifact_dir"

echo "Downloading latest '$artifact_name' artifact from $REPOSITORY ($BRANCH)..."
gh run download \
  --repo "$REPOSITORY" \
  --branch "$BRANCH" \
  --name "$artifact_name" \
  --dir "$artifact_dir"

if [[ "$mode" == "app" ]]; then
  app_path="$(find "$artifact_dir" -type d -name 'Amcam Imaging.app' -print -quit)"
  if [[ -z "$app_path" ]]; then
    nested_zip="$(find "$artifact_dir" -type f -name '*.zip' -print -quit)"
    if [[ -z "$nested_zip" ]]; then
      echo "Artifact did not contain the expected app bundle or nested ZIP." >&2
      find "$artifact_dir" -maxdepth 3 -print >&2
      exit 1
    fi
    expanded="$work_dir/expanded-app"
    mkdir -p "$expanded"
    ditto -x -k "$nested_zip" "$expanded"
    app_path="$(find "$expanded" -type d -name 'Amcam Imaging.app' -print -quit)"
  fi

  if [[ -z "$app_path" || ! -d "$app_path" ]]; then
    echo "Could not locate 'Amcam Imaging.app' in the downloaded artifact." >&2
    exit 1
  fi

  destination="${APP_DESTINATION:-$HOME/Applications/Amcam Imaging.app}"
  mkdir -p "$(dirname "$destination")"
  if [[ -e "$destination" ]]; then
    rm -rf "$destination"
  fi
  ditto "$app_path" "$destination"
  xattr -dr com.apple.quarantine "$destination" 2>/dev/null || true
  echo "Launching: $destination"
  open "$destination"
else
  probe_path="$(find "$artifact_dir" -type f -name 'amcam-camera-probe' -print -quit)"
  if [[ -z "$probe_path" ]]; then
    echo "Could not locate amcam-camera-probe in the downloaded artifact." >&2
    find "$artifact_dir" -maxdepth 3 -print >&2
    exit 1
  fi
  chmod +x "$probe_path"
  echo "Running camera probe. Pass extra arguments through PROBE_ARGS, e.g. PROBE_ARGS='--help'."
  # Intentional word splitting permits conventional command-line arguments.
  # shellcheck disable=SC2086
  "$probe_path" ${PROBE_ARGS:-}
fi
