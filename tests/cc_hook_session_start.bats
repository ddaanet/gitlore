#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures

SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

# The relay drain's framing line, hand-typed here rather than sourced from
# scripts/lib/index-sync.sh's gitlore_relay_drain: sourcing it would move both
# sides together and the positive case would stop pinning the actual wording.
RELAY_FRAMING="--- gitlore-relay agent"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

# What "no-op" means here, asserted as one thing so every negative below says
# it. settings.local.json is NOT it: D10 forbids writing that file on the
# enabled path too, so its absence is true either way and pins nothing. The
# config keys, the wrappers and the stdout JSON are what the enabled path
# produces, and a no-op is their absence.
assert_session_start_did_nothing() {
  [ "$status" -eq 0 ]
  [ -z "$output" ]                                  # no JSON on the CC channel
  run git config --get gitlore.hooksDir
  [ "$status" -ne 0 ]
  [ ! -e .git/gitlore-pre-commit ]
  [ ! -e .git/gitlore-pre-push ]
}

@test "no-op when there is no settings.json at all" {
  make_parent_with_memory
  run --separate-stderr bash "$SESSION_START"
  assert_session_start_did_nothing
}

@test "no-op when gitlore.enabled is false" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":false}}\n' > .claude/settings.json
  run --separate-stderr bash "$SESSION_START"
  assert_session_start_did_nothing
}

@test "a malformed settings.json no-ops but says why on the user-visible channel" {
  # Why the file-existence guard is separate from the jq read rather than folded
  # into a `2>/dev/null`: absent is the ordinary not-a-gitlore-repo case, but
  # unparseable is a fault. `enabled=$(jq ... || echo false)` used to swallow
  # jq's complaint into "false", downgrading a real fault to silent
  # "gitlore disabled" — jq's own parse error still reached stderr, but
  # SessionStart's stderr is invisible to the user outside --verbose (the
  # comment above `exec 3>&1 1>&2` below), so nowhere the user actually looks
  # said anything was wrong.
  make_parent_with_memory
  mkdir -p .claude
  printf 'this is not json\n' > .claude/settings.json
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  hook_output="$output"   # `run` below would otherwise overwrite it
  run git config --get gitlore.hooksDir
  [ "$status" -ne 0 ]
  [ ! -e .git/gitlore-pre-commit ]
  [ ! -e .git/gitlore-pre-push ]
  # The user-visible channel: SessionStart's own JSON systemMessage, not stderr.
  [[ "$(printf '%s' "$hook_output" | jq -r '.systemMessage')" == *"could not be parsed"* ]]
}

@test "no-op when .gitmodules has no gitlore-memory entry" {
  mkdir .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run --separate-stderr bash "$SESSION_START"
  assert_session_start_did_nothing
}

@test "does not write settings.local.json (D10); sets hooksDir and emits wrappers" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -f .claude/settings.local.json ]
  [ "$(git config gitlore.hooksDir)" = "$CLAUDE_PLUGIN_ROOT/scripts/git-hooks" ]
  [ "$(git config gitlore.commitCommand)" = "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" ]
  [ "$(git config gitlore.pushCommand)" = "$CLAUDE_PLUGIN_ROOT/scripts/push-memory.sh" ]
  [ "$(git config gitlore.mergeCommand)" = "$CLAUDE_PLUGIN_ROOT/scripts/merge-memory.sh" ]
  [ "$(git config gitlore.memoryApprovalClauseFile)" = "$CLAUDE_PLUGIN_ROOT/reference/memory-approval-clause.txt" ]
  [ -x .git/gitlore-pre-commit ]
  [ -x .git/gitlore-pre-push ]
}

@test "emits launcher-guard JSON on stdout when GITLORE_LAUNCHED is unset" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  unset GITLORE_LAUNCHED
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("direnv allow")'
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("GITLORE_LAUNCHED")'
}

@test "clean launched session: success confirmation on systemMessage, no launcher warning (D14)" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # D14 always-confirm: a clean start rides a success confirmation on systemMessage...
  echo "$output" | jq -e '.systemMessage | test("ready")'
  echo "$output" | jq -e '.systemMessage | test("detached at live")'
  # ...and it is NOT the launcher warning (shim ran).
  echo "$output" | jq -e '.systemMessage | test("direnv allow") | not'
  # The standing commit-protocol orientation (Fix B) is always present.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("memory submodule")'
  # A store WITH a root index gets no repair and no repair notice.
  echo "$output" | jq -e '.systemMessage | test("no root MEMORY.md") | not'
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a store with no root MEMORY.md gets the scaffold as a dirty file, and says so (D14)" {
  # An install seeded from an auto-memory dir that existed but held nothing
  # used to commit an empty tree: no root index for a tier to compose into,
  # nothing for a merge continuation to stage. Every path downstream assumes
  # the scaffold exists, so SessionStart writes it back — as an uncommitted
  # file the next FR11 commit reviews, never as a commit of its own.
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  # Live and the detached HEAD both lack the index, so the ff-merge has nothing
  # to restore it from and the working tree is clean before the hook runs.
  git -C memory rm -q MEMORY.md
  GITLORE_MEMORY_COMMIT=1 git -C memory -c user.email=t@t -c user.name=t commit -q -m "no index"
  git -C memory update-ref refs/heads/live HEAD
  before=$(git -C memory rev-parse HEAD)
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(head -1 memory/MEMORY.md)" = "# Memory Index" ]
  # Untracked, not committed: HEAD did not move, and status reports the file.
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
  [ "$(git -C memory status --porcelain -- MEMORY.md)" = "?? MEMORY.md" ]
  echo "$output" | jq -e '.systemMessage | test("no root MEMORY.md")'
  echo "$output" | jq -e '.systemMessage | test("detached at live")'
}

@test "emits standing commit-protocol additionalContext every gitlore session" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # The prohibition (the one piece that must precede any action) is present...
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("never commit"; "i")'
  # ...along with the one-line seamless happy path (commit the parent; hook handles it).
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("PARENT repo"; "i")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("seamless"; "i")'
  # ...but the four-step persist *procedure* is NOT front-loaded — it is surfaced
  # just-in-time by the pre-commit hook / gitlore:resolve, not the always-on context.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("explicit user approval"; "i") | not'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("rev-parse --git-path gitlore-commit-msg"; "i") | not'
}

@test "wires the submodule commit gate (memory-pre-commit) into the submodule hooks dir" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  hookfile="$(git -C memory rev-parse --git-path hooks)/pre-commit"
  [ -x "$hookfile" ]
  # And it must actually block a naked direct commit.
  echo dirty > memory/notes.md
  git -C memory add -A
  CLAUDECODE=1 run --separate-stderr git -C memory commit -m "direct"
  [ "$status" -ne 0 ]
  [[ "${output}${stderr}" == *"blocked"* ]]
}

@test "detaches memory HEAD when it arrives on a named branch" {
  # Migration path off the retired per-parent-branch model: a memory worktree
  # left attached to a branch must come back detached, at the same commit.
  make_parent_with_memory
  (cd memory && git checkout -q -b legacy-branch)
  before=$(git -C memory rev-parse HEAD)
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  run git -C memory symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
}

@test "parent branch named 'live' is no longer a collision" {
  # The old model named memory's working branch after the parent branch, so a
  # parent on 'live' collided with the memory trunk. Detached HEADs cannot.
  make_parent_with_memory
  git checkout -q -b live
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("collides|rename"; "i")' && return 1
  echo "$output" | jq -e '.systemMessage | test("memory ready")'
}

@test "ff-merges detached memory HEAD to live when clean" {
  make_parent_with_memory
  # Advance live ahead of the detached HEAD.
  advance_branch_with_file memory live EXTRA.md extra "Advance live"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  bash "$SESSION_START"
  # After SessionStart, the detached HEAD should sit at the live tip.
  [ "$(git -C memory rev-parse live)" = "$(git -C memory rev-parse HEAD)" ]
}

@test "warns and skips ff when memory is dirty via systemMessage (D14)" {
  make_parent_with_memory
  echo dirty > memory/scratch.md
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("uncommitted")'
}

@test "diverged memory reports via systemMessage, exit 0 (D14)" {
  make_parent_with_memory
  make_diverged_head_vs_live
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("diverged")'
  echo "$output" | jq -e '.systemMessage | test("resolve")'
}

@test "a ff-only merge failure that is NOT divergence reports git's own reason, not a guessed 'diverged'" {
  # Regression for the blanket `2>&1` this hook used to carry on the ff-only
  # merge: a lock, a corrupt object, or an unwritable worktree all refuse
  # --ff-only the same way a genuine divergence does, and sending the user to
  # /gitlore:resolve for any of them replaces git's own explanation with a
  # guess. Force a real, non-divergence failure: HEAD is strictly BEHIND live
  # (an ordinary fast-forward would succeed) but a stranded index.lock in
  # memory's own gitdir blocks the merge from writing.
  export GITLORE_GIT_RETRY_SCHEDULE="0 0 0 0 0 0 0"
  make_parent_with_memory
  advance_branch_with_file memory live EXTRA.md extra "Advance live"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json

  mem_gitdir=$(git -C memory rev-parse --git-dir)
  : > "$mem_gitdir/index.lock"
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  rm -f "$mem_gitdir/index.lock"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("could not be fast-forwarded")'
  run bash -c "echo \"\$1\" | jq -e '.systemMessage | test(\"diverged\")'" _ "$output"
  [ "$status" -ne 0 ]
  # HEAD never advanced — the merge genuinely did not happen.
  [ "$(git -C memory rev-parse live)" != "$(git -C memory rev-parse HEAD)" ]
}

@test "dangling index pointers: one capped systemMessage + a capped additionalContext (D14)" {
  make_parent_with_memory
  # Seven root pointers whose target files do not exist — a dangling report
  # longer than the 5-line cap. It must arrive as ONE notice that lists five and
  # counts the rest, on BOTH the user channel (systemMessage) and the agent
  # channel (additionalContext), never the full flood the raw report would be.
  for i in 1 2 3 4 5 6 7; do
    printf -- '- [missing %s](gone_%s.md) — a hook\n' "$i" "$i" >> memory/MEMORY.md
  done
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # systemMessage: names the count, lists exactly five targets, summarizes the rest.
  echo "$output" | jq -e '.systemMessage | test("points at 7 missing files")'
  echo "$output" | jq -e '.systemMessage | test("… and 2 more")'
  [ "$(echo "$output" | jq -r '.systemMessage' | grep -c 'names no file')" -eq 5 ]
  # additionalContext: the agent is told the index is stale — also capped, so the
  # always-loaded index it is about to trust is not silently believed.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("STALE")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("… and 2 more")'
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -c 'names no file')" -eq 5 ]
}

@test "sentinel 'direct' re-applies direct wiring" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'direct\n' > .claude/gitlore-hook-setup
  bash "$SESSION_START"
  grep -q '# gitlore: managed' .git/hooks/pre-commit
}

@test "sentinel 'manual' emits a reminder to stderr" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'manual\n' > .claude/gitlore-hook-setup
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"manual"* ]]
}

@test "an unrecognized sentinel is NOT executed as a shell command (W8)" {
  # `.claude/gitlore-hook-setup` is a TRACKED file — a fresh clone brings
  # whatever its first line says, and an unconstrained `sh -c "$cmd"` on it
  # would run any line that clone carried at the very first session start.
  # Only the three known hook-manager installers are legitimate `*)` content
  # (wire-lefthook.sh/wire-husky.sh/wire-overcommit.sh are the only writers);
  # anything else must be reported, never executed.
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'touch %s/pwned\n' "$TMP_REPO" > .claude/gitlore-hook-setup
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP_REPO/pwned" ]
  echo "$output" | jq -e '.systemMessage | test("gitlore-hook-setup")'
}

@test "creates the memory worktree detached at live in a linked (CC-created) worktree" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
  # git populates the gitlink dir but does not check out the submodule:
  [ ! -e "$WT/memory/.git" ]
  mkdir -p "$WT/.claude"
  printf '{"gitlore":{"enabled":true}}\n' > "$WT/.claude/settings.json"

  CLAUDE_PROJECT_DIR="$WT" GITLORE_LAUNCHED=1 run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ -e "$WT/memory/.git" ]
  # Detached at live — the reason one memory gitdir can serve many parent
  # worktrees at once (a named branch could only be checked out in one).
  run git -C "$WT/memory" symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  [ "$(git -C "$WT/memory" rev-parse HEAD)" = "$(git -C "$WT/memory" rev-parse live)" ]
}

@test "session-start drains a stranded relay marker" {
  # A subagent's PostToolBatch hook staged a report to its own marker and the
  # session ended before any parent-side batch drained it.
  # SessionStart is the backstop: it must fold the marker's two channels into
  # its own systemMessage / additionalContext and remove the marker.
  make_parent_with_memory
  # Bare helper call under bats' own errexit: capture status explicitly rather
  # than let a write failure abort the test with no named assertion.
  if gitlore_relay_write memory a1 "STRANDED SYSMSG BODY" "STRANDED CTX BODY"; then
    write_status=0
  else
    write_status=$?
  fi
  [ "$write_status" -eq 0 ]
  marker="$(gitlore_relay_marker_file memory a1)"
  [ -f "$marker" ]
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  sysmsg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$sysmsg" == *"STRANDED SYSMSG BODY"* ]]
  [[ "$sysmsg" == *"$RELAY_FRAMING a1 ---"* ]]
  [[ "$ctx" == *"STRANDED CTX BODY"* ]]
  [[ "$ctx" == *"$RELAY_FRAMING a1 ---"* ]]
  [ ! -f "$marker" ]
}

@test "session-start with no marker emits no relay framing" {
  # The negative that keeps the positive above honest, over the same fixture
  # differing only in whether a marker exists.
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  sysmsg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  # `jq -r` prints the literal "null" for a key that is not there, so both
  # refutations below would pass on a JSON that had dropped the channel
  # entirely — the negative would keep counting as green while watching
  # nothing. Pin that each channel is present first: the positive above proves
  # this is an observable the drain path really writes to.
  [ "$sysmsg" != "null" ]
  [ "$ctx" != "null" ]
  [[ "$sysmsg" != *"$RELAY_FRAMING"* ]]
  [[ "$ctx" != *"$RELAY_FRAMING"* ]]
}

# Item 3.1 slice 4, Group A (item-3-1-s3-code-review.md "Concern 1", the
# SessionStart half of the shared fixture in tests/index_sync.bats). A marker
# at mode 0200 is found by the drain's `find -type f` but cannot be opened by
# its `awk`, which exits 2 — and under this file's own `set -euo pipefail`
# that used to take the whole hook down before slice 3's `|| true` landed.
# What that fix does NOT restore is the body: the marker is folded as an
# empty block and removed, so only the drain's own return code is protected.
# This case pins the residual: the hook must still finish and still carry
# everything ELSE accumulated above the fold — the standing FR11
# commit-protocol context most of all, since losing it costs every session
# after this one, not just this batch's relay.
@test "an unreadable marker costs the relay, not the hook" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  if gitlore_relay_write memory a1 "STRANDED SYSMSG BODY" "STRANDED CTX BODY"; then
    write_status=0
  else
    write_status=$?
  fi
  [ "$write_status" -eq 0 ]
  marker="$(gitlore_relay_marker_file memory a1)"
  chmod 0200 "$marker"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  # Restore only if the drain (or the mutation-red run below) left the marker
  # behind — the fixed drain's own `rm -f` removes it regardless of its mode,
  # since deletion depends on the containing directory's permissions, not the
  # target file's.
  [ -e "$marker" ] && chmod 0600 "$marker"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("never commit"; "i")'
}

# A third case — "a stranded marker is the only thing SessionStart has to
# say" — is in the runbook item (emit_session_json omits systemMessage
# entirely when $sysmsg is empty, so a fold placed after that decision, or one
# appending to the wrong variable, would leave the relay unemitted on exactly
# the session where it is the only news). No fixture reaches emit_session_json
# with $sysmsg empty: every branch of the `gitlore_memory_dirty` if/elif/else
# at session-start.sh:193-212 calls add_sysmsg before falling through (or
# before its own early emit_session_json + exit 0) — "memory ready", "…
# uncommitted changes…", "diverged", or "could not be fast-forwarded" — and
# every path that reaches the bottom of the script passed through exactly one
# of those branches. A guard-failure fixture (no settings.json, disabled,
# unregistered submodule) exits before mempath is even resolved and emits no
# JSON at all (assert_session_start_did_nothing), not an empty-systemMessage
# JSON. So $sysmsg is unconditionally non-empty at every emit_session_json
# call site this hook has today, and a case asserting the relay alone drives
# systemMessage would be vacuous by construction — not a red, a tautology.
# Measured, not read: an instrumented emit_session_json driven by every fixture
# in this suite and the nine others that run the hook logged 52 emits across
# all three call sites, none with $sysmsg empty.
#
# The case is also not NEEDED for the two bugs it was specified to catch. A
# fold placed after emit_session_json, and one appending to the wrong variable,
# each red the positive above on its first assertion. What no case here pins —
# and what today's code cannot tell apart from correct — is a fold nested
# inside an `[ -n "$sysmsg" ]` guard: behaviour-identical while all four dirty
# branches report, and silently dropping the relay the day one stops.
