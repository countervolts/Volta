#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP="xtool/Volta.app"
ICON_DIR="xtool/icon-src/loose"

# Default devices (override by passing UDIDs as arguments).
PHONES=( 00008020-000E0C3A2168402E 00008120-00124D56366A601E )
if [ "$#" -gt 0 ]; then
  PHONES=( "$@" )
fi

echo "==> Building (xtool dev build)..."
xtool dev build

if [ ! -d "$APP" ]; then
  echo "!! Build did not produce $APP" >&2
  exit 1
fi

echo "==> Injecting loose icon PNGs into app-bundle root..."
cp "$ICON_DIR"/AppIcon*.png "$APP"/
ls "$APP"/AppIcon*.png | sed 's/^/     injected: /'

echo "==> Verifying CFBundleIcons is present in the built Info.plist..."
if grep -q "CFBundleIcons" "$APP/Info.plist"; then
  echo "     ok: CFBundleIcons found"
else
  echo "!! CFBundleIcons missing from $APP/Info.plist — icon will not show." >&2
  echo "   (Check that Info.plist is merged via xtool.yml infoPath.)" >&2
  exit 1
fi

# --- App Intents / Siri metadata ------------------------------------------
# iOS discovers an app's Siri intents (the App Shortcuts in
# Sources/Volta/Intents/PlayIntents.swift) from a "Metadata.appintents" bundle
# that Apple's appintentsmetadataprocessor generates at build time. xtool builds
# with SwiftPM and never runs that processor, so without injecting the bundle
# here Siri has no idea Volta exposes any intents ("Volta hasn't added support").
# The bundle must be generated once on a Mac — see xtool/gen-appintents-metadata.sh —
# then committed to xtool/Metadata.appintents. We inject it into the app bundle.
METADATA_SRC="xtool/Metadata.appintents"
if [ -d "$METADATA_SRC" ]; then
  echo "==> Injecting App Intents metadata for Siri ..."
  rm -rf "$APP/Metadata.appintents"
  cp -R "$METADATA_SRC" "$APP/Metadata.appintents"
  echo "     injected: $APP/Metadata.appintents"
else
  echo "!! WARNING: $METADATA_SRC not found — Siri / App Shortcuts will NOT register." >&2
  echo "   Generate it once on macOS:  ./xtool/gen-appintents-metadata.sh" >&2
  echo "   then commit xtool/Metadata.appintents and re-run this script." >&2
fi

for udid in "${PHONES[@]}"; do
  echo "==> Installing to $udid ..."
  xtool install --udid "$udid" "$APP"
done

echo "all done."
