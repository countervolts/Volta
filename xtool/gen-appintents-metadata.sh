#!/usr/bin/env bash
#
# gen-appintents-metadata.sh — generate the Metadata.appintents bundle for Siri.
#
# WHY THIS EXISTS
# --------------
# iOS only registers an app's Siri intents (the App Shortcuts in
# Sources/Volta/Intents/PlayIntents.swift) if the .app contains a
# "Metadata.appintents" bundle. That bundle is produced by Apple's
# `appintentsmetadataprocessor`, which ONLY runs as part of an Xcode/macOS build.
# xtool builds with SwiftPM on Linux and never runs it, so Siri sees nothing.
#
# This script regenerates that bundle ON A MAC using the real Apple tool, writes
# it to xtool/Metadata.appintents, and then deploy.sh injects it into the app on
# every build. You only need to re-run this when the intents in PlayIntents.swift
# change.
#
# REQUIREMENTS
# ------------
#   * macOS with Xcode (full Xcode, not just Command Line Tools) installed.
#   * Run from the repo root:  ./xtool/gen-appintents-metadata.sh
#
# HOW IT WORKS
# ------------
# xcodebuild compiles the Volta Swift package for iOS (arm64). Xcode 15+ emits
# .swiftconstvalues files automatically for any target that imports AppIntents,
# and runs appintentsmetadataprocessor as part of the build. We just copy the
# resulting .appintents bundle from DerivedData to xtool/Metadata.appintents.
#
# GUI FALLBACK (most reliable — uses Xcode end to end)
# -----------------------------------------------------
# If this script fails on your Xcode version:
#   1. In Xcode, File > New > Project > iOS App ("VoltaShim"), deployment target 17.0.
#   2. File > Add Package Dependencies > Add Local… > select this repo. Add the
#      "Volta" library to the VoltaShim app target.
#   3. Build VoltaShim for "Any iOS Device (arm64)".
#   4. Find the generated bundle:
#         find ~/Library/Developer/Xcode/DerivedData -type d -name Metadata.appintents
#   5. Copy it here:
#         cp -R "<that path>" xtool/Metadata.appintents
#   6. Commit xtool/Metadata.appintents and run ./xtool/deploy.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ "$(uname)" != "Darwin" ]; then
  echo "!! This must run on macOS — appintentsmetadataprocessor is macOS-only." >&2
  exit 1
fi

if ! xcrun -f appintentsmetadataprocessor &>/dev/null; then
  echo "!! appintentsmetadataprocessor not found. Install full Xcode and run:" >&2
  echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

MODULE="Volta"
BUILD_DIR=".build/appintents-metadata"
DERIVED_DATA="$BUILD_DIR/derived-data"
OUT_DIR="xtool/Metadata.appintents"

mkdir -p "$BUILD_DIR"

echo "==> Building Volta for iOS (arm64) via xcodebuild …"
# xcodebuild runs appintentsmetadataprocessor internally and writes the bundle
# to Build/Products/Debug-iphoneos/<module>.appintents. We then copy it.
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
if ! xcodebuild \
  -scheme "$MODULE" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Debug \
  build \
  > "$BUILD_LOG" 2>&1; then
  echo "!! xcodebuild failed. Errors:" >&2
  grep -E "error:" "$BUILD_LOG" | head -20 >&2 || true
  echo "" >&2
  echo "   Full log: $BUILD_LOG" >&2
  exit 1
fi
echo "   xcodebuild succeeded."

# xcodebuild writes the bundle as <module>.appintents inside the products dir.
BUILT_BUNDLE="$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -name "${MODULE}.appintents" -type d 2>/dev/null | head -1)"
if [ -z "$BUILT_BUNDLE" ]; then
  echo "!! ${MODULE}.appintents bundle not found in DerivedData after build." >&2
  echo "   The Volta target may not have an app intents build phase." >&2
  echo "   Try the GUI fallback documented at the bottom of this script." >&2
  exit 1
fi

echo "   Found bundle: $BUILT_BUNDLE"

# xcodebuild nests the real bundle inside Volta.appintents/Metadata.appintents;
# we want the inner Metadata.appintents at xtool/Metadata.appintents.
INNER_BUNDLE="$BUILT_BUNDLE/Metadata.appintents"
if [ ! -d "$INNER_BUNDLE" ]; then
  # Older Xcode versions put files directly in the .appintents dir
  INNER_BUNDLE="$BUILT_BUNDLE"
fi

rm -rf "$OUT_DIR"
cp -R "$INNER_BUNDLE" "$OUT_DIR"

if [ -f "$OUT_DIR/extract.actionsdata" ]; then
  echo "==> Success! Wrote $OUT_DIR"
  echo "    Commit it, then run ./xtool/deploy.sh to ship Siri support."
else
  echo "!! Bundle was copied but extract.actionsdata is missing." >&2
  echo "   Inspect $OUT_DIR and try the GUI fallback if needed." >&2
  exit 1
fi
