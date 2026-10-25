#!/bin/bash
# Copies the shared operation test cases (docs/app-api/ops.json) from Conclave into the core's
# tests, at one Conclave commit, and notes that commit next to the file. Run it when Conclave's
# appops.py changed, then fix whatever the core tests now find. Usage: scripts/update_api_cases.sh <full commit hash>
set -euo pipefail

rev="${1:?usage: scripts/update_api_cases.sh <full Conclave commit hash>}"
dir="$(dirname "$0")/../Packages/ConclaveCore/Tests/ConclaveCoreTests/Resources"
curl -fsSL "https://raw.githubusercontent.com/liehrdot/Conclave/$rev/docs/app-api/ops.json" -o "$dir/ops.json"
echo "$rev" > "$dir/ops.rev"
echo "ops.json from Conclave $rev"
