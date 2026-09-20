# Shared setup for the tests/resolve_recovery*.bats suites: the script paths,
# the tmp-repo/memory fixture, and the tier-merge preparation helper the
# landed-tier-merge suites both call.

# shellcheck disable=SC2034   # used by callers' @test bodies
RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"
PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}
teardown() { teardown_tmp_repo; }

# Item 1.3 slice 1: gitlore_recover_landed_merge stages the gitlink it
# moved, in the store that recorded it, so a memory commit right after does not
# meet the pin guard on a tier gitlore itself just left ahead.
#
# Both rc-0 branches leave the STORE's own gitdir clean (its own MERGE_HEAD and
# merge-state file are gone), but neither touches the ENCLOSING store's index —
# so a tier recovered this way looks, to the pin guard, exactly like one moved
# off its pin by hand. Every fixture below diverges a tier from its own `live`
# and prepares the merge through the real hook — precedent:
# tests/tier_divergence.bats "pre-commit prepares a merge when a tier commit
# diverged from its own live" — then lands it with a bare `git commit --no-edit`
# rather than through /gitlore:merge's own continuation, which is what leaves
# the moved gitlink unstaged in memory's index (D43 only covers the normal
# advancing path).
# $status is bats' `run` variable, consumed within this same call.
# shellcheck disable=SC2154
tier_prepare_head_vs_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  set_tier_manifest "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
  advance_branch_with_file "memory/$tier" live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> "memory/$tier/MEMORY.md"
  printf 'memory: record the org fact\n' > "$(gitlore_commit_msg_file memory)"
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [ -n "$(git -C "memory/$tier" rev-parse -q --verify MERGE_HEAD)" ]
}
