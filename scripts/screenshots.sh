#!/bin/bash
# Takes screenshots of the app in the iOS simulator, in light and dark mode, on an iPhone and an
# iPad. CI runs it on every pull request, so a PR that changes a screen shows how it looks without
# anyone needing a Mac.
#
# Usage: scripts/screenshots.sh <path to Conclave.app> <output folder>
#
# What takes the time on a CI runner (measured in #29): a freshly made simulator needs about 10 minutes
# to boot, and the simulator service runs one device's commands at a time, so a second device can't
# shoot alongside the first (its first command waited 10 minutes). So both devices boot together, then
# shoot one after the other, and each screen is launched once and shot in light and then in dark mode.
# Every simulator command that takes 10 s or more is logged with its time.
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

# runs simctl for the current device, timed
sim() { timed xcrun simctl "$1" "$udid" "${@:2}"; }

# boots both devices at once: the boot is the long part, and two take as long as one
for kind in "${DEVICES[@]}"; do
  udid=$(device "$kind")
  echo "Booting $kind ($udid)"
  sim boot 2>/dev/null || true
done
for kind in "${DEVICES[@]}"; do
  udid=$(device "$kind")
  sim bootstatus -b >/dev/null
done

# opens a screen afresh and waits until it has settled
open_screen() {
  SIMCTL_CHILD_CONCLAVE_SCREEN="$1" timed xcrun simctl launch --terminate-running-process "$udid" "$bundle" >/dev/null
  sleep 4 # a cold launch, keyboard-free: long enough for the first frame and its animations
  case "$1" in card | cards | filters) sleep 4 ;; esac # pictures and search results come from Scryfall
}

for kind in "${DEVICES[@]}"; do
  udid=$(device "$kind")
  slug=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
  echo "Device: $(xcrun simctl list devices -j | jq -r --arg u "$udid" '.devices[][] | select(.udid == $u) | .name')"
  # Apple's marketing screenshots: 9:41, full bars, full battery
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  sim install "$app"

  for screen in "${SCREENS[@]}"; do
    xcrun simctl ui "$udid" appearance light
    open_screen "$screen"
    sim io screenshot --type=png "$out/$slug-light-$screen.png" >/dev/null 2>&1
    # the running app follows the switch to dark mode, so most screens need no second launch
    xcrun simctl ui "$udid" appearance dark
    if [ "$screen" = saved ]; then
      open_screen "$screen" # its toast is gone after 6 s
    else
      sleep 2
    fi
    sim io screenshot --type=png "$out/$slug-dark-$screen.png" >/dev/null 2>&1
    echo "  $slug-light-$screen.png, $slug-dark-$screen.png"
  done
  xcrun simctl shutdown "$udid"
done
