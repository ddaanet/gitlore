#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/commit-memory
load helpers/divergence-fixtures
load helpers/index-compose

# The commit path writes no index. A store whose indexes a compose pass would
# change aborts the commit, naming each such index and `gitlore-compose`, and
# leaves every file and every commit as it found them. The edit that leaves a
# store in that state was made outside a session (a human in an editor, a dead
# hook, a manifest edit in a terminal), so no batch composed it.
#
# Each case is run through both entries into the sync: `gitlore-commit`
# (commit-memory.sh) and gitlore_sync_memory_to_live called as add-tier.sh calls
# it. Each test aborts first, then settles the SAME store with gitlore_compose and
# commits it: the abort is evidence only against a store the commit then accepts.
#
# Asserted on the abort: a non-zero status, the index path, and the literal
# `gitlore-compose`. The rest of the wording is not pinned; it reaches the agent.

# --- fixtures -----------------------------------------------------------------

# Memory with a tier of three facts (a, b, c) in root and carrier alike, a
# project fact beyond them, and everything committed. $1 = "dormant" leaves the
# tier out of the manifest.
settled_store() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  if [ "${1:-}" = dormant ]; then set_tier_manifest; else set_tier_manifest ddaanet; fi
  seed_tier_bullet ddaanet a.md "first"
  seed_tier_bullet ddaanet b.md "middle"
  seed_tier_bullet ddaanet c.md "last"
  if [ "${1:-}" != dormant ]; then gitlore_compose memory >/dev/null; fi
  commit_sections "memory: settled baseline"
  [ -z "$(git -C memory status --porcelain)" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}

# A project fact written the way the write instructions describe, so the root
# store has content of its own to commit in every case.
add_project_fact() {
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  seed_root_bullet "proj.md" "a project fact"
}

# A line removed from the carrier alone, root and root at HEAD still carrying it.
pend_lost_batch() {
  settled_store
  sed -i.bak '/](b.md)/d' memory/ddaanet/MEMORY.md && rm -f memory/ddaanet/MEMORY.md.bak
  run -1 grep -qF '](b.md)' memory/ddaanet/MEMORY.md
  # A tier fact of its own, authored in both indexes, so the tier has a change to
  # commit that the restore does not undo (a restore alone leaves it clean).
  printf -- '---\nname: e\ndescription: ""\n---\n\nbody\n' > memory/ddaanet/e.md
  printf -- '- [e](e.md) — new\n' >> memory/ddaanet/MEMORY.md
  set_bullets memory/MEMORY.md \
    '- [a](ddaanet/a.md) — first' \
    '- [b](ddaanet/b.md) — middle' \
    '- [c](ddaanet/c.md) — last' \
    '- [e](ddaanet/e.md) — new'
  add_project_fact
  PENDING_INDEX=memory/ddaanet/MEMORY.md
}

# A tier line typed into the root index by hand, in the tier's block.
pend_root_line() {
  settled_store
  printf -- '---\nname: d\ndescription: ""\n---\n\nbody\n' > memory/ddaanet/d.md
  set_bullets memory/MEMORY.md \
    '- [a](ddaanet/a.md) — first' \
    '- [b](ddaanet/b.md) — middle' \
    '- [c](ddaanet/c.md) — last' \
    '- [d](ddaanet/d.md) — typed into the root' \
    '- [proj](proj.md) — a project fact'
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  PENDING_INDEX=memory/ddaanet/MEMORY.md
}

# A tier activated by a manifest edit in a terminal: its lines are not in root yet.
pend_manifest() {
  settled_store dormant
  set_tier_manifest ddaanet
  add_project_fact
  PENDING_INDEX=memory/MEMORY.md
}

# A tier line typed into the root index AND a project line typed above the tier
# block: the carrier needs the tier line, and root needs its layout put back.
pend_both() {
  settled_store
  printf -- '---\nname: d\ndescription: ""\n---\n\nbody\n' > memory/ddaanet/d.md
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  set_bullets memory/MEMORY.md \
    '- [proj](proj.md) — a project fact' \
    '- [a](ddaanet/a.md) — first' \
    '- [b](ddaanet/b.md) — middle' \
    '- [c](ddaanet/c.md) — last' \
    '- [d](ddaanet/d.md) — typed into the root'
  PENDING_INDEX=memory/ddaanet/MEMORY.md
}

# Two tiers, a line lost from the SECOND one's carrier alone: a check that stops
# at the first tier, or reads only the first carrier, sees nothing pending.
pend_second_tier() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory lore
  set_tier_manifest ddaanet lore
  seed_tier_bullet ddaanet a.md "first"
  seed_tier_bullet lore x.md "one"
  seed_tier_bullet lore y.md "two"
  seed_tier_bullet lore z.md "three"
  gitlore_compose memory >/dev/null
  commit_sections "memory: settled baseline"
  [ -z "$(git -C memory status --porcelain)" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ -z "$(git -C memory/lore status --porcelain)" ]
  sed -i.bak '/](y.md)/d' memory/lore/MEMORY.md && rm -f memory/lore/MEMORY.md.bak
  run -1 grep -qF '](y.md)' memory/lore/MEMORY.md
  # A tier fact of its own, authored in both indexes, so the tier still has a change
  # to commit once the lost line is restored (the section check names it).
  printf -- '---\nname: e\ndescription: ""\n---\n\nbody\n' > memory/lore/e.md
  printf -- '- [e](e.md) — new\n' >> memory/lore/MEMORY.md
  set_bullets memory/MEMORY.md \
    '- [a](ddaanet/a.md) — first' \
    '- [x](lore/x.md) — one' \
    '- [y](lore/y.md) — two' \
    '- [z](lore/z.md) — three' \
    '- [e](lore/e.md) — new'
  add_project_fact
  PENDING_INDEX=memory/lore/MEMORY.md
}

# Everything an aborted commit must leave alone, as one comparable text: the three
# files compose could write, both stores' status, and both stores' history.
store_snapshot() {
  local f
  for f in memory/MEMORY.md memory/*/MEMORY.md memory/.gitlore-tiers; do
    if [ -f "$f" ]; then printf '%s %s\n' "$f" "$(cksum < "$f")"; else printf '%s absent\n' "$f"; fi
  done
  git -C memory status --porcelain
  for f in memory/*/.git; do git -C "${f%/.git}" status --porcelain; done
  git -C memory log --format='%H' -n 20
  for f in memory/*/.git; do git -C "${f%/.git}" log --format='%H' -n 20; done
  git -C memory diff --cached --stat
  find memory -path '*/.git' -prune -o -type f -print | LC_ALL=C sort
}

# The entries. Each runs the commit over the store's present state and leaves its
# stderr in $stderr and its status in $status.
via_bin() {
  local summary
  summary=$(sectioned_summary "memory: record the edits")
  # shellcheck disable=SC2016 # $1 and $2 expand in the inner shell
  run --separate-stderr bash -c \
    'printf "%s\n" "$1" | "$2/bin/gitlore-commit"' _ "$summary" "$PLUGIN_ROOT"
}

via_sync() {
  local summary driver="$BATS_TEST_TMPDIR/sync-driver.sh"
  summary=$(sectioned_summary "memory: record the edits")
  cat > "$driver" <<DRIVER
#!/usr/bin/env bash
set -euo pipefail
source "$PLUGIN_ROOT/scripts/lib/util.sh"
source "$PLUGIN_ROOT/scripts/lib/log.sh"
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"
gitlore_sync_memory_to_live memory "\$1"
DRIVER
  run --separate-stderr bash "$driver" "$summary"
}

# The case, aborted and then accepted. $1 = fixture function, $2 = entry function.
abort_then_commit() {
  local pend="$1" entry="$2" before head
  "$pend"
  before=$(store_snapshot)
  head=$(git -C memory rev-parse HEAD)

  "$entry"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$PENDING_INDEX"* ]] || false
  [[ "$stderr" == *"gitlore-compose"* ]] || false
  # Untouched: files, status, history and the worktree listing, not the status alone.
  [ "$(store_snapshot)" = "$before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]

  # The same store, composed, commits.
  gitlore_compose memory >/dev/null
  "$entry"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head" ]
}

# --- the three states, through both entries -----------------------------------

@test "gitlore-commit aborts on a line deleted from a carrier outside a session" {
  abort_then_commit pend_lost_batch via_bin
}

@test "the sync aborts on a line deleted from a carrier outside a session" {
  abort_then_commit pend_lost_batch via_sync
}

@test "gitlore-commit aborts on a tier line added to the root index outside a session" {
  abort_then_commit pend_root_line via_bin
}

@test "the sync aborts on a tier line added to the root index outside a session" {
  abort_then_commit pend_root_line via_sync
}

@test "gitlore-commit aborts on a manifest edit made in a terminal" {
  abort_then_commit pend_manifest via_bin
}

@test "the sync aborts on a manifest edit made in a terminal" {
  abort_then_commit pend_manifest via_sync
}

@test "gitlore-commit names every index a compose would change, not only the first" {
  pend_both
  before=$(store_snapshot)
  via_bin
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md"* ]] || false
  # Root's own path, not the carrier's: the carrier path also contains "MEMORY.md".
  [[ "${stderr//memory\/ddaanet\/MEMORY.md/}" == *"memory/MEMORY.md"* ]] || false
  [[ "$stderr" == *"gitlore-compose"* ]] || false
  [ "$(store_snapshot)" = "$before" ]
  # The fixture really leaves both indexes pending: a compose writes each.
  run gitlore_compose memory
  [[ "$output" == *"composed memory/ddaanet/MEMORY.md"* ]] || false
  [[ "$output" == *"composed memory/MEMORY.md"* ]] || false
}

@test "gitlore-commit aborts on a line deleted from the second tier's carrier" {
  abort_then_commit pend_second_tier via_bin
}

@test "the sync aborts on a line deleted from the second tier's carrier" {
  abort_then_commit pend_second_tier via_sync
}

# --- nothing pending: the commit goes ahead -------------------------------------

@test "a settled store with a new project fact commits through both entries, with no compose text" {
  settled_store
  add_project_fact
  head=$(git -C memory rev-parse HEAD)
  via_bin
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head" ]
  [[ "$stderr" != *"gitlore-compose"* ]] || false

  printf -- '---\nname: two\ndescription: ""\n---\n\nbody\n' > memory/two.md
  seed_root_bullet "two.md" "another project fact"
  head=$(git -C memory rev-parse HEAD)
  via_sync
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head" ]
}

# --- the check is read-only for real --------------------------------------------

@test "an aborted commit writes no temp file beside an index and touches no mtime" {
  pend_lost_batch
  files=(memory/MEMORY.md memory/ddaanet/MEMORY.md memory/.gitlore-tiers)
  # Backdated, so any write after this point is newer than the reference file.
  touch -t 200001010000 "${files[@]}"
  touch -t 200001020000 "$BATS_TEST_TMPDIR/ref"
  listing=$(find memory -path '*/.git' -prune -o -type f -print | LC_ALL=C sort)

  via_bin
  [ "$status" -ne 0 ]
  [ -z "$(find "${files[@]}" -newer "$BATS_TEST_TMPDIR/ref")" ]
  [ "$(find memory -path '*/.git' -prune -o -type f -print | LC_ALL=C sort)" = "$listing" ]
  # And none left in a store's own gitdir, where gitlore_compose_write keeps its scratch.
  [ -z "$(find "$(git -C memory rev-parse --absolute-git-dir)" \
    "$(git -C memory/ddaanet rev-parse --absolute-git-dir)" -name 'gitlore-compose.tmp.*')" ]
}

# --- a refusal still follows the present rule ------------------------------------
#
# Rules 1, 4 and 6 in an index with uncommitted changes abort; the same problem in
# a clean index reports and lets the commit go ahead (tests/commit_memory.bats and
# tests/commit_memory_reports.bats pin both for the sync). Here the store ALSO has
# a pending compose: the refusal writes nothing, so it outranks the pending abort,
# and the clean-index case commits instead of aborting on the pending change.

@test "a problem in a clean index still reports and commits though a compose would also change an index" {
  settled_store
  # A duplicate pointer committed into the carrier: a rule 1 problem in an index
  # with no uncommitted change.
  printf -- '- [a](a.md) — first again\n' >> memory/ddaanet/MEMORY.md
  git -C memory/ddaanet commit -qam "carrier: a duplicate pointer"
  git -C memory add ddaanet && git -C memory commit -qm "memory: record the tier commit"
  # A root tier line typed by hand: with no refusal the compose would write the
  # carrier. The refusal writes nothing, so it, not the pending change, decides.
  seed_root_bullet "ddaanet/e.md" "typed into the root"
  head=$(git -C memory rev-parse HEAD)
  carrier=$(cksum < memory/ddaanet/MEMORY.md)
  via_bin
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head" ]
  [[ "$stderr" == *"tier composition refused"* ]] || false
  [ "$(cksum < memory/ddaanet/MEMORY.md)" = "$carrier" ]
}

@test "the same problem in a dirty index aborts, with a compose also pending" {
  settled_store
  # The duplicate is uncommitted this time, so the commit would publish it.
  printf -- '- [a](a.md) — first again\n' >> memory/ddaanet/MEMORY.md
  seed_root_bullet "ddaanet/e.md" "typed into the root"
  head=$(git -C memory rev-parse HEAD)
  before=$(store_snapshot)
  via_bin
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md"* ]] || false
  [[ "$stderr" == *"duplicate pointer"* ]] || false
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  [ "$(store_snapshot)" = "$before" ]
}

@test "a tier with a prepared merge is answered by its merge directive, not the pending compose" {
  # tests/tier_divergence.bats's prepared-merge fixture: the tier at `live`, the
  # two sides touching different files, so the gate prepares a clean merge.
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  gitlore_compose memory >/dev/null
  commit_sections "memory: record the org fact"
  merge_gate || true
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  # A pending compose beside the merge: a root tier line the carrier lacks.
  seed_root_bullet "ddaanet/e.md" "typed into the root"

  via_bin
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"memory merge prepared"* ]] || false
  [[ "$stderr" != *"gitlore-compose"* ]] || false
}

# --- bin/gitlore-compose ----------------------------------------------------------

@test "gitlore-compose writes a pending compose, reports it, and the commit then succeeds" {
  pend_lost_batch
  head=$(git -C memory rev-parse HEAD)
  via_bin
  [ "$status" -ne 0 ]

  run --separate-stderr "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"$PENDING_INDEX"* ]] || false
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [b](b.md) — middle' \
    '- [c](c.md) — last' \
    '- [e](e.md) — new'

  # No further edit: the same commit goes through.
  via_bin
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head" ]
}

@test "gitlore-compose on a composed store writes nothing and reports no index" {
  settled_store
  touch -t 200001010000 memory/MEMORY.md memory/ddaanet/MEMORY.md memory/.gitlore-tiers
  touch -t 200001020000 "$BATS_TEST_TMPDIR/ref"
  before=$(store_snapshot)
  run --separate-stderr "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
  [ "$(store_snapshot)" = "$before" ]
  [ -z "$(find memory/MEMORY.md memory/ddaanet/MEMORY.md memory/.gitlore-tiers -newer "$BATS_TEST_TMPDIR/ref")" ]
  [[ "$output$stderr" != *"MEMORY.md"* ]] || false
}

@test "gitlore-compose is resolved from its own location, like gitlore-commit" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-compose" ]
  grep -qF 'BASH_SOURCE' "$PLUGIN_ROOT/bin/gitlore-compose"
  # shellcheck disable=SC2016 # the literal text of the script's exec line
  grep -qF 'exec "$root/scripts/' "$PLUGIN_ROOT/bin/gitlore-compose"
  # shellcheck disable=SC2016 # sed program, not a shell expansion
  exec_target=$(sed -n 's|.*exec "\$root/\(scripts/[^"]*\)".*|\1|p' "$PLUGIN_ROOT/bin/gitlore-compose")
  [ -x "$PLUGIN_ROOT/$exec_target" ]
}
