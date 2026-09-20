# Shared setup for the resolve-compose split: hook/script paths, the
# tier-merge preparation helpers, and the fixtures that diverge a store's root
# index or mount a tier detached on `live`.

PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"
PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"
# shellcheck disable=SC2034   # used by callers' @test bodies
RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

approve() { printf '%s\n' "$1" > "$(gitlore_commit_msg_file memory)"; }

mount_tier_at_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
}

# Commit $1 as the root index on the detached memory HEAD, then move `live`
# sideways — the head-vs-live shape, carrying the index the merge must compose.
diverge_memory_with_index() {
  printf '%s\n' "$1" > memory/MEMORY.md
  (
    cd memory || exit 1
    git add -A
    GITLORE_MEMORY_COMMIT=1 git -c user.email=t@t -c user.name=t commit -q -m "Pending index"
  )
  advance_branch_with_file memory live LIVE.md live-side "Live commit"
  echo parent > parent-file
  git add parent-file
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

# Prepare a tier merge and synthesize it, leaving the continuation to run. Both
# sides add a line to the carrier, so the landed merge holds text root lacks.
# $1 = the command whose refusal prepares the merge (default: pre-push).
prepare_tier_merge_with_new_lines() {
  local preparer="${1:-$PRE_PUSH}"
  make_parent_with_memory
  # The fixture's memory remote has no `live` yet, and a take fetches it.
  git -C memory push -q origin live
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact ddaanet "- [their fact](t.md) — theirs" >/dev/null
  bash "$preparer" && return 1
  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [org fact](f.md) — ours\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A
}
