#!/usr/bin/env bash
# Shared by the session-start line suites (session_start_line*.bats): running
# the hook, reading its two channels by paragraph, the line assertions, and the
# store fixtures. Needs helpers/setup, fixtures, tier-fixtures,
# divergence-fixtures, cc-hook-session-start and merge-memory loaded first.
#
# $output and $status are bats' `run` captures; shellcheck cannot see them.
# shellcheck disable=SC2154

# --- running the hook and reading its two channels ------------------------------

session_start() {
  enable_gitlore
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
}

# Paragraphs of channel $1 (sys|ctx) are split on a blank line, as the notices
# are joined. These read the hook JSON in $output. The `$c` is jq's, not the
# shell's.
# shellcheck disable=SC2016
jq_chan='(if $c == "sys" then .systemMessage else .hookSpecificOutput.additionalContext end // "")'

# Paragraphs of channel $1 equal to $2.
count_equal() { jq -r --arg c "$1" --arg l "$2" "[$jq_chan | split(\"\\n\\n\")[] | select(. == \$l)] | length" <<<"$output"; }

# Paragraphs of channel $1 matching ERE $2.
count_match() { jq -r --arg c "$1" --arg re "$2" "[$jq_chan | split(\"\\n\\n\")[] | select(test(\$re))] | length" <<<"$output"; }

# Offset of literal $2 in channel $1, -1 when absent.
offset() { jq -r --arg c "$1" --arg s "$2" "$jq_chan | (index(\$s) // -1)" <<<"$output"; }

dump() { printf '%s channel:\n%s\n' "$1" "$(jq -r --arg c "$1" "$jq_chan" <<<"$output")" >&2; }

# A store-position line, whichever store leads it: `gitlore: ` then an optional
# command opener, then a store name and a position word ending at `;`, `)` or
# the end of the line. The superseded per-store lines (`memory in sync.`,
# `tier 'x' in sync.`, `memory holds …`) do not match it.
STORE_LINE_RE='^gitlore: (Run /gitlore:(push|merge) \()?[^ ;()]+ (in sync|[0-9]+ (ahead|behind)|diverged|unreachable)(;|\)|$)'

# The line is exactly $1, once on each channel, and no other paragraph of either
# channel is a store-position line.
assert_line() {
  local ch
  for ch in sys ctx; do
    [ "$(count_equal "$ch" "$1")" = 1 ] || { printf 'want exactly one paragraph == [%s]\n' "$1" >&2; dump "$ch"; return 1; }
    [ "$(count_match "$ch" "$STORE_LINE_RE")" = 1 ] \
      || { printf 'want exactly one store-position line\n' >&2; dump "$ch"; return 1; }
  done
}

# No store-position line on either channel. Pair it with a positive assertion
# on the message the left-out store keeps.
assert_no_line() { assert_absent "$STORE_LINE_RE"; }

# No paragraph of either channel matches ERE $1.
assert_absent() {
  local ch
  for ch in sys ctx; do
    [ "$(count_match "$ch" "$1")" = 0 ] || { printf 'unexpected paragraph matching [%s]\n' "$1" >&2; dump "$ch"; return 1; }
  done
}

# Some paragraph of channel $1 matches ERE $2.
assert_present() {
  [ "$(count_match "$1" "$2")" -ge 1 ] || { printf 'no %s paragraph matches [%s]\n' "$1" "$2" >&2; dump "$1"; return 1; }
}

# The per-store position lines and D4's merge report this line replaces. T6's
# text is matched up to its `'live' — each side`, so the kept T6t/T6g messages
# (`has diverged from its remote 'live', and its rewrite record …`) do not.
OLD_LINES="memory in sync\\.|tier '[^']+' in sync\\.|has upstream facts waiting|has diverged from its remote 'live' — each side|HEAD that diverged from its local|HEAD has diverged from live|upstream memory has diverged|holds commits its remote 'live' lacks|commits? its remote's live lacks|has a HEAD ahead of its local|on live not checked out|upstream memory commits? —|memory's HEAD is [0-9]+ commits? ahead|has commits on its local 'live'|these tiers hold commits on their local 'live'"
assert_no_old_lines() { assert_absent "$OLD_LINES"; }

# --- fixtures ---------------------------------------------------------------------

# Memory published to its own remote, one tier mounted at its remote's live, and
# both level with their remotes.
synced_store() {
  wire_memory_remote
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  commit_memory_state "memory: activate the tier"
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
  assert_level_with_remotes ddaanet
}

# Memory and tier $1 (default ddaanet) hold what their remotes hold.
assert_level_with_remotes() {
  local t="${1:-ddaanet}"
  [ "$(git -C memory rev-parse live)" = "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" ]
  [ "$(git -C "memory/$t" rev-parse live)" = "$(git --git-dir="$TMP_REPO/.bare-$t.git" rev-parse live)" ]
}

# One commit on memory's HEAD, with local live following.
commit_on_head_and_live() {
  git -C memory -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local fact"
  git -C memory push -q . HEAD:refs/heads/live
}

# Commits $1 files onto tier $2's live and its remote, leaving HEAD where it is.
advance_tier_live() {
  local n="$1" t="${2:-ddaanet}" i=1
  while [ "$i" -le "$n" ]; do
    advance_branch_with_file "memory/$t" live "upstream$i.md" "fact $i" "tier fact $i"
    i=$((i + 1))
  done
  git -C "memory/$t" push -q origin live
}

# Commits $1 files onto memory's local live only, leaving HEAD and the remote.
advance_memory_live() {
  local n="$1" i=1
  while [ "$i" -le "$n" ]; do
    advance_branch_with_file memory live "live$i.md" "live $i" "live fact $i"
    i=$((i + 1))
  done
}

# Tier ddaanet's HEAD and live both one commit past a remote that has one commit
# of its own: diverged from its remote. Memory records the tier commit, so the
# pin keeps the tier where it is; memory's live follows HEAD, its remote not.
diverge_tier() {
  git -C memory/ddaanet -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local tier fact"
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  commit_memory_state "memory: record the tier commit"
  git -C memory push -q . HEAD:refs/heads/live
  push_tier_fact ddaanet >/dev/null
  git -C memory/ddaanet fetch -q origin live
  run ! git -C memory/ddaanet merge-base --is-ancestor live FETCH_HEAD
  run ! git -C memory/ddaanet merge-base --is-ancestor FETCH_HEAD live
}

# Count of commits in range $2 of store $1.
count() { git -C "$1" rev-list --count "$2"; }

# A committed, composed store with one tier, memory's remote carrying no live
# (memory reads against its local live); the tier published.
composed_store() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet kept.md "carried by both"
  seed_root_bullet "ddaanet/kept.md" "carried by both"
  gitlore_compose memory
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -q -m "tier fact"
  git -C memory/ddaanet push -q origin HEAD:refs/heads/live
  git -C memory/ddaanet update-ref refs/heads/live HEAD
  commit_memory_state
  git -C memory update-ref refs/heads/live HEAD
  [ -z "$(gitlore_compose_pending memory)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

# A root line outside a session: a pending compose.
make_compose_pending() {
  printf -- '---\nname: authored\ndescription: ""\n---\n\nbody\n' > memory/ddaanet/authored.md
  seed_root_bullet "ddaanet/authored.md" "written in the root index"
  [ -n "$(gitlore_compose_pending memory)" ]
}
