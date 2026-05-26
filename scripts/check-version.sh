#!/usr/bin/env bash
set -euo pipefail

# Fail when this plugin's version drifts from the version recorded for gitlore in
# the sibling marketplace repo. The two `version` strings are maintained by hand
# in separate repos (.claude-plugin/plugin.json here; .claude-plugin/marketplace.json
# in ../claude-plugins); `/plugin marketplace update` surfaces the marketplace
# value, so drift misreports the installed version. Run via `make check-version`.
#
# Usage: check-version.sh [PLUGIN_JSON] [MARKETPLACE_JSON]
# Both default relative to this script: ../.claude-plugin/plugin.json and the
# sibling ../../claude-plugins/.claude-plugin/marketplace.json.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$here/.." && pwd)"

plugin_json="${1:-$plugin_root/.claude-plugin/plugin.json}"
marketplace_json="${2:-$plugin_root/../claude-plugins/.claude-plugin/marketplace.json}"

# The marketplace lives in a separate repo that may not be checked out (fresh
# clone, CI without it). Skipping keeps the check non-fatal where it can't run;
# it only guards on machines where both repos are present.
if [ ! -f "$marketplace_json" ]; then
  echo "check-version: marketplace.json not found at $marketplace_json — skip" >&2
  exit 0
fi

plugin_ver="$(jq -r '.version' "$plugin_json")"
market_ver="$(jq -r '.plugins[] | select(.name=="gitlore") | .version' "$marketplace_json")"

if [ -z "$market_ver" ] || [ "$market_ver" = "null" ]; then
  echo "check-version: no gitlore entry (or no version) in $marketplace_json" >&2
  exit 1
fi

if [ "$plugin_ver" != "$market_ver" ]; then
  echo "check-version: version drift — plugin.json=$plugin_ver marketplace.json=$market_ver" >&2
  echo "  bump both to the same value before release." >&2
  exit 1
fi

echo "check-version: in sync ($plugin_ver)"
