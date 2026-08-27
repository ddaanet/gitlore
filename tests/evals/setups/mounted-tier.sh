#!/usr/bin/env bash
# Scenario fixture: an acme tier already mounted AND active.
#
# The starting state for anything that grades what happens *after* a tier exists
# — routing a portable fact into it, mirroring its index, committing it in
# lockstep with memory.
#
# The mount goes through the production scripts/add-tier.sh, driven by the same
# intent file the agent writes. A hand-rolled `submodule add` here would be a
# second, drifting definition of what a mounted tier looks like; if add-tier.sh
# breaks, this fixture should fail loudly rather than paper over it.
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) captures below

SETUPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$SETUPS_DIR/../../.." && pwd)}"

bash "$SETUPS_DIR/tier-remote.sh"

cat > .claude/gitlore-add-tier <<EOF
mode=mount
name=acme
url=$PWD/.tier-remote.git
EOF

CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/add-tier.sh" >/dev/null
rm -f .claude/gitlore-add-tier

[ -e memory/acme/.git ] || { echo "fixture: acme tier did not mount" >&2; exit 1; }

# Activate it. Listed = active, file order = precedence (D17).
printf 'acme\n' > memory/.gitlore-tiers

git -C memory/acme config user.email "eval@test.com"
git -C memory/acme config user.name "Eval Test"

# Compose here rather than leaving it to the agent's SessionStart: the fixture's
# job is to hand over an already-settled store. Otherwise the very first hook of
# the session rewrites the indexes, and the scenario grades a store that changed
# under the agent between reading it and writing to it.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
gitlore_compose memory >/dev/null

# Commit the mount, the manifest and the composed indexes, so the agent starts
# from a clean store rather than one already dirty with fixture setup — a dirty
# store would put the commit gate's "uncommitted changes present" arm in the way
# of whatever the scenario is actually grading.
#
# Tier first, then memory: memory records the tier as a gitlink, so committing
# memory first would pin a SHA the tier is about to move off. That ordering is
# the same one the production pre-commit hook follows.
GITLORE_MEMORY_COMMIT=1 git -C memory/acme add -A
if ! git -C memory/acme diff --cached --quiet; then
  GITLORE_MEMORY_COMMIT=1 git -C memory/acme commit -q -m "Compose acme tier index"
fi
git -C memory/acme branch -f live HEAD
git -C memory/acme checkout -q --detach live

GITLORE_MEMORY_COMMIT=1 git -C memory add -A
GITLORE_MEMORY_COMMIT=1 git -C memory commit -q -m "Mount and activate the acme tier"
git -C memory branch -f live HEAD
