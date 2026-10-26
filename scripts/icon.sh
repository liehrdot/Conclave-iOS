#!/bin/bash
# Shows the app icon the way iOS draws it, without a Mac at hand. CI runs it when the icon
# changes, or when started by hand (Actions › CI › Run workflow).
# Usage: scripts/icon.sh <path to Conclave.app> <output folder>
#
# 1. Icon Composer's command line tool (ictool, inside Xcode) renders App/AppIcon.icon with Liquid
#    Glass in all six appearances people can pick: default, dark, clear light/dark, tinted light/dark.
# 2. The app goes onto a simulator's Home Screen, which is photographed in light and dark mode.
set -euo pipefail

app="$1"
out="$2"
mkdir -p "$out"

ictool=$(find "$(xcode-select -p)/.." /Applications -path "*Icon Composer.app/Contents/Executables/ictool" -print -quit 2>/dev/null || true)
if [ -n "$ictool" ]; then
  echo "ictool: $ictool"
  for rendition in Default Dark ClearLight ClearDark TintedLight TintedDark; do
    "$ictool" App/AppIcon.icon --export-image --output-file "$out/icon-$rendition.png" \
      --platform iOS --rendition "$rendition" --width 1024 --height 1024 --scale 1
    echo "  icon-$rendition.png"
  done
else
  echo "No ictool in this Xcode, skipping the renders"
fi

runtime=$(xcrun simctl list runtimes available -j |
  jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier')
udid=$(xcrun simctl list devices available -j |
  jq -r --arg rt "$runtime" '.devices[$rt] | map(select(.name | startswith("iPhone")))
    | (map(select(.name | test("Pro"))) + .) | first | .udid')
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app"
for appearance in light dark; do
  xcrun simctl ui "$udid" appearance "$appearance"
  sleep 4 # the Home Screen redraws its icons after a change of appearance
  xcrun simctl io "$udid" screenshot --type=png "$out/home-$appearance.png" >/dev/null
  echo "  home-$appearance.png"
done
xcrun simctl shutdown "$udid"
