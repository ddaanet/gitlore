#!/usr/bin/env bats
# SessionStart over a root memory store that holds a prepared merge (no-pin-loop
# plan, "Design" and "What the probes add"). The root has no report of its own
# today, and a merge prepared by a take or a push is not a divergence the user
# can act on with /gitlore:resolve or /gitlore:push, which would only meet it
# again. The report names the command that completes the merge
# (`resolve.sh continue-after-merge`, the same for both flavors) and the one
# that aborts it. The abort restores the store: it reads refs/gitlore/pending,
# tolerates a missing MERGE_HEAD, checks the pending commit out detached and
# drops the merge preparation, and it reports an untracked file a merger left
# without removing it.
#
# The plan names no entry point for the abort, so the tests run whichever
# command the report prints. A command is a line of the report that, after an
# optional `gitlore:` prefix and indentation, starts with `cd "<dir>" && ` — the
# shape the merge directive already gives its continuation. The continuation is
# the one containing `continue-after-merge`; the abort is the other.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory

# --- fixtures -----------------------------------------------------------------

# Root diverged from its remote: a root-only commit and an upstream commit. One
# take prepares the merge and yields. Leaves $head0 (HEAD before the take),
# $live0 and $statefile.
root_merge_prepared_against_remote() {
  wire_memory_remote
  printf 'local only\n' > memory/local-only.md
  git -C memory add local-only.md
  git -C memory commit -qm "a root-only fact"
  git -C memory push -q . HEAD:refs/heads/live
  push_memory_fact
  head0=$(git -C memory rev-parse HEAD)
  live0=$(git -C memory rev-parse live)
  run bash "$CMD"
  [ "$status" -ne 0 ]
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "head-vs-remote" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
}

# HEAD forked from local live, no remote involved: the head-vs-live flavor.
root_merge_prepared_against_live() {
  wire_memory_remote
  make_diverged_head_vs_live
  head0=$(git -C memory rev-parse HEAD)
  live0=$(git -C memory rev-parse live)
  run bash "$CMD"
  [ "$status" -ne 0 ]
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "head-vs-live" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
}

# Run SessionStart; $sys and $ctx are the two channels.
session_start_over_store() {
  enable_gitlore
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  sys=$(jq -r '.systemMessage // ""' <<<"$output")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$output")
}

# The command lines of a report text ($1): `cd "<dir>" && ...`, the optional
# `gitlore:` prefix and the indentation removed.
report_commands() {
  printf '%s\n' "$1" \
    | sed -n 's/^[[:space:]]*\(gitlore:[[:space:]]*\)\{0,1\}\(cd "[^"]*" && .*\)$/\2/p'
}

# Set $complete_cmd and $abort_cmd from the agent's channel. Fails, printing
# what was found, unless there is exactly one of each.
find_report_commands() {
  local cmds
  cmds=$(report_commands "$ctx")
  complete_cmd=$(printf '%s\n' "$cmds" | grep -F 'continue-after-merge' | head -n 1 || true)
  abort_cmd=$(printf '%s\n' "$cmds" | grep -vF 'continue-after-merge' | head -n 1 || true)
  [ -n "$complete_cmd" ] || { printf 'no command completing the merge in the report; additionalContext:\n%s\n' "$ctx" >&2; return 1; }
  [ -n "$abort_cmd" ] || { printf 'no command aborting the merge in the report; commands found:\n%s\n' "$cmds" >&2; return 1; }
}

# What a prepared merge changes and an abort must undo.
merge_fingerprint() {
  printf 'HEAD %s\nlive %s\nMERGE_HEAD %s\npending %s\nstate %s\n' \
    "$(git -C memory rev-parse HEAD)" "$(git -C memory rev-parse live)" \
    "$(git -C memory rev-parse -q --verify MERGE_HEAD || echo none)" \
    "$(git -C memory rev-parse -q --verify refs/gitlore/pending || echo none)" \
    "$([ -f "$(git -C memory rev-parse --git-path gitlore-merge-state)" ] && echo present || echo none)"
  git -C memory status --porcelain
}

# --- the report ----------------------------------------------------------------

@test "SessionStart over a root merge prepared against the remote names the command that completes it, on both channels" {
  root_merge_prepared_against_remote
  session_start_over_store
  [[ "$sys" == *"continue-after-merge"* ]] || {
    printf 'the user is not told how to complete the merge; systemMessage:\n%s\n' "$sys" >&2
    return 1
  }
  [[ "$ctx" == *"continue-after-merge"* ]]
  [[ "$ctx" == *"resolve.sh"* ]]
}

@test "SessionStart over a root merge prepared against local live names the command that completes it" {
  root_merge_prepared_against_live
  session_start_over_store
  [[ "$ctx" == *"continue-after-merge"* ]] || {
    printf 'the agent is not told how to complete the merge; additionalContext:\n%s\n' "$ctx" >&2
    return 1
  }
}

@test "SessionStart over a prepared root merge names a second command that aborts it" {
  root_merge_prepared_against_remote
  session_start_over_store
  find_report_commands
  [ "$abort_cmd" != "$complete_cmd" ]
  [[ "$sys$ctx" == *[Aa]bort* ]] || {
    printf 'the report never says which command aborts; additionalContext:\n%s\n' "$ctx" >&2
    return 1
  }
}

@test "passing pin: SessionStart over a prepared root merge moves nothing" {
  root_merge_prepared_against_remote
  before=$(merge_fingerprint)
  session_start_over_store
  [ "$(merge_fingerprint)" = "$before" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
}

# --- the commands the report names ---------------------------------------------

@test "the completing command the report names lands the merge" {
  root_merge_prepared_against_remote
  session_start_over_store
  find_report_commands
  # The merger's own step, then the command verbatim.
  git -C memory add -A
  run --separate-stderr bash -c "$complete_cmd"
  [ "$status" -eq 0 ] || { printf 'completing command failed (%s):\n%s\n' "$status" "$stderr" >&2; return 1; }
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ ! -f "$statefile" ]
  [ "$(git -C memory rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = "3" ]
}

@test "the aborting command the report names restores the store, for a merge prepared against the remote" {
  root_merge_prepared_against_remote
  session_start_over_store
  find_report_commands
  run --separate-stderr bash -c "$abort_cmd"
  [ "$status" -eq 0 ] || { printf 'abort failed (%s):\n%s\n' "$status" "$stderr" >&2; return 1; }
  [ "$(git -C memory rev-parse HEAD)" = "$head0" ] || {
    printf 'HEAD is %s, not the %s the merge was prepared from\n' "$(git -C memory rev-parse HEAD)" "$head0" >&2
    return 1
  }
  [ "$(git -C memory rev-parse live)" = "$live0" ]
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ -z "$(git -C memory rev-parse -q --verify refs/gitlore/pending)" ]
  [ ! -f "$statefile" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ -f memory/local-only.md ]
  [ ! -e memory/REMOTE.md ]
}

@test "the aborting command the report names restores the store, for a merge prepared against local live" {
  root_merge_prepared_against_live
  session_start_over_store
  find_report_commands
  run --separate-stderr bash -c "$abort_cmd"
  [ "$status" -eq 0 ] || { printf 'abort failed (%s):\n%s\n' "$status" "$stderr" >&2; return 1; }
  [ "$(git -C memory rev-parse HEAD)" = "$head0" ]
  [ "$(git -C memory rev-parse live)" = "$live0" ]
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ -z "$(git -C memory rev-parse -q --verify refs/gitlore/pending)" ]
  [ ! -f "$statefile" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "the abort tolerates an interrupted preparation that left no MERGE_HEAD" {
  root_merge_prepared_against_remote
  # What a preparation killed after the checkout leaves: the state file, the
  # pending ref and HEAD on the authority, with the merge itself gone.
  git -C memory merge --abort
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ -f "$statefile" ]
  [ "$(git -C memory rev-parse HEAD)" != "$head0" ]
  session_start_over_store
  find_report_commands
  run --separate-stderr bash -c "$abort_cmd"
  [ "$status" -eq 0 ] || { printf 'abort failed (%s):\n%s\n' "$status" "$stderr" >&2; return 1; }
  [ "$(git -C memory rev-parse HEAD)" = "$head0" ]
  [ -z "$(git -C memory rev-parse -q --verify refs/gitlore/pending)" ]
  [ ! -f "$statefile" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "the abort reports an untracked file a merger left and does not remove it" {
  root_merge_prepared_against_remote
  printf 'synthesized\n' > memory/synth-new.md
  session_start_over_store
  find_report_commands
  run --separate-stderr bash -c "$abort_cmd"
  [ "$status" -eq 0 ] || { printf 'abort failed (%s):\n%s\n' "$status" "$stderr" >&2; return 1; }
  [ -f memory/synth-new.md ]
  [ "$(cat memory/synth-new.md)" = "synthesized" ]
  [[ "$output$stderr" == *"synth-new.md"* ]] || {
    printf 'the abort never names the file it left:\n%s\n%s\n' "$output" "$stderr" >&2
    return 1
  }
  [ "$(git -C memory rev-parse HEAD)" = "$head0" ]
}
