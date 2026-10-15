#!/bin/bash
# Builds build/MachinePromptsMan.app and build/MachinePromptsMan.zip (what a release carries) from
# the Swift package. Needs a Mac with Apple's command line tools (xcode-select --install).
#
#   scripts/make-app.sh                            a local build
#   VERSION=1.0.7 BRANCH=main scripts/make-app.sh  what CI and the in-app updater run
#
# Environment:
#   VERSION         CFBundleShortVersionString (default: from Info.plist, e.g. 1.0)
#   BUILD_NUMBER    CFBundleVersion, digits only (default: the minute of the build, yyyymmddHHMM)
#   COMMIT          the commit it was built from (default: git HEAD, if this is a checkout)
#   BRANCH          the branch the in-app updater follows (default: main)
#   UNIVERSAL=1     arm64 + x86_64 (CI); default builds only this Mac's architecture
#   SIGN_IDENTITY   a code-signing identity from your keychain. Optional: without one the app is
#                   ad-hoc signed with a designated requirement of just its bundle identifier, so
#                   macOS treats every update as the same app (and keeps its permissions).
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=MachinePromptsMan
APP="build/$NAME.app"
PB=/usr/libexec/PlistBuddy
PLIST_VERSION="$($PB -c 'Print CFBundleShortVersionString' Info.plist 2>/dev/null || echo 1.0)"
VERSION="${VERSION:-$PLIST_VERSION}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
COMMIT="${COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
BRANCH="${BRANCH:-main}"

if [ "$(uname)" != "Darwin" ]; then
  echo "error: make-app.sh must run on macOS (this is $(uname))." >&2
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "error: building needs Apple's command line tools: run xcode-select --install" >&2
  exit 3
fi

# FluidAudio (the voices) needs Swift 6: an older Swift stops while resolving packages. When the
# Swift on the PATH is older (old command line tools) and a newer Xcode is installed, build with
# that Xcode instead.
swift_major() { "$@" --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+)\..*/\1/p' | head -1; }
major="$(swift_major swift || true)"
if [ -z "$major" ] || [ "$major" -lt 6 ]; then
  for dev in /Applications/Xcode*.app/Contents/Developer "$HOME"/Applications/Xcode*.app/Contents/Developer; do
    [ -d "$dev" ] || continue
    m="$(DEVELOPER_DIR="$dev" swift_major xcrun swift || true)"
    if [ -n "$m" ] && [ "$m" -ge 6 ]; then
      export DEVELOPER_DIR="$dev"
      major="$m"
      echo "==> using Swift $m from $dev"
      break
    fi
  done
fi
if [ -z "$major" ] || [ "$major" -lt 6 ]; then
  have="$(swift --version 2>/dev/null | head -1 || true)"
  echo "error: building needs Swift 6 or newer, and this Mac has: ${have:-no Swift}." >&2
  echo "       Update Apple's command line tools (sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install) or install Xcode 16 or newer, then try again." >&2
  exit 3
fi

if [ "${UNIVERSAL:-0}" = 1 ]; then ARCHS=(--arch arm64 --arch x86_64); else ARCHS=(); fi

echo "==> swift build -c release ($VERSION, $BRANCH, ${COMMIT:0:7})"
swift build -c release --product "$NAME" ${ARCHS[@]+"${ARCHS[@]}"}
BINDIR="$(swift build -c release --product "$NAME" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

echo "==> assembling $APP"
rm -rf ./build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/$NAME" "$APP/Contents/MacOS/$NAME"
# The packages' resource bundles (FluidAudio's), where their code looks for them.
for bundle in "$BINDIR"/*.bundle; do
  if [ -e "$bundle" ]; then cp -R "$bundle" "$APP/Contents/Resources/"; fi
done
cp Info.plist "$APP/Contents/Info.plist"
$PB -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
# CFBundleVersion must be numbers and dots: a "1.0-abc1234" there confuses Launch Services.
$PB -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
$PB -c "Add :MPMCommit string $COMMIT" "$APP/Contents/Info.plist"
$PB -c "Add :MPMBranch string $BRANCH" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

BUNDLE_ID="$($PB -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> signing with \"$SIGN_IDENTITY\""
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
else
  # An ad-hoc signature's default designated requirement is the binary's hash, which changes with
  # every build; macOS stores it with the Microphone and folder grants, so each update would look
  # like a new app. Requiring only the bundle identifier keeps the grants across builds.
  echo "==> ad-hoc signing ($BUNDLE_ID, identifier-only requirement)"
  codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
# The same check the in-app updater makes before it swaps a bundle in.
codesign --verify --deep --strict --verbose=1 "$APP"

ditto -c -k --keepParent "$APP" "build/$NAME.zip"
echo "==> built $(pwd)/$APP ($VERSION, $BRANCH, ${COMMIT:0:7})"
