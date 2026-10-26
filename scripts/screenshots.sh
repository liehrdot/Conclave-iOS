#!/bin/bash
# Takes screenshots of the app in the iOS simulator, in light and dark mode, on an iPhone and an
# iPad. CI runs it on every pull request, so a PR that changes a screen shows how it looks without
# anyone needing a Mac.
#
# Usage: scripts/screenshots.sh <path to Conclave.app> <output folder>
#
# The iPhone and the iPad run side by side. A freshly booted simulator on a CI runner is slow for its
# first minutes, so every simulator command that takes 10 s or more is logged with its time: that shows
# which step waits, and for how long.
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

app="$1"
out="$2"
mkdir -p "$out"
echo "Runtime: $runtime"

# runs a command and logs it when it takes 10 s or more, on fd 3 (the log), since the callers
# silence the command's own output
exec 3>&1
timed() {
  local start=$SECONDS status=0
  "$@" || status=$?
  if ((SECONDS - start >= 10)); then echo "    $((SECONDS - start)) s: simctl $3 ($kind)" >&3; fi
  return $status
}

# all screenshots of one device, light and dark
shoot() {
  local kind="$1" udid name slug
  udid=$(device "$kind")
  name=$(xcrun simctl list devices -j | jq -r --arg u "$udid" '.devices[][] | select(.udid == $u) | .name')
  slug=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
  echo "Device: $name ($udid)"

  timed xcrun simctl boot "$udid" 2>/dev/null || true
  timed xcrun simctl bootstatus "$udid" -b >/dev/null
  # Apple's marketing screenshots: 9:41, full bars, full battery
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  timed xcrun simctl install "$udid" "$app"

  for appearance in light dark; do
    xcrun simctl ui "$udid" appearance "$appearance"
    for screen in "${SCREENS[@]}"; do
      timed xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
      SIMCTL_CHILD_CONCLAVE_SCREEN="$screen" timed xcrun simctl launch "$udid" "$bundle" >/dev/null
      sleep 4 # first launch, keyboard-free: long enough for the first frame and its animations
      case "$screen" in card | cards | filters) sleep 4 ;; esac # pictures and search results come from Scryfall
      timed xcrun simctl io "$udid" screenshot --type=png "$out/$slug-$appearance-$screen.png" >/dev/null 2>&1
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
