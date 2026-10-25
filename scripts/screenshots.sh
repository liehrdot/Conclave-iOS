#!/bin/bash
# Takes screenshots of the app in the iOS simulator, in light and dark mode, on an iPhone and an
# iPad. CI runs it on every pull request, so a PR that changes a screen shows how it looks without
# anyone needing a Mac. Usage: scripts/screenshots.sh <path to Conclave.app> <output folder>
#
# Each entry of SCREENS is a screen name the app opens straight away when it gets it as the
# environment variable CONCLAVE_SCREEN (the simulator passes on every SIMCTL_CHILD_* variable).
# Add a name here when the app learns to open a new screen.
set -euo pipefail

app="$1"
out="$2"
SCREENS=(welcome code scan signed-off decks deck rule0 card opponents opponent settings)
# The look-and-feel variants (`Look` in the app, environment variable CONCLAVE_LOOK) on the screens they change.
LOOKS=(gallery brand glass)
LOOK_SCREENS=(decks deck)
DEVICES=("iPhone" "iPad")
bundle=app.conclave.mobile

mkdir -p "$out"

# the newest iOS runtime the runner has, and the first device of each kind on it, preferring Pro
runtime=$(xcrun simctl list runtimes available -j |
  jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier')
echo "Runtime: $runtime"

# shoot <screen> <look> <seconds to wait> <file name>
shoot() {
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  SIMCTL_CHILD_CONCLAVE_SCREEN="$1" SIMCTL_CHILD_CONCLAVE_LOOK="$2" xcrun simctl launch "$udid" "$bundle" >/dev/null
  sleep "$3"
  xcrun simctl io "$udid" screenshot --type=png "$out/$4" >/dev/null
  echo "  $4"
}

for kind in "${DEVICES[@]}"; do
  udid=$(xcrun simctl list devices available -j |
    jq -r --arg rt "$runtime" --arg kind "$kind" '
      .devices[$rt] | map(select(.name | startswith($kind)))
      | (map(select(.name | test("Pro"))) + .) | first | .udid')
  name=$(xcrun simctl list devices -j | jq -r --arg u "$udid" '.devices[][] | select(.udid == $u) | .name')
  echo "Device: $name ($udid)"
  slug=$(echo "$kind" | tr '[:upper:]' '[:lower:]')

  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # Apple's marketing screenshots: 9:41, full bars, full battery
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl install "$udid" "$app"

  for appearance in light dark; do
    xcrun simctl ui "$udid" appearance "$appearance"
    for screen in "${SCREENS[@]}"; do
      wait=4 # first launch, keyboard-free: long enough for the first frame and its animations
      [ "$screen" = card ] && wait=8 # the card picture comes from Scryfall
      shoot "$screen" today "$wait" "$slug-$appearance-$screen.png"
    done
    for look in "${LOOKS[@]}"; do
      for screen in "${LOOK_SCREENS[@]}"; do
        shoot "$screen" "$look" 8 "$slug-$appearance-look-$look-$screen.png" # the art comes from Scryfall
      done
    done
  done
  xcrun simctl shutdown "$udid"
done
