#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY="Shennagyp/AMSCOPE_DRIVER"
readonly BRANCH="macos-version-optimization"
readonly API_ROOT="https://api.github.com/repos/${REPOSITORY}"
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

for tool in curl python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required command not found: $tool" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/amscope-driver.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
artifact_dir="$work_dir/artifact"
mkdir -p "$artifact_dir"

api_headers=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
  -H "User-Agent: AMSCOPE_DRIVER-artifact-launcher"
)

echo "Finding the latest successful '$artifact_name' artifact on $BRANCH..."
runs_json="$work_dir/runs.json"
if ! curl -fsSL "${api_headers[@]}" \
  "$API_ROOT/actions/runs?branch=$BRANCH&status=success&per_page=100" \
  -o "$runs_json"; then
  echo "Could not query the public GitHub Actions API." >&2
  echo "Check network access or GitHub's anonymous API rate limit; no login is required." >&2
  exit 1
fi

run_ids="$(python3 - "$runs_json" "$BRANCH" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    payload = json.load(source)

for run in payload.get("workflow_runs", []):
    if (run.get("head_branch") == sys.argv[2]
            and run.get("status") == "completed"
            and run.get("conclusion") == "success"):
        print(run["id"])
PY
)"

artifact_id=""
while IFS= read -r run_id; do
  [[ -n "$run_id" ]] || continue
  artifacts_json="$work_dir/artifacts-$run_id.json"
  if ! curl -fsSL "${api_headers[@]}" \
    "$API_ROOT/actions/runs/$run_id/artifacts?per_page=100" \
    -o "$artifacts_json"; then
    echo "Warning: could not inspect artifacts for workflow run $run_id; trying an older successful run." >&2
    continue
  fi

  candidate="$(python3 - "$artifacts_json" "$artifact_name" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    payload = json.load(source)

for artifact in payload.get("artifacts", []):
    if artifact.get("name") == sys.argv[2] and not artifact.get("expired", True):
        print(artifact["id"])
        break
PY
)"
  if [[ -n "$candidate" ]]; then
    artifact_id="$candidate"
    echo "Using workflow run $run_id (artifact $artifact_id)."
    break
  fi
done <<< "$run_ids"

if [[ -z "$artifact_id" ]]; then
  echo "No unexpired '$artifact_name' artifact was found in the latest 100 successful runs on $BRANCH." >&2
  echo "Confirm that the branch workflow completed successfully and uploaded the expected artifact name." >&2
  exit 1
fi

archive="$work_dir/$artifact_name.zip"
echo "Downloading artifact anonymously..."
if ! curl -fLsS "${api_headers[@]}" \
  "$API_ROOT/actions/artifacts/$artifact_id/zip" \
  -o "$archive"; then
  echo "Artifact download failed. The artifact may have expired or GitHub may be temporarily unavailable." >&2
  exit 1
fi

ditto -x -k "$archive" "$artifact_dir"

if [[ "$mode" == "app" ]]; then
  app_path="$(find "$artifact_dir" -type d -name 'Amcam Imaging.app' -print -quit)"
  if [[ -z "$app_path" ]]; then
    nested_zip="$(find "$artifact_dir" -type f -name '*.zip' -print -quit)"
    if [[ -n "$nested_zip" ]]; then
      expanded="$work_dir/expanded-app"
      mkdir -p "$expanded"
      ditto -x -k "$nested_zip" "$expanded"
      app_path="$(find "$expanded" -type d -name 'Amcam Imaging.app' -print -quit)"
    fi
  fi

  if [[ -z "$app_path" || ! -d "$app_path" ]]; then
    echo "Could not locate 'Amcam Imaging.app' in the downloaded artifact." >&2
    find "$artifact_dir" -maxdepth 4 -print >&2
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
    nested_zip="$(find "$artifact_dir" -type f -name '*.zip' -print -quit)"
    if [[ -n "$nested_zip" ]]; then
      expanded="$work_dir/expanded-probe"
      mkdir -p "$expanded"
      ditto -x -k "$nested_zip" "$expanded"
      probe_path="$(find "$expanded" -type f -name 'amcam-camera-probe' -print -quit)"
    fi
  fi
  if [[ -z "$probe_path" ]]; then
    echo "Could not locate amcam-camera-probe in the downloaded artifact." >&2
    find "$artifact_dir" -maxdepth 4 -print >&2
    exit 1
  fi
  chmod +x "$probe_path"
  echo "Running camera probe. Pass extra arguments through PROBE_ARGS, e.g. PROBE_ARGS='--help'."
  # Intentional word splitting permits conventional command-line arguments.
  # shellcheck disable=SC2086
  "$probe_path" ${PROBE_ARGS:-}
fi
