#!/bin/bash
# Takes screenshots of the app in the iOS simulator, in light and dark mode, on an iPhone and an
# iPad. CI runs it on every pull request, so a PR that changes a screen shows how it looks without
# anyone needing a Mac.
#
# Usage:
#   scripts/screenshots.sh boot                         starts both simulators and returns at once
#   scripts/screenshots.sh <path to Conclave.app> <out>  takes the screenshots
#
# Booting a simulator on a CI runner takes minutes (6 for the iPhone, 3.5 for the iPad on 2026-10-26),
# more than all the screenshots together. So CI starts the boot before it builds the app, and the
# iPhone and the iPad then run side by side instead of one after the other.
#
# Each entry of SCREENS is a screen name the app opens straight away when it gets it as the
# environment variable CONCLAVE_SCREEN (the simulator passes on every SIMCTL_CHILD_* variable).
# Add a name here when the app learns to open a new screen.
set -euo pipefail

SCREENS=(welcome code scan signed-off decks deck rule0 card log-game saved opponents opponent edit-opponent cards filters describe settings)
DEVICES=("iPhone" "iPad")
bundle=app.conclave.mobile

# the newest iOS runtime the runner has
runtime=$(xcrun simctl list runtimes available -j |
  jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier')

# the first device of a kind ("iPhone", "iPad") on that runtime, preferring Pro
device() {
  xcrun simctl list devices available -j |
    jq -r --arg rt "$runtime" --arg kind "$1" '
      .devices[$rt] | map(select(.name | startswith($kind)))
      | (map(select(.name | test("Pro"))) + .) | first | .udid'
}

if [ "${1:-}" = "boot" ]; then
  echo "Runtime: $runtime"
  for kind in "${DEVICES[@]}"; do
    udid=$(device "$kind")
    echo "Booting $kind ($udid)"
    # in the background: the next CI steps run while it boots, and the screenshot step waits for it
    nohup xcrun simctl boot "$udid" >/dev/null 2>&1 &
  done
  exit 0
fi

app="$1"
out="$2"
mkdir -p "$out"
echo "Runtime: $runtime"

# all screenshots of one device, light and dark
shoot() {
  local kind="$1" udid name slug
  udid=$(device "$kind")
  name=$(xcrun simctl list devices -j | jq -r --arg u "$udid" '.devices[][] | select(.udid == $u) | .name')
  slug=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
  echo "Device: $name ($udid)"

  xcrun simctl boot "$udid" 2>/dev/null || true # already booting when CI ran "boot" first
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # Apple's marketing screenshots: 9:41, full bars, full battery
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl install "$udid" "$app"

  for appearance in light dark; do
    xcrun simctl ui "$udid" appearance "$appearance"
    for screen in "${SCREENS[@]}"; do
      xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
      SIMCTL_CHILD_CONCLAVE_SCREEN="$screen" xcrun simctl launch "$udid" "$bundle" >/dev/null
      sleep 4 # first launch, keyboard-free: long enough for the first frame and its animations
      case "$screen" in card | cards | filters) sleep 4 ;; esac # pictures and search results come from Scryfall
      xcrun simctl io "$udid" screenshot --type=png "$out/$slug-$appearance-$screen.png" >/dev/null 2>&1
      echo "  $slug-$appearance-$screen.png"
    done
  done
  xcrun simctl shutdown "$udid"
}

# both devices at once; a failure on either fails the run
pids=()
for kind in "${DEVICES[@]}"; do
  shoot "$kind" &
  pids+=($!)
done
status=0
for pid in "${pids[@]}"; do wait "$pid" || status=1; done
exit $status
