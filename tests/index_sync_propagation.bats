#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Propagation guards (unchanged/added/self-reference/traversal), the two
# hooks' end-to-end wiring, and the per-agent race the post hook must not
# resolve onto the wrong baseline. Continues from tests/index_sync_post.bats.

load helpers/setup
load helpers/fixtures
load helpers/index-sync

# shellcheck disable=SC1090
setup() { setup_tmp_repo; . "$SRC"; }
teardown() { teardown_tmp_repo; }

@test "post: does NOT touch a file whose index line is UNCHANGED (protects fresh frontmatter)" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: fresh frontmatter\n---\n' > memory/b.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  # b's line is identical in pre and post (stale index, unchanged this edit);
  # only a's line changed.
  printf -- '---\ndescription: x\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old\n- [B](b.md) — stale index for b\n' > "$stash"
  printf -- '- [A](a.md) — new\n- [B](b.md) — stale index for b\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  run grep '^description:' memory/b.md
  [ "$output" = 'description: fresh frontmatter' ]   # untouched — the key guard
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new"' ]
}

@test "post: does NOT clobber an authored description when the index line is ADDED (fill-if-empty)" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  # a.md is a freshly authored memory file with a considered description; its
  # index one-liner is ADDED in the same batch (absent from the pre-image). An
  # added line must fill only an empty frontmatter, never overwrite authored
  # prose with the terser index hook.
  printf -- '---\nname: a\ndescription: considered authored prose\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [Z](z.md) — unrelated\n' > "$stash"                                  # a.md NOT in pre-image
  printf -- '- [Z](z.md) — unrelated\n- [A](a.md) — terse index hook\n' > memory/MEMORY.md   # a.md ADDED
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: considered authored prose' ]   # untouched — added-line fill-if-empty
}

@test "post: FILLS an empty description when the index line is ADDED" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  # a.md has no description value; its index line is ADDED this batch. With
  # nothing to clobber, fill-if-empty seeds the frontmatter from the hook.
  printf -- '---\nname: a\ndescription:\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [Z](z.md) — unrelated\n' > "$stash"
  printf -- '- [Z](z.md) — unrelated\n- [A](a.md) — filled hook\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "filled hook"' ]   # seeded — nothing was lost
}

@test "post: no-op when no stash exists (no baseline to diff)" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: keep\n---\n' > memory/a.md
  printf -- '- [A](a.md) — whatever\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: keep' ]
}

@test "post: does NOT rewrite the index itself even via a self-referential index line" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '---\ndescription: index desc\n---\n- [Index](MEMORY.md) — old\n' > "$stash"
  printf -- '---\ndescription: index desc\n---\n- [Index](MEMORY.md) — new\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/MEMORY.md
  [ "$output" = 'description: index desc' ]   # untouched — self-reference guard
}

@test "post: rejects an index line with a '..' path component (no write outside the memory dir)" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  mkdir -p outside
  printf -- '---\ndescription: outside orig\n---\n' > outside/evil.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [Evil](../outside/evil.md) — old\n' > "$stash"
  printf -- '- [Evil](../outside/evil.md) — new\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run grep '^description:' outside/evil.md
  [ "$output" = 'description: outside orig' ]   # untouched — traversal guard
}

@test "post: a failed frontmatter write surfaces via systemMessage and does not abort other files' sync" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits; cannot force a write failure"
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  mkdir memory/locked
  printf -- '---\ndescription: stale a\n---\n' > memory/locked/a.md
  printf -- '---\ndescription: stale b\n---\n' > memory/b.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](locked/a.md) — old a\n- [B](b.md) — old b\n' > "$stash"
  printf -- '- [A](locked/a.md) — new a\n- [B](b.md) — new b\n' > memory/MEMORY.md
  chmod 555 memory/locked   # blocks the frontmatter rewrite for a.md only
  run --separate-stderr post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  chmod 755 memory/locked   # restore so teardown can clean up
  [ "$status" -eq 0 ]                              # PostToolUse: never non-zero here
  run jq -e '.systemMessage' <<<"$output"
  [ "$status" -eq 0 ]                              # stdout is valid JSON with the field
  [[ "$output" == *"locked/a.md"* ]]
  [[ "$stderr" == *"locked/a.md"* ]]                # also echoed to stderr (debug log)
  run grep '^description:' memory/b.md
  [ "$output" = 'description: "new b"' ]            # second target still synced
  [ ! -f "$stash" ]                                 # stash still removed
}

@test "post: stash is removed even when a propagation fails" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits; cannot force a write failure"
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  mkdir memory/locked
  printf -- '---\ndescription: stale\n---\n' > memory/locked/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](locked/a.md) — old\n' > "$stash"
  printf -- '- [A](locked/a.md) — new\n' > memory/MEMORY.md
  chmod 555 memory/locked
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  chmod 755 memory/locked
  [ "$status" -eq 0 ]
  [ ! -f "$stash" ]
}

@test "pre: a failed stash cp emits a systemMessage and exits 0 (never blocks the Write)" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits; cannot force a write failure"
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '- [a](a.md) — before\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  stashdir=$(dirname "$stash")
  chmod 555 "$stashdir"   # blocks creation of the stash file
  payload=$(jq -n --arg f "$abs" '{tool_name:"Edit",tool_input:{file_path:$f}}')
  run --separate-stderr pre_stdin "$payload"
  chmod 755 "$stashdir"   # restore so teardown can clean up
  [ "$status" -eq 0 ]                              # PreToolUse: only exit 2 blocks; never used
  run jq -e '.systemMessage' <<<"$output"
  [ "$status" -eq 0 ]
  [ -n "$stderr" ]
  [ ! -f "$stash" ]
}

@test "e2e: pre-then-post syncs a description edited only in the index" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\nbody\n' > memory/a.md
  printf -- '- [A](a.md) — old hook line\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  pre_payload=$(jq -n --arg f "$abs" '{tool_name:"Edit",tool_input:{file_path:$f}}')
  printf '%s' "$pre_payload" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"
  # the "edit" happens between pre and post:
  printf -- '- [A](a.md) — brand new hook line\n' > memory/MEMORY.md
  printf '%s' "$(batch_payload "$abs")" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "brand new hook line"' ]
}

@test "e2e: a sed -i under Bash propagates, though the call named no file" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  # A Bash call announces nothing, so the pre hook takes the baseline for every
  # one of them and the post hook decides from what actually changed. This is
  # the desync the tool_calls-based trigger left behind: the edit landed and no
  # propagation ran.
  printf '{"tool_name":"Bash","tool_input":{"command":"sed -i ..."}}' \
    | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"
  sed -i'' -e 's/old hook/new hook/' memory/MEMORY.md
  printf '%s' "$(batch_payload)" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new hook"' ]
}

@test "e2e: a Bash call that leaves the index alone propagates nothing" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"
  printf '%s' "$(batch_payload)" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"
  run grep '^description:' memory/a.md
  [ "$output" = 'description: OLD' ]
  [ ! -f "$(git -C memory rev-parse --git-path gitlore-index-preimage)" ]
}

@test "e2e: TWO index edits in one batch diff against the pre-BATCH state, not the last edit" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD A\n---\n' > memory/a.md
  printf -- '---\nname: b\ndescription: OLD B\n---\n' > memory/b.md
  printf -- '- [A](a.md) — hook a v0\n- [B](b.md) — hook b v0\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  pre=$(jq -n --arg f "$abs" '{tool_name:"Edit",tool_input:{file_path:$f}}')
  # Edit 1 of the batch: pre fires, stashes v0; the edit changes a's line.
  printf '%s' "$pre" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"
  printf -- '- [A](a.md) — hook a v1\n- [B](b.md) — hook b v0\n' > memory/MEMORY.md
  # Edit 2 of the same batch: pre fires again and must NOT re-stash. Were the
  # baseline overwritten here, a's change would vanish from the batch-end diff.
  printf '%s' "$pre" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"
  printf -- '- [A](a.md) — hook a v1\n- [B](b.md) — hook b v1\n' > memory/MEMORY.md
  printf '%s' "$(batch_payload "$abs" "$abs")" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "hook a v1"' ]   # the first edit is not lost
  run grep '^description:' memory/b.md
  [ "$output" = 'description: "hook b v1"' ]
}

# The race Item 2.1 exists to close, driven end to end: a parent batch ending
# between a subagent's pre-hook and its post-hook must not consume the
# subagent's baseline. Both cases key the pre-hook with agent_id "a1" for
# real, via $PRE — only the post side is under test. Every payload without an
# agent_id still carries an agent_type decoy, the shape of a real main-thread
# `--agent` payload. It bites in the second phase of the first case, where the
# parent has a baseline of its own to consume: a post-hook falling back to
# `agent_type` resolves a name nothing ever wrote and strands that baseline.
@test "a parent post-hook leaves a subagent's pre-image intact" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  sub_pre=$(jq -n --arg f "$abs" \
    '{tool_name:"Edit",tool_input:{file_path:$f},agent_id:"a1",agent_type:"general-purpose"}')
  printf '%s' "$sub_pre" | bash "$PRE"
  # the subagent's Edit lands
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  # The parent batch ends here with no agent_id of its own — it had no
  # baseline of its own, so there is nothing for it to diff or report.
  run post_stdin "$(TEST_AGENT_TYPE=general-purpose batch_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$(gitlore_index_preimage_file memory a1)" ]

  # Positive control, and the only part of this case that pins WHICH name the
  # parent resolved: with no baseline of its own the parent exits before it
  # touches any file, so a parent that resolved the wrong name — or a post hook
  # that never ran at all — is indistinguishable from a correct one above. Give
  # the parent a baseline it does own, the way the observed race does (a parent
  # Bash call landing after the subagent's Edit, so the pre-hook stashes the
  # index as it already stands), and run the parent's post-hook again: it must
  # consume its own bare pair, stay silent because that baseline matches the
  # index, and still leave the subagent's keyed one alone.
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"},"agent_type":"general-purpose"}' \
    | bash "$PRE"
  [ -f "$(gitlore_index_preimage_file memory)" ]
  run post_stdin "$(TEST_AGENT_TYPE=general-purpose batch_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$(gitlore_index_preimage_file memory)" ]
  [ -f "$(gitlore_index_preimage_file memory a1)" ]
}

@test "the subagent's own post-hook then consumes its keyed pre-image" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  sub_pre=$(jq -n --arg f "$abs" \
    '{tool_name:"Edit",tool_input:{file_path:$f},agent_id:"a1",agent_type:"general-purpose"}')
  printf '%s' "$sub_pre" | bash "$PRE"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  # The parent's own post hook fires first and, as the case above shows,
  # leaves the keyed baseline untouched.
  run post_stdin "$(TEST_AGENT_TYPE=general-purpose batch_payload)"
  [ "$status" -eq 0 ]
  # The continuation: the subagent's own post hook, keyed the same as its pre
  # hook, finds its baseline and completes the propagation.
  run post_stdin "$(TEST_AGENT_ID=a1 TEST_AGENT_TYPE=general-purpose batch_payload "$abs")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new hook"' ]
  [ ! -f "$(gitlore_index_preimage_file memory a1)" ]
}

# Item 3.1/D: the same relay mechanism as the compose hook, over the sync
# hook's own report. The subagent keeps its own report — "in addition to,
# not instead of" — so the systemMessage assertion holds beside the marker.
@test "a keyed index-sync run writes its replacement report to a marker" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  sub_pre=$(jq -n --arg f "$abs" \
    '{tool_name:"Edit",tool_input:{file_path:$f},agent_id:"a1",agent_type:"general-purpose"}')
  printf '%s' "$sub_pre" | bash "$PRE"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  run post_stdin "$(TEST_AGENT_ID=a1 TEST_AGENT_TYPE=general-purpose batch_payload "$abs")"
  [ "$status" -eq 0 ]
  json="$output"
  # The report's own text, not the bare presence of a `systemMessage` key: the
  # key survives a wiring that relayed the report INSTEAD of emitting it and
  # put something else on the user's channel, and "in addition to, not instead
  # of" is the whole point of this assertion.
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reset frontmatter to match MEMORY.md"* ]]
  marker=$(relay_marker_for memory a1)
  [ -f "$marker" ]
  grep -qF 'reset frontmatter to match MEMORY.md' "$marker"
  grep -qF '• a.md:' "$marker"
}

# Slice 2 (D51 revised): index-sync-post.sh no longer drains — relay-drain.sh
# is the one drainer now. Replaces "an unkeyed index-sync run folds in the
# marker" and "... with no report of its own still emits the relay", both of
# which pinned the drain-in-each-hook behaviour this slice removes. The
# marker is staged under the session the hook runs in, so any drain returning
# to the hook would consume it, whether scoped to that session (the D51
# shape) or unscoped; a marker under another session survives both and
# asserts nothing.
@test "an unkeyed index-sync run leaves a marker in place" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  gitlore_relay_write memory test-session a1 sync "keyed relay sysmsg a1" "keyed relay ctx a1"
  marker=$(relay_marker_for memory a1)
  [ -f "$marker" ]
  payload=$(jq -n --arg f "$abs" \
    '{tool_name:"Edit",tool_input:{file_path:$f},agent_type:"general-purpose"}')
  printf '%s' "$payload" | bash "$PRE"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  run post_stdin "$(TEST_AGENT_TYPE=general-purpose batch_payload "$abs")"
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reset frontmatter to match MEMORY.md"* ]]
  [[ "$output" != *"gitlore-relay agent a1"* ]]
  [ -f "$marker" ]
}

@test "e2e: both index-sync hook scripts are executable" {
  [ -x "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh" ]
  [ -x "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh" ]
}

@test "e2e: hooks.json registers pre on PreToolUse(Write|Edit|Bash) and post on PostToolBatch" {
  # Bash is in the matcher because a `sed -i` on the index names no file: the
  # pre hook takes the baseline for every Bash call and the post hooks decide
  # from what actually changed.
  run jq -r '.hooks.PreToolUse[] | select(.matcher=="Write|Edit|Bash") | .hooks[].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *index-sync-pre.sh ]]
  # PostToolBatch takes no matcher — it carries the whole batch, and the hooks
  # key on their own pre-batch baseline rather than on its calls. The event is
  # shared (memory-commit-batch.sh is also registered here), so select the
  # index-sync entry by command.
  run jq -r '.hooks.PostToolBatch[].hooks[].command | select(test("index-sync-post"))' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *index-sync-post.sh ]]
  # ...and is no longer double-registered on the per-call event.
  run jq -r '[.hooks.PostToolUse[]? | .hooks[].command] | map(select(test("index-sync"))) | length' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$output" = "0" ]
}
