#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/cc-hook-memory-commit-batch
load helpers/hook-guard

@test "no-op (exit 0, silent) when gitlore is not configured" {
  # The commit fixture minus exactly the memory submodule: an approved summary
  # and a trigger are both waiting, so but for the configuration gate this batch
  # would act and speak. With no trigger written the run reaches the no-trigger
  # branch and comes out silent whether the gate is there or not.
  mkdir -p "$(dirname "$(gitlore_commit_trigger_file memory)")"
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]   # and nothing was consumed
}

@test "no-op when no trigger file is present" {
  make_parent_with_memory
  echo dirty > memory/notes.md   # dirty, but nobody asked us to commit
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -n "$(git -C memory status --porcelain)" ]   # memory untouched
}

@test "trigger + approved summary commits memory, advances live, consumes both files" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory committed"* ]]
  # The agent asked for this commit and cannot see systemMessage (D14), so the
  # outcome it would otherwise go and check for itself rides the model channel,
  # carrying the new memory HEAD and standing the agent down from confirming it.
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$(git -C memory log -1 --format='%h %s')"* ]]
  [[ "$agent" == *"do not run git status"* ]]

  # Memory committed and live advanced.
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record notes" ]
  # Both IPC files consumed.
  [ ! -f "$(gitlore_commit_trigger_file memory)" ]
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
}

@test "trigger without an approved summary keeps the trigger so it self-heals" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"no approved summary"* ]]
  [[ "$output" == *"$(gitlore_commit_msg_file memory)"* ]]
  [[ "$output" == *blockquote* ]]   # present as a draft (> ...), not a code fence
  # The instruction is addressed to the agent, so it must reach the agent.
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$(gitlore_commit_msg_file memory)"* ]]
  [[ "$agent" == *blockquote* ]]
  # Nothing committed, and the trigger is KEPT: the moment the summary is
  # written, the next batch commits transparently (no re-trigger needed).
  [ -n "$(git -C memory status --porcelain)" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
}

@test "pending-summary message interpolates the canonical memory-approval clause" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  : > "$(gitlore_commit_trigger_file memory)"
  clause=$(cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt")

  run run_batch
  [ "$status" -eq 0 ]
  # Multi-line clause: it survives only through jq's escaping, so both channels
  # are decoded before matching. A raw-$output match would test the escaping,
  # not the wording.
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$clause"* ]]
  user="$(echo "$output" | jq -r '.systemMessage // ""')"
  [[ "$user" == *"$clause"* ]]
}

@test "a locked repo keeps both IPC files so the next batch retries transparently" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  # Simulate a held index lock — an expected transient. Don't actually sleep out
  # the retry backoff.
  export GITLORE_GIT_RETRY_SCHEDULE="0 0"
  : > "$(git -C memory rev-parse --git-dir)/index.lock"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"retry"* ]]
  # The retry is automatic; a blind agent either sits on it or re-triggers
  # pointlessly, so say both on the channel it reads.
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"deferred"* ]]
  [[ "$agent" == *"re-trigger"* ]]
  # Nothing committed, and BOTH files survive for the next attempt — no lost
  # approval, no agent action required.
  [ -n "$(git -C memory status --porcelain)" ]
  # These document the consequence the report states; they hold on the
  # untouched tree too and do not test the hook.
  [ -f "$(gitlore_commit_trigger_file memory)" ]
  [ -f "$(gitlore_commit_msg_file memory)" ]
}

@test "a blank approval file is no approval and does not become a per-batch retry loop" {
  # An all-whitespace file is non-empty, so `-s` admits it, and `git commit -F`
  # then rejects it as an empty message on an arm that restamps the approval —
  # every later batch reproducing the identical refusal under "no action is
  # needed from you". Screened at the hook, so the run is never reached.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile="$(gitlore_commit_msg_file memory)"
  printf '\n' > "$msgfile"
  : > "$(gitlore_commit_trigger_file memory)"
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"no approved summary exists yet"* ]]
  # git's own words are what the unscreened path emits, on a branch that tells
  # the agent to sit still; the discriminating negative for this fix.
  [[ "$agent" != *"empty commit message"* ]]
  [[ "$agent" != *"no action is needed from you"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
}

@test "a refusal that needs a fix keeps both IPC files and hands the agent the fix" {
  # A welded line in root's changed index aborts the commit: a retry alone
  # never lands it, so the agent must read that the reason names a fix.
  make_parent_with_memory
  printf -- '- [A](a.md) — a- [B](b.md) — b\n' >> memory/MEMORY.md
  printf 'memory: record a and b\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"deferred"* ]]
  [[ "$agent" == *"When the reason below names a fix, make it"* ]]
  [[ "$agent" == *"welds two pointer bullets"* ]]
  [[ "$agent" == *"aborted"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
  [ -f "$(gitlore_commit_msg_file memory)" ]
}

@test "a fix after an aborting index does not commit under the old approval" {
  # The welded-index abort restamps the approval to "now" (D50). If the retry
  # then reads that restamp as fresh, an edit that only fixes the weld commits
  # under a summary that never saw the fix — the defect this slice closes.
  make_parent_with_memory
  printf -- '- [A](a.md) — a- [B](b.md) — b\n' >> memory/MEMORY.md
  msgfile="$(gitlore_commit_msg_file memory)"
  printf 'memory: record a and b\n' > "$msgfile"
  : > "$(gitlore_commit_trigger_file memory)"
  head_before=$(git -C memory rev-parse HEAD)

  # First batch: the existing fix-needed abort, reused here as setup.
  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"aborted"* ]]
  [[ "$agent" == *"welds two pointer bullets"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]

  # The agent repairs the weld: the two bullets on separate lines. That write
  # lands in the store and must outdate the approval — so the approval is
  # backdated first, since the abort above just restamped it to now.
  touch -t 200001010000 "$msgfile"
  printf '# memory\n- [A](a.md) — a\n- [B](b.md) — b\n' > memory/MEMORY.md
  cp "$msgfile" "$BATS_TEST_TMPDIR/approval.before"
  # Whole-second mtimes: the marker sits a second before the run, so a restamp
  # of the approval leaves it newer. The abort arms restamp with `touch
  # "$msgfile"` (D50); this branch must not, because a restamp re-mints the
  # approval and the batch after this one commits under the old summary — the
  # defect itself, and invisible to the third batch below, which rewrites the
  # file first. The bytes are asserted too: the stale file is the text the agent
  # re-presents.
  : > "$TMP_REPO/before-second-batch"
  sleep 1

  # Second batch: the fix landed, but the approval no longer covers what is
  # now in the store — the retry must not commit under it.
  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ -n "$(git -C memory status --porcelain)" ]   # and the fix was not discarded
  [ -f "$(gitlore_commit_trigger_file memory)" ]
  [ -f "$msgfile" ]
  cmp -s "$msgfile" "$BATS_TEST_TMPDIR/approval.before"
  [ ! "$msgfile" -nt "$TMP_REPO/before-second-batch" ]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"no longer covers"* ]]
  clause=$(cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt")
  [[ "$agent" == *"$clause"* ]]
  # Not the transient-retry branch's own phrase (freshness `yes`) — `deferred`
  # alone doesn't discriminate, since this branch's systemMessage carries it too.
  [[ "$agent" != *"retries by itself"* ]]
  user="$(echo "$output" | jq -r '.systemMessage // ""')"
  [ "$user" = "gitlore: memory commit deferred — the approved summary no longer covers the store, approval needed again" ]

  # Once re-approved, the next batch commits normally. The subject is asserted
  # against the rewritten text: HEAD moving alone is also what a commit under
  # the *original* approval looks like.
  printf 'memory: record a and b (fixed)\n' > "$msgfile"
  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record a and b (fixed)" ]
  [ ! -f "$(gitlore_commit_trigger_file memory)" ]
  [ ! -f "$msgfile" ]
}

@test "trigger on clean memory reports nothing to commit and consumes both IPC files" {
  # The summary goes with the trigger: it covers a store with nothing pending,
  # the next dirty episode needs its own approval, and the message stands the
  # agent down from looking — which it can only do if both files are really gone.
  make_parent_with_memory
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"already clean"* ]]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"nothing to commit"* ]]
  [[ "$agent" == *"both IPC files have been removed"* ]]
  [ ! -f "$(gitlore_commit_trigger_file memory)" ]
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
}

@test "a trigger written against another root is reported, not silently skipped" {
  # The handoff probe resolves the IPC dir from `git rev-parse --show-toplevel`
  # of the session cwd; this hook resolves it from CLAUDE_PROJECT_DIR. In a
  # linked worktree those disagree — CC chdirs into the worktree but leaves
  # CLAUDE_PROJECT_DIR at the launch repo — so the approved summary and trigger
  # land in the worktree's .claude/ while the hook reads the launch repo's, and
  # `[ -f "$trigger" ] || exit 0` made that a silent no-op: the user approved a
  # commit that never happened and nothing said so.
  make_parent_with_memory
  echo dirty > memory/notes.md
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null
  mkdir -p "$WT/.claude"
  printf 'memory: record notes\n' > "$WT/.claude/gitlore-memory-message"
  : > "$WT/.claude/gitlore-commit-memory"

  CLAUDE_PROJECT_DIR="$TMP_REPO" run run_batch "$WT"
  [ "$status" -eq 0 ]
  # Both roots named, on both channels: the user needs to know the approval did
  # not land, and the agent needs the two paths to move the files itself.
  [[ "$output" == *"$WT/.claude/gitlore-commit-memory"* ]]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$WT/.claude/gitlore-commit-memory"* ]]
  [[ "$agent" == *"$(gitlore_commit_trigger_file memory)"* ]]
  [[ "$agent" == *"$(gitlore_commit_msg_file memory)"* ]]
  # Reported, not acted on: this hook commits the project root's memory, and a
  # trigger from another working tree is not authority to do that.
  [ -n "$(git -C memory status --porcelain)" ]
  [ -f "$WT/.claude/gitlore-commit-memory" ]
}

@test "no trigger anywhere stays silent — the stranded check must not fire on its own" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null

  CLAUDE_PROJECT_DIR="$TMP_REPO" run run_batch "$WT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op in a session-less worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  # A trigger is present, yet the guard must fire first: no memory worktree here.
  mkdir -p "$(dirname "$(gitlore_commit_trigger_file memory)")"
  : > "$(gitlore_commit_trigger_file memory)"
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# D60: a PostToolBatch hook that dies reports instead of ending the turn. The
# IPC directory is read-only (files restored from a backup, another user's), so
# on a clean store `rm -f "$trigger" "$msgfile"`) cannot remove
# either: status 1, both files as found.
@test "an IPC directory that cannot be written is reported on both channels, exit 0" {
  [ "$(id -u)" -ne 0 ] || skip "root writes into a read-only directory"
  make_parent_with_memory
  mkdir -p .claude
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"
  chmod 555 .claude

  run --separate-stderr run_batch
  chmod 755 .claude
  assert_hook_died memory-commit-batch 1 "unknown" "IPC"
  [ -f "$(gitlore_commit_trigger_file memory)" ]
  [ -f "$(gitlore_commit_msg_file memory)" ]
}
