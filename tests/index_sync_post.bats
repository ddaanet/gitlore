#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# The index-sync pre and post hook scripts: stashing the index pre-image,
# per-agent keying of the stash, and the post hook's batch-wide propagation,
# reporting and failure handling. Continues in tests/index_sync_propagation.bats.

bats_require_minimum_version 1.5.0   # `run --separate-stderr`

load helpers/setup
load helpers/fixtures
load helpers/index-sync

# shellcheck disable=SC1090
setup() { setup_tmp_repo; . "$SRC"; }
teardown() { teardown_tmp_repo; }

@test "pre: stashes MEMORY.md when the edited file is the index" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '- [a](a.md) — before\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  payload=$(jq -n --arg f "$abs" '{tool_name:"Edit",tool_input:{file_path:$f}}')
  run pre_stdin "$payload"
  [ "$status" -eq 0 ]
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  [ -f "$stash" ]
}

@test "pre: no-op when the edited file is not the index" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '- [a](a.md) — before\n' > memory/MEMORY.md
  payload=$(jq -n --arg f "$PWD/memory/other.md" '{tool_name:"Write",tool_input:{file_path:$f}}')
  run pre_stdin "$payload"
  [ "$status" -eq 0 ]
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  [ ! -f "$stash" ]
}

# A payload's agent_id keys BOTH the pre-image and the compose stamp onto the
# same agent, so a parent batch ending mid-subagent-batch cannot consume the
# subagent's baseline (and the mirror: a subagent batch cannot consume the
# parent's). Absent/empty keeps today's bare name, so the main thread migrates
# nothing. The key is `agent_id`, never `agent_type`: only the first is
# subagent-only, and the second also appears on the main thread of an `--agent`
# session (memory/ddaanet/hook-input-schema.md), so keying on it would move the
# main thread's own files. The no-agent_id payload below carries an
# `agent_type` for exactly that reason — a hook falling back to it stamps a
# keyed path and reds this case.

@test "pre: a payload carrying agent_id stamps the keyed path, not the bare one" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '- [a](a.md) — before\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  # A real subagent payload carries both fields; only `agent_id` may key the
  # path, so the two are given different values and the assertions name a1.
  payload=$(jq -n --arg f "$abs" \
    '{tool_name:"Edit",tool_input:{file_path:$f},agent_id:"a1",agent_type:"general-purpose"}')
  run pre_stdin "$payload"
  [ "$status" -eq 0 ]
  [ -f "$(gitlore_index_preimage_file memory a1)" ]
  [ -f "$(gitlore_compose_stamp_file memory a1)" ]
  [ ! -f "$(gitlore_index_preimage_file memory)" ]
  [ ! -f "$(gitlore_compose_stamp_file memory)" ]
}

@test "pre: a payload with no agent_id stamps the bare path" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '- [a](a.md) — before\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  payload=$(jq -n --arg f "$abs" \
    '{tool_name:"Edit",tool_input:{file_path:$f},agent_type:"general-purpose"}')
  run pre_stdin "$payload"
  [ "$status" -eq 0 ]
  [ -f "$(gitlore_index_preimage_file memory)" ]
  [ -f "$(gitlore_compose_stamp_file memory)" ]
  # Each `find` runs only because the `-f` above it held, which is what proves
  # the directory it searches exists — a `find` on a missing directory prints
  # nothing and would satisfy `-z` vacuously.
  [ -z "$(find "$(dirname "$(gitlore_index_preimage_file memory)")" \
    -maxdepth 1 -name 'gitlore-index-preimage-*')" ]
  [ -z "$(find "$(dirname "$(gitlore_compose_stamp_file memory)")" \
    -maxdepth 1 -name 'gitlore-compose-stamp-*')" ]
}

@test "post: fires ONCE for a batch containing several index edits" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: stale\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — new\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  # Three Edits to the index in one turn — the user must still see one line.
  run post_stdin "$(batch_payload "$abs" "$abs" "$abs")"
  [ "$status" -eq 0 ]
  run jq -r '.systemMessage' <<<"$output"
  [ "${#lines[@]}" -eq 1 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new"' ]
}

@test "post: syncs when the index edit is one call among unrelated ones" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: stale\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — new\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/src.txt" "$PWD/memory/MEMORY.md" "$PWD/other.txt")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new"' ]
}

@test "post: an unchanged index clears the stash and propagates nothing" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: keep me\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old\n' > memory/MEMORY.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  cp memory/MEMORY.md "$stash"              # baseline taken; the batch moved nothing
  run post_stdin "$(batch_payload "$PWD/unrelated.txt")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: keep me' ]
  [ ! -f "$stash" ]
}

@test "post: a stash stranded by an interrupted batch is consumed, not discarded" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: keep me\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"     # stranded by an interrupted batch
  printf -- '- [A](a.md) — new\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/unrelated.txt")"
  [ "$status" -eq 0 ]
  # The propagation that batch owed lands now. The hook keys on the difference
  # between the baseline and the file, not on this batch's calls, so a baseline
  # that outlived its batch is a propagation still due — deferred, not dropped.
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new"' ]
  [ ! -f "$stash" ]                        # and staleness stays bounded to one batch
}

@test "post: hookEventName is PostToolBatch and stdout is suppressed from the transcript" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: stale\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — new\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  json="$output"
  run jq -r '.hookSpecificOutput.hookEventName' <<<"$json"
  [ "$output" = "PostToolBatch" ]
  run jq -r '.suppressOutput' <<<"$json"
  [ "$output" = "true" ]
}

# Seed a stash + a memory file, edit the index, run post.
@test "post: propagates a CHANGED index hook into the file's frontmatter" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: stale desc\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)   # abs
  printf -- '- [A](a.md) — old hook\n' > "$stash"             # pre-image
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md     # post-edit
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new hook"' ]
  [ ! -f "$stash" ]   # stash consumed
}

# Reds when the hook's `|| agent_id=""` fallback (line ~30) is removed: jq's
# parse failure then kills the hook under errexit before the stash is ever
# consumed, so nothing propagates and the stash survives.
@test "post: an unparseable payload still propagates on the unkeyed baseline (fallback proof)" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: stale desc\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook\n' > "$stash"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  run bash -c 'printf "not json" | bash "$1"' _ "$POST"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new hook"' ]
  [ ! -f "$stash" ]
}

@test "post: refuses to propagate a hook carrying a markdown link (glue artifact)" {
  # `gitlore_index_pairs` splits on the FIRST ") — ", so a welded line is one
  # syntactically valid pair whose hook happens to contain a whole second
  # bullet. Propagating it faithfully copies the blob into `description:`,
  # where it is far less visible than in the index. A description holding a
  # second `](` is structurally impossible as a hook, so the sync refuses it —
  # independently of whatever produced the glue.
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: stale desc\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook\n' > "$stash"
  printf -- '- [A](a.md) — hook a- [B](b.md) — hook b\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: stale desc' ]   # untouched, not overwritten
}

@test "post: says which line it refused, on both channels" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: stale desc\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook\n' > "$stash"
  printf -- '- [A](a.md) — hook a- [B](b.md) — hook b\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [[ "$output" == *"a.md"* ]]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [[ "$output" == *"a.md"* ]]
  [[ "$output" == *"welded"* ]]   # names the shape, so the fix is the index line
}

@test "post: a hook carrying plain brackets still propagates" {
  # The negative half: only a markdown LINK is a glue artifact. A bracketed
  # span is ordinary hook text and must reach the frontmatter untouched.
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: stale desc\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook\n' > "$stash"
  printf -- '- [A](a.md) — hook with [a bracket] and (parens)\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "hook with [a bracket] and (parens)"' ]
}

@test "post: systemMessage is ONE terse line; the replaced text goes to the agent only" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: considered prose the agent authored\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook\n' > "$stash"
  printf -- '- [A](a.md) — terse hook\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [ "${#lines[@]}" -eq 1 ]                                     # one line, no bullets
  [[ "$output" == *"MEMORY.md"* ]]
  [[ "$output" != *"considered prose the agent authored"* ]]   # detail is not the user's problem
  # The agent still gets the full before/after — explicitness buys compliance.
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [[ "$output" == *"considered prose the agent authored"* ]]
  [[ "$output" == *"terse hook"* ]]
}

@test "post: tells the agent via additionalContext so it need not re-derive" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: old prose\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook\n' > "$stash"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  json="$output"   # each `run` clobbers $output; keep the JSON to re-query
  run jq -r '.hookSpecificOutput.hookEventName' <<<"$json"
  [ "$output" = "PostToolBatch" ]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.md"* ]]
}

@test "post: marks an absent description as unset rather than replaced" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\n---\nbody\n' > memory/a.md   # no description: line
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook\n' > "$stash"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$output"
  [[ "$output" == *"unset"* ]]
  [[ "$output" == *"a.md"* ]]
}

@test "post: stays SILENT when the frontmatter already matched the new hook (no news)" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  # Index line changed, but the frontmatter already carries the new text —
  # the rewrite is a no-op, so there is nothing to report.
  printf -- '---\ndescription: "new hook"\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook\n' > "$stash"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "post: reports a successful sync and a failure together in ONE json object" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits; cannot force a write failure"
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  mkdir memory/locked
  printf -- '---\ndescription: stale a\n---\n' > memory/locked/a.md
  printf -- '---\ndescription: stale b\n---\n' > memory/b.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](locked/a.md) — old a\n- [B](b.md) — old b\n' > "$stash"
  printf -- '- [A](locked/a.md) — new a\n- [B](b.md) — new b\n' > memory/MEMORY.md
  chmod 555 memory/locked
  run --separate-stderr post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  chmod 755 memory/locked
  [ "$status" -eq 0 ]
  # A single object: two jq objects concatenated would not parse as one.
  run jq -e '.' <<<"$output"
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [[ "$output" == *"locked/a.md"* ]]   # the failure names the file — it needs action
  [[ "$output" == *"MEMORY.md"* ]]     # alongside the terse success line
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [[ "$output" == *"stale b"* ]]       # the successful replacement, agent-side
}
