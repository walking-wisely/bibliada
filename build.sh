#!/bin/bash
# Bibliada build script: xcodegen -> xcodebuild -> (optional) install to /Applications.
#
# Usage:
#   ./build.sh              # Release build, then offer to install to /Applications
#   ./build.sh --debug      # Debug build instead of Release
#   ./build.sh --no-install # Build only, skip the /Applications install step
#
# Signing note: without BIBLIADA_TEAM_ID set to a real Apple Developer Team ID,
# the build uses ad-hoc code signing (CODE_SIGN_IDENTITY=-). This builds and runs
# fine locally, but the com.bibliada.shared App Group entitlement cannot actually
# be granted without a real team + provisioning profile, so the app and widget
# each fall back to their own local UserDefaults. See README.md.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIGURATION="Release"
DO_INSTALL=1

for arg in "$@"; do
  case "$arg" in
    --debug)
      CONFIGURATION="Debug"
      ;;
    --no-install)
      DO_INSTALL=0
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install it with 'brew install xcodegen'." >&2
  exit 1
fi

echo "==> Generating Xcode project (xcodegen generate)"
xcodegen generate

DERIVED_DATA_PATH=".build"

# Without a real Apple Developer Team ID, Xcode refuses to build at all once
# App Group entitlements are present (ad-hoc signing can't satisfy them). In
# that case we disable code signing outright so the build succeeds locally;
# the app then can't see the App Group, and SettingsStore/widget degrade to
# local UserDefaults defaults. See project.yml and README.md for details.
EXTRA_XCODEBUILD_ARGS=()
if [ -z "${BIBLIADA_TEAM_ID:-}" ]; then
  echo "==> BIBLIADA_TEAM_ID not set: building unsigned (App Group / widget settings sharing will not work)"
  EXTRA_XCODEBUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

echo "==> Building Bibliada (configuration: $CONFIGURATION)"
xcodebuild \
  -project Bibliada.xcodeproj \
  -scheme Bibliada \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  ${EXTRA_XCODEBUILD_ARGS[@]+"${EXTRA_XCODEBUILD_ARGS[@]}"}

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Bibliada.app"

if [ ! -d "$BUILT_APP" ]; then
  echo "error: expected build product not found at $BUILT_APP" >&2
  exit 1
fi

echo "==> Built: $BUILT_APP"

if [ "$DO_INSTALL" -eq 0 ]; then
  echo "==> Skipping install (--no-install)"
  exit 0
fi

DEST="/Applications/Bibliada.app"

echo "==> Will install $BUILT_APP -> $DEST"
if [ -e "$DEST" ]; then
  read -r -p "    $DEST already exists. Overwrite? [y/N] " REPLY
  case "$REPLY" in
    [yY]|[yY][eE][sS])
      echo "==> Removing existing $DEST"
      rm -rf "$DEST"
      ;;
    *)
      echo "==> Skipping install."
      exit 0
      ;;
  esac
fi

echo "==> Copying to $DEST"
rsync -a --delete "$BUILT_APP/" "$DEST/"
echo "==> Installed Bibliada.app to /Applications"
