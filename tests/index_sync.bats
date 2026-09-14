#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.5.0   # `run --separate-stderr`

load helpers/setup
load helpers/fixtures

SRC="$PLUGIN_ROOT/scripts/lib/index-sync.sh"

# shellcheck disable=SC1090
setup() { setup_tmp_repo; . "$SRC"; }
teardown() { teardown_tmp_repo; }

@test "index_pairs: extracts path and hook, tab-separated" {
  printf '# Memory Index\n\n- [Proj](project_overview.md) — current state, next steps\n- [Gitmoji](feedback_gitmoji.md) — prefixes required\n' > MEMORY.md
  run gitlore_index_pairs MEMORY.md
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'project_overview.md\tcurrent state, next steps')" ]
  [ "${lines[1]}" = "$(printf 'feedback_gitmoji.md\tprefixes required')" ]
}

@test "index_pairs: skips non-bullet and separatorless lines" {
  printf '# Header\n- [x](a.md) no dash here\n- [y](b.md) — has hook\n' > MEMORY.md
  run gitlore_index_pairs MEMORY.md
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "$(printf 'b.md\thas hook')" ]
}

@test "index_pairs: hook containing an em-dash keeps everything after the FIRST separator" {
  printf -- '- [z](c.md) — front — back\n' > MEMORY.md
  run gitlore_index_pairs MEMORY.md
  [ "${lines[0]}" = "$(printf 'c.md\tfront — back')" ]
}

@test "set_frontmatter_description: replaces the description line in place" {
  printf -- '---\nname: foo\ndescription: old text\nmetadata:\n  type: project\n---\n\nbody\n' > f.md
  gitlore_set_frontmatter_description f.md "new hook text"
  run grep -c '^description:' f.md
  [ "$output" = "1" ]
  run grep '^description:' f.md
  [ "$output" = 'description: "new hook text"' ]
  run grep -c '^name: foo' f.md   # untouched
  [ "$output" = "1" ]
  run tail -n1 f.md               # body untouched
  [ "$output" = "body" ]
}

# shellcheck disable=SC2016
@test "set_frontmatter_description: YAML-escapes quotes, colons, backticks" {
  printf -- '---\ndescription: x\n---\n' > f.md
  gitlore_set_frontmatter_description f.md 'has "quote": a `tick` and \ slash'
  run grep '^description:' f.md
  [ "$output" = 'description: "has \"quote\": a `tick` and \\ slash"' ]
}

@test "set_frontmatter_description: only touches the FIRST frontmatter block" {
  printf -- '---\ndescription: real\n---\nbody with\n---\ndescription: not-frontmatter\n---\n' > f.md
  gitlore_set_frontmatter_description f.md "changed"
  run grep -c '^description: not-frontmatter' f.md
  [ "$output" = "1" ]
  run grep -c '^description: "changed"' f.md
  [ "$output" = "1" ]
}

@test "set_frontmatter_description: no scratch file survives when awk itself fails (not the redirect)" {
  printf -- '---\ndescription: old\n---\n' > f.md
  # Shadow awk with a stub that always fails, so the redirect (which creates
  # the scratch file) succeeds but the command itself does not — distinct
  # from the chmod-555 case, which fails the redirect before awk ever runs.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  printf '#!/bin/sh\nexit 1\n' > "$fakebin/awk"
  chmod +x "$fakebin/awk"
  PATH="$fakebin:$PATH" run gitlore_set_frontmatter_description f.md "new"
  [ "$status" -ne 0 ]                      # failure status preserved
  [ ! -e f.md.gitlore.tmp ]                # no leftover temp file beside the target
  run find .git -name 'gitlore-frontmatter.tmp.*'
  [ -z "$output" ]                         # no leftover temp file in the gitdir either
  run grep '^description:' f.md
  [ "$output" = 'description: old' ]       # original file untouched
}

# shellcheck disable=SC2016
@test "get_frontmatter_description: unquotes a JSON-quoted scalar (round-trips the setter)" {
  printf -- '---\ndescription: x\n---\n' > f.md
  gitlore_set_frontmatter_description f.md 'has "quote": a `tick`'
  run gitlore_get_frontmatter_description f.md
  [ "$status" -eq 0 ]
  [ "$output" = 'has "quote": a `tick`' ]
}

@test "get_frontmatter_description: returns a bare (hand-authored) value verbatim" {
  printf -- '---\nname: a\ndescription: hand authored prose — no quotes\n---\nbody\n' > f.md
  run gitlore_get_frontmatter_description f.md
  [ "$status" -eq 0 ]
  [ "$output" = 'hand authored prose — no quotes' ]
}

@test "get_frontmatter_description: fails when there is no description line" {
  printf -- '---\nname: a\n---\nbody\ndescription: not in frontmatter\n' > f.md
  run gitlore_get_frontmatter_description f.md
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

PRE="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"

pre_stdin() { printf '%s' "$1" | bash "$PRE"; }

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

POST="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"

post_stdin() { printf '%s' "$1" | bash "$POST"; }

# PostToolBatch payload: every call of the turn under .tool_calls[], so the
# sync runs once per batch however many Edits it contains. $1.. = file paths.
# TEST_AGENT_ID mirrors TEST_SESSION_ID: unset/empty omits the field entirely
# (a main-thread batch), non-empty adds it (a subagent batch) — same
# absent/empty-vs-non-empty contract as the helpers in scripts/lib/index-sync.sh.
# TEST_AGENT_TYPE is the decoy field: a real main-thread payload from inside an
# `--agent` session carries `agent_type` but never `agent_id`, so a hook that
# falls back to `agent_type` must not key on it.
batch_payload() {
  local f json='[]'
  for f in "$@"; do
    json=$(jq -c --arg f "$f" '. + [{tool_name:"Edit",tool_input:{file_path:$f}}]' <<<"$json")
  done
  jq -n --argjson c "$json" --arg s "${TEST_SESSION_ID:-test-session}" \
    --arg a "${TEST_AGENT_ID:-}" --arg t "${TEST_AGENT_TYPE:-}" \
    '{hook_event_name:"PostToolBatch", session_id:$s, tool_calls:$c, tool_results:[]}
     + (if $a == "" then {} else {agent_id:$a} end)
     + (if $t == "" then {} else {agent_type:$t} end)'
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
# hook's own report. The subagent's own report is unaffected by this item —
# "in addition to, not instead of" — so the systemMessage assertion is already
# true today; only the marker half is new.
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
# marker is written under the empty/"nosession" mapping so this reds against
# TODAY's code, which still drains unkeyed with no session concept at all —
# a marker under a real session would already survive today, making the
# assertion vacuous rather than red.
@test "an unkeyed index-sync run leaves a marker in place" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  gitlore_relay_write memory "" a1 sync "keyed relay sysmsg a1" "keyed relay ctx a1"
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

# --- per-agent pre-image / compose-stamp paths ---------------------------------
#
# An absent or empty agent id yields exactly the name every existing consumer
# already uses, so the main thread's files do not migrate; a non-empty one
# appends `-<agent_id>`. Both halves are asserted as an equality against the
# `rev-parse --git-path` name rather than a trailing glob: equality is what
# pins the file inside the memory submodule's gitdir, rejects a `-` appended
# for an empty id, and rejects a doubled or partial suffix.

@test "preimage_file is unsuffixed with no agent id" {
  make_parent_with_memory
  base=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  run gitlore_index_preimage_file memory
  [ "$status" -eq 0 ]
  [ "$output" = "$base" ]
  run gitlore_index_preimage_file memory ""
  [ "$status" -eq 0 ]
  [ "$output" = "$base" ]
}

@test "preimage_file suffixes the agent id" {
  make_parent_with_memory
  base=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  run gitlore_index_preimage_file memory agent-7
  [ "$status" -eq 0 ]
  [ "$output" = "$base-agent-7" ]
}

@test "compose_stamp_file is unsuffixed with no agent id" {
  make_parent_with_memory
  base=$(git -C memory rev-parse --git-path gitlore-compose-stamp)
  run gitlore_compose_stamp_file memory
  [ "$status" -eq 0 ]
  [ "$output" = "$base" ]
  run gitlore_compose_stamp_file memory ""
  [ "$status" -eq 0 ]
  [ "$output" = "$base" ]
}

@test "compose_stamp_file suffixes the agent id" {
  make_parent_with_memory
  base=$(git -C memory rev-parse --git-path gitlore-compose-stamp)
  run gitlore_compose_stamp_file memory agent-7
  [ "$status" -eq 0 ]
  [ "$output" = "$base-agent-7" ]
}

@test "an agent id outside [A-Za-z0-9-] cannot leave the gitdir" {
  make_parent_with_memory
  traversal='../../../etc/passwd'
  sanitized=$(printf '%s' "$traversal" | LC_ALL=C tr -c 'A-Za-z0-9-' '_')

  base=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  run gitlore_index_preimage_file memory "$traversal"
  [ "$status" -eq 0 ]
  [ "$output" = "$base-$sanitized" ]
  run gitlore_index_preimage_file memory agent-7
  [ "$status" -eq 0 ]
  [ "$output" = "$base-agent-7" ]

  base=$(git -C memory rev-parse --git-path gitlore-compose-stamp)
  run gitlore_compose_stamp_file memory "$traversal"
  [ "$status" -eq 0 ]
  [ "$output" = "$base-$sanitized" ]
  run gitlore_compose_stamp_file memory agent-7
  [ "$status" -eq 0 ]
  [ "$output" = "$base-agent-7" ]
}

# --- relay markers (Item 3.1/D51 revision) -------------------------------------
#
# Redesigned per plans/index-edit-propagation/relay-redesign.md: a subagent's
# report is now a write-once file keyed by session AND agent, never merged,
# and drained by session rather than folded in by any unkeyed run. Two
# channels — sysmsg is the user's, ctx is the model's — must not
# cross-contaminate on drain.
#
# RED stub (slice 1): gitlore_relay_write and gitlore_relay_drain accept the
# new argument positions (mempath session agent tag sysmsg ctx / mempath
# session) but still key a relay file on the agent id alone, still merge a
# second write into the first, and still ignore the session argument on
# drain — exactly the defects cases 1-3 below exist to catch.
# gitlore_relay_sweep is inert. gitlore_relay_marker_file is retired: no case
# below predicts a relay filename, all locate files with `find`.

# 1: two writes under one agent in one session yield two files; the drain
# frames both, in write order, and removes both.
@test "relay_write: two writes under one agent in one session yield two files, drained together in write order" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  run gitlore_relay_write memory s1 a-1 sync "S1" "C1"
  [ "$status" -eq 0 ]
  # A whole second between the two writes, not a stylistic pause. The design
  # fixes the filename as `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>`, so two
  # writes that agree on session, agent, tag AND wall-clock second collide on
  # one name, and D51 refuses an install onto an occupied path. Production
  # cannot produce that collision — the two writers are separate hook
  # processes carrying different pids and different tags — but this case
  # drives both writes from one shell, so it has to separate them on the one
  # field it controls. That same field is what the order assertion below
  # rests on: filename order is write order only because the epochs differ.
  sleep 1
  run gitlore_relay_write memory s1 a-1 sync "S2" "C2"
  [ "$status" -eq 0 ]

  # Two files on disk before the drain removes them — red on the RED stub,
  # which still keys a relay file on the agent id alone and merges a second
  # write into the first (see gitlore_relay_write's RED STUB comment).
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print0)
  [ "$count" -eq 2 ]

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]
  # Two separate framing lines for a-1, not one — a merge into a single file
  # frames only once no matter how many bodies land in it. `-x`: the frame is
  # the whole line `--- gitlore-relay agent a-1 ---`, and a substring match
  # would also accept a frame carrying the session, epoch or tag alongside
  # the agent id, which is not the format D51 states. The agent id carries a
  # dash on purpose: D51 recovers `A` from the filename by stripping the
  # known `gitlore-relay-<S>-` prefix and the three trailing `-<epoch>-<pid>-<H>`
  # fields, and calls that unambiguous for a dashed id. Nothing else in the
  # slice exercises that claim, and the plausible wrong recovery — cutting at
  # the first dash — frames `a` here instead.
  run grep -c -x -- '--- gitlore-relay agent a-1 ---' <<<"$GITLORE_RELAY_SYSMSG"
  [ "$output" -eq 2 ]
  # Order, not mere presence.
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1"*"S2"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"C1"*"C2"* ]]

  # ...and both files are gone.
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' -print0)
  [ "$count" -eq 0 ]
}

# 2 (C2): 20 gitlore_relay_write calls for one agent in parallel, one drain —
# every body must survive. Red on the merge-write stub regardless of the
# renumbering above: a shared, read-modify-written file loses most of 20
# racing installs, the same shape the deliverable review measured at 86 lost
# reports in 200 runs of two concurrent writers.
#
# The writers are separate `bash -c` PROCESSES, not `foo &` subshells of this
# test's shell. D51 discriminates two same-second writes by the writer's pid,
# and `$$` is fixed at shell startup: every `&` subshell of one shell reports
# the same `$$`, and `$BASHPID` — the only per-subshell alternative — does not
# exist on bash 3.2, which is a target. Backgrounded subshells would therefore
# make this case fail on GREEN for a reason production never has, since in
# production each writer is its own hook process. Spawning processes
# reproduces the guarantee the design actually rests on.
@test "relay_write: 20 concurrent writes for one agent are not lost by the drain" {
  make_parent_with_memory

  for i in $(seq 1 20); do
    bash -c '
      set -euo pipefail
      # shellcheck disable=SC1090
      . "$1"
      gitlore_relay_write "$2" s1 a1 sync "SYS-$3" "CTX-$3"
    ' _ "$SRC" "$PWD/memory" "$i" &
  done
  # Bare `wait` returns 0 whatever the children returned, so a writer that
  # failed is not reported here. That is deliberate: the contract under test
  # is what the drain recovers, and a per-writer status check would red this
  # case on the writers' own exits before the recovery assertion below ever
  # ran. A lost write shows up as a missing body either way.
  wait

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]

  # `-x`, the whole framing line — see case 1.
  run grep -c -x -- '--- gitlore-relay agent a1 ---' <<<"$GITLORE_RELAY_SYSMSG"
  [ "$output" -eq 20 ]
  for i in $(seq 1 20); do
    # `-x`, exact full-line match: a substring check on "SYS-$i" alone would
    # count "SYS-1" as present whenever "SYS-10".."SYS-19" survived instead.
    run grep -c -x -- "SYS-$i" <<<"$GITLORE_RELAY_SYSMSG"
    [ "$output" -eq 1 ]
    run grep -c -x -- "CTX-$i" <<<"$GITLORE_RELAY_CTX"
    [ "$output" -eq 1 ]
  done
}

# 3: a write for session S2 is not drained by S1 and survives it. Different
# agent ids for the two sessions, so the RED stub's write always creates a
# fresh, distinct file (no cross-write merge muddying this case) — the only
# defect this case can catch is the drain's blindness to its own session
# argument.
@test "relay_drain: a write for session S2 is not drained by S1 and survives it" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  run gitlore_relay_write memory s1 a1 sync "S1-BODY" "C1-BODY"
  [ "$status" -eq 0 ]
  run gitlore_relay_write memory s2 a2 sync "S2-BODY" "C2-BODY"
  [ "$status" -eq 0 ]

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1-BODY"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" != *"S2-BODY"* ]]

  # The S2 write is untouched by S1's drain — red on the RED stub, which
  # ignores the session argument and drains every keyed file it finds
  # regardless of which session it was written for (see
  # gitlore_relay_drain's RED STUB comment).
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print0)
  [ "$count" -eq 1 ]

  rc=0
  gitlore_relay_drain memory s2 || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"S2-BODY"* ]]
}

# 4: a .tmp beside the markers is neither folded nor removed by the drain
# (the unlink-between-read-and-rm half is settled by construction — unique
# names — and has no test). Over a gitdir path holding a space, per the
# whitespace-safety rule: this is the only case in the new section that
# builds a fixture out of line, so it is the one that reuses the shape.
@test "relay_drain: a .tmp beside the markers is neither folded nor removed, over a gitdir path holding a space" {
  root="$TMP_REPO/has space"
  _gitlore_build_parent_with_memory "$root" memory
  mem="$root/memory"
  gitdir=$(git -C "$mem" rev-parse --absolute-git-dir)
  case "$gitdir" in
    *\ *) : ;;                             # the fixture really is spaced
    *) echo "fixture gitdir path has no space" >&2; return 1 ;;
  esac

  run gitlore_relay_write "$mem" s1 a1 sync "S1" "C1"
  [ "$status" -eq 0 ]
  tmp="$gitdir/gitlore-relay-s1-orphan-9999999999-99999-sync.tmp"
  {
    printf -- '--- gitlore-relay-sysmsg ---\n'
    printf 'TORN-BODY\n'
  } > "$tmp"

  rc=0
  gitlore_relay_drain "$mem" s1 || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" != *"TORN-BODY"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" != *"orphan"* ]]
  [ -e "$tmp" ]
  # Born green against the RED stub — the `.tmp` exclusion is unchanged from
  # the pre-revision code — so the ordering supplies no red here and the
  # discrimination was shown by mutation instead. Dropping `'!' -name
  # '*.tmp'` from the drain's `find` reds the TORN-BODY assertion; widening
  # the drain's per-marker `rm -f "$marker.tmp"` to `rm -f
  # "$gitdir"/gitlore-relay-*.tmp` — the plausible "clean up strays" form —
  # reds `[ -e "$tmp" ]`. One mutation per half, so neither is decoration.
}

# 5: the sweep removes relay files older than 7 days, temps included, and
# leaves fresh ones alone. Red on the inert RED stub: gitlore_relay_sweep is a
# no-op, so the aged marker is never removed.
@test "relay_sweep: removes relay files older than 7 days, temps included, and leaves fresh ones alone" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  run gitlore_relay_write memory s1 a1 sync "OLD" "OLD-C"
  [ "$status" -eq 0 ]
  old=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$old" ]
  # BSD `date -v` first; GNU has no `-v` and errors on it, so the `||` falls
  # back to `-d` — provoking the platform mismatch is the detection
  # mechanism, not a routine failure suppression.
  old_ts=$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d '10 days ago' +%Y%m%d%H%M)
  touch -t "$old_ts" "$old"
  old_tmp="$old.tmp"
  printf 'STALE-TMP\n' > "$old_tmp"
  touch -t "$old_ts" "$old_tmp"

  run gitlore_relay_write memory s1 a2 sync "FRESH" "FRESH-C"
  [ "$status" -eq 0 ]
  fresh=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' '!' -path "$old" -print)
  [ -n "$fresh" ]

  fresh_tmp="$fresh.tmp"
  printf 'LIVE-TMP\n' > "$fresh_tmp"

  run gitlore_relay_sweep memory
  [ "$status" -eq 0 ]
  [ ! -e "$old" ]
  # Fails on a sweep that ignores age and clears the directory.
  [ -e "$fresh" ]
  # The `.tmp` exclusion is a DRAIN rule — a temp must never be folded as a
  # report — not a sweep rule: a temp stranded by a killed writer is collected
  # by age like any other relay file, or it would never be collected at all.
  # Fails on a sweep that carries the drain's `'!' -name '*.tmp'` over.
  [ ! -e "$old_tmp" ]
  # Fails on a sweep that removes every `.tmp` regardless of age — one a
  # writer is still filling.
  [ -e "$fresh_tmp" ]
}

# 6: empty agent id refused; empty session maps to "nosession" on both sides.
@test "relay_write: empty agent id refused; empty session and \"nosession\" reach each other" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  # Born green — the refusal is unchanged pre-revision behaviour, so the
  # ordering supplies no red. Shown to discriminate by mutation: replacing
  # `[ -n "$agent" ] || return 1` in gitlore_relay_write with a no-op reds
  # this `[ "$status" -ne 0 ]`.
  run gitlore_relay_write memory s1 "" sync "S" "C"
  [ "$status" -ne 0 ]
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay*' -print0)
  [ "$count" -eq 0 ]

  # Empty session maps to "nosession" on both sides — a write with no session
  # id, drained under the literal session id "nosession", must reach it.
  run gitlore_relay_write memory "" a1 sync "NOSESSION-BODY" "NOSESSION-CTX"
  [ "$status" -eq 0 ]

  # The write side of the mapping, asserted on the name D51 states:
  # `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>` with `S` = "nosession". Red on
  # the RED stub, which keys on the agent id alone and writes
  # `gitlore-relay-a1`. Without this, the "reach each other" assertion below
  # is vacuous against a stub that ignores the session argument on BOTH
  # sides: a drain that enumerates everything reaches a write that recorded
  # nothing, and neither half of the mapping is exercised.
  name=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$name" ]
  [[ "${name##*/}" == gitlore-relay-nosession-a1-* ]]

  # The drain side. Still cannot red on its own before GREEN scopes the
  # enumeration by session — it binds on that scoping, and case 3 is what
  # proves the scoping exists at all.
  rc=0
  gitlore_relay_drain memory nosession || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"NOSESSION-BODY"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"NOSESSION-CTX"* ]]
}

# 7 (flagged in relay-s1-code-review.md "The tag guard ships untested"): a tag
# outside {sync, compose} is a caller mistake, not a hook-payload field, so
# gitlore_relay_write refuses it rather than sanitizing it — validated here
# rather than merely assumed from the code review's read of the guard.
@test "relay_write: a tag outside {sync, compose} is refused and leaves no file" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  rc=0
  gitlore_relay_write memory s1 a1 bogus "S" "C" || rc=$?
  [ "$rc" -ne 0 ]
  run find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*'
  [ -z "$output" ]
}

# --- relay markers: robustness cases carried over, adapted to the new signatures
#
# Behaviour that survives the D51 revision unchanged, kept as regression pins.
# `the drain survives a gitdir it cannot write` was not individually named in
# the runbook's keep-list (only the three above it were), but its own
# behaviour survives the revision the same way theirs does, so it is kept
# here too rather than dropped.

@test "relay_drain on an empty store sets both variables empty and returns 0" {
  make_parent_with_memory
  # Sentinels, not the birth state: a drain that leaves the variables alone
  # when it finds nothing would re-emit whatever the previous drain left in
  # them. The decoy is a real neighbour in the same gitdir, so a `gitlore-*`
  # glob deletes the compose baseline and fails here rather than in Item 2.1's
  # cases.
  GITLORE_RELAY_SYSMSG="STALE-SYS"
  GITLORE_RELAY_CTX="STALE-CTX"
  decoy=$(gitlore_compose_stamp_file memory)
  : > "$decoy"

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]
  [ -z "$GITLORE_RELAY_SYSMSG" ]
  [ -z "$GITLORE_RELAY_CTX" ]
  [ -f "$decoy" ]
}

@test "an unreadable marker costs the relay, not the hook" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  run gitlore_relay_write memory s1 a1 sync "S" "C"
  [ "$status" -eq 0 ]
  marker=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$marker" ]
  chmod 0200 "$marker"

  # Plain `run`, not `run --separate-stderr`: awk's "Permission denied" is on
  # stderr on every run of this fixture and lands in $output, but the assertion
  # below is a substring on the synthetic hook's own line, which no diagnostic
  # supplies. `--separate-stderr` would also stop shellcheck recognising
  # `bash -c` and linting the script below, trading that for nothing.
  run bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    . "$1"
    gitlore_relay_drain "$2" s1
    printf "OWN REPORT\n"
  ' _ "$SRC" "$PWD/memory"
  # Guarded, not unconditional: a fixed drain folds the unreadable marker as an
  # empty block and removes it, and a bare chmod would then fail on a missing
  # path — killing the test on its own cleanup instead of on an assertion.
  [ -e "$marker" ] && chmod 0600 "$marker"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OWN REPORT"* ]]
  [ ! -e "$marker" ]
}

@test "the drain survives a gitdir it cannot write" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  run gitlore_relay_write memory s1 a1 sync "S" "C"
  [ "$status" -eq 0 ]
  # r-x, no w: `find` can still enumerate and `awk` can still read the marker
  # (both need only read+execute on the directory), but the drain's `rm -f`
  # needs write on the directory it lives in, which this removes.
  chmod 0500 "$gitdir"

  run bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    . "$1"
    gitlore_relay_drain "$2" s1
    printf "OWN REPORT\n"
  ' _ "$SRC" "$PWD/memory"

  # Guarded, not unconditional — see the marker-mode case above for why.
  [ -e "$gitdir" ] && chmod 0700 "$gitdir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OWN REPORT"* ]]
}

@test "relay_write does not destroy a staged report when its temp cannot be written" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  # Both writes invoked directly, never through `run`: `run` forks its
  # command into its own subshell, so two `run gitlore_relay_write` calls
  # would carry two different `$BASHPID` values and land on two different
  # names — this case needs the SECOND write to target the SAME name as the
  # first, which only holds when both calls share one process.
  #
  # Same pid is not enough: the name also carries `date +%s`, so whenever the
  # two calls straddle a second boundary the second one picks a fresh name,
  # misses the squat and succeeds — measured at 4 failures in 25 runs before
  # this stub went in. Freezing the epoch makes the collision the fixture's
  # own construction rather than a coincidence of timing. The stub delegates
  # every other invocation to the real binary so nothing else shifts.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_date=$(command -v date)
  cat > "$fakebin/date" <<EOF
#!/bin/sh
case "\$1" in
  +%s) echo 1700000000; exit 0 ;;
esac
exec "$real_date" "\$@"
EOF
  chmod +x "$fakebin/date"
  saved_path="$PATH"
  PATH="$fakebin:$PATH"

  rc=0
  gitlore_relay_write memory s1 a1 sync "S1" "C1" || rc=$?
  [ "$rc" -eq 0 ]
  marker=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$marker" ]
  before=$(cat "$marker")

  # The atomic write builds the new marker at `$marker.tmp` and only then
  # renames it into place; squatting that path with a directory makes the
  # write fail with the marker itself never opened.
  mkdir "$marker.tmp"

  rc=0
  gitlore_relay_write memory s1 a1 sync "S2" "C2" || rc=$?
  PATH="$saved_path"
  [ "$rc" -ne 0 ]

  # The squat is untouched (nothing landed there) and the FIRST report is
  # still on disk byte for byte -- S2/C2 never overwrote it.
  [ -d "$marker.tmp" ]
  [ "$(cat "$marker")" = "$before" ]
}

# --- routing-key advisories ---------------------------------------------------

# shellcheck disable=SC2016   # literal backticks/$VAR are the fixture text
@test "has_literal: accepts the token classes a real query would carry" {
  for h in 'a `backticked` span' 'pass --print to it' 'lives in scripts/lib' \
           'the .gitmodules file' 'see docs/design.md' 'when $TMPDIR is unset' \
           'set protocol.ext.allow=never' 'fixed in 2.47.3' \
           'clear GIT_INDEX_FILE first' 'the autoMemoryDirectory setting' \
           'CC freezes it' 'the FR11 gate'; do
    run gitlore_index_has_literal "$h"
    [ "$status" -eq 0 ] || { echo "missed literal in: $h"; return 1; }
  done
}

@test "has_literal: a prose hook carries none" {
  run ! gitlore_index_has_literal 'run new code on the real target the day it ships'
  run ! gitlore_index_has_literal 'current state, next steps, design doc location'
}

@test "has_literal: a hyphenated word is prose, not a flag" {
  # The whole point of splitting on whitespace: an ERE for `-x` with no portable
  # word boundary would match the tail of every hyphenated compound.
  run ! gitlore_index_has_literal 'a well-known model-dependent trade-off'
}

@test "has_literal: strips surrounding punctuation before classifying" {
  run gitlore_index_has_literal 'wraps it (--print), then exits'
  [ "$status" -eq 0 ]
  run ! gitlore_index_has_literal 'the index, the store; the pass.'
}

@test "frontmatter_type: reads the indented metadata form and ignores node_type" {
  printf -- '---\nname: a\nmetadata:\n  node_type: memory\n  type: reference\n---\nbody\n' > f.md
  run gitlore_frontmatter_type f.md
  [ "$output" = "reference" ]
}

@test "frontmatter_type: reads the older top-level form" {
  printf -- '---\nname: a\ntype: feedback\n---\nbody\n' > f.md
  run gitlore_frontmatter_type f.md
  [ "$output" = "feedback" ]
}

@test "frontmatter_type: fails when there is no type, and ignores the body" {
  printf -- '---\nname: a\n---\ntype: reference\n' > f.md
  run gitlore_frontmatter_type f.md
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "index_budget_pct: floored percent of the byte budget" {
  printf '%0.sx' $(seq 1 512) > MEMORY.md      # 512 bytes, no trailing newline
  GITLORE_INDEX_BUDGET_BYTES=1024
  run gitlore_index_budget_pct MEMORY.md
  [ "$output" = "50" ]
}

@test "index_largest: ranks bullets by BYTE length, descending, top N" {
  {
    printf -- '- [S](s.md) — tiny\n'
    printf -- '- [L](l.md) — %s\n' "$(printf '%0.sx' $(seq 1 80))"
    printf -- '- [M](m.md) — %s\n' "$(printf '%0.sx' $(seq 1 40))"
    printf 'not a bullet at all, and long enough to outrank them\n'
  } > MEMORY.md
  run gitlore_index_largest MEMORY.md 2
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]#*$'\t'}" = "l.md" ]
  [ "${lines[1]#*$'\t'}" = "m.md" ]
}

@test "index_largest: survives an index too big to fit the pipe buffer" {
  # Callers run with `set -o pipefail`. An early-exiting consumer (`head -n`)
  # leaves `sort` writing into a closed pipe once its output exceeds the 64 KiB
  # pipe buffer: SIGPIPE, exit 141, and the advisory is lost on precisely the
  # large indexes it exists to report on.
  # Built in one awk pass: a 3000-iteration shell loop makes this the slowest
  # test in the suite for no extra coverage.
  # What has to exceed the 64 KiB pipe buffer is `sort`'s OUTPUT, not the index:
  # each line it emits is "bytes<TAB>path", so the paths carry the volume.
  awk 'BEGIN {
    printf "# Memory Index\n\n"
    pad = sprintf("%0100d", 0)
    for (i = 1; i <= 3000; i++) printf "- [t%d](f%050d_%s.md) — %s\n", i, i, pad, pad
  }' > MEMORY.md
  [ "$(wc -c < MEMORY.md)" -gt 65536 ]

  set -o pipefail
  run gitlore_index_largest MEMORY.md 5
  set +o pipefail
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
}

# shellcheck disable=SC2016   # literal backticks/$VAR are the fixture text
@test "post: flags a reference line whose hook carries no trigger token" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nmetadata:\n  type: reference\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old hook with `code`\n' > "$stash"
  printf -- '- [A](a.md) — hidden scaffolding channel, model dependent\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [[ "$output" == *"a.md"* ]]
  [[ "$output" == *"trigger"* ]]
  run jq -r '.systemMessage' <<<"$json"
  [[ "$output" == *"routing key"* ]]
}

@test "post: does NOT flag a prose hook on a feedback memory" {
  # A behavioural rule is found by topic, not by an error string; prose is
  # correct there. Type-conditioning is what keeps this check out of the way.
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nmetadata:\n  type: feedback\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — run new code on the real target the day it ships\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  run jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$output"
  [[ "$output" != *"trigger"* ]]
}

# shellcheck disable=SC2016   # literal backticks/$VAR are the fixture text
@test "post: does NOT flag a reference line that already carries a token" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nmetadata:\n  type: reference\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — `git rev-parse --local-env-vars` clears them\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  run jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$output"
  [[ "$output" != *"trigger"* ]]
}

# shellcheck disable=SC2016   # literal backticks/$VAR are the fixture text
@test "post: does NOT re-flag an UNCHANGED weak line" {
  # Advisories are diff-keyed like the sync: an old thin hook is not news every
  # time some other line is edited, or the channel becomes noise to scroll past.
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nmetadata:\n  type: reference\n---\nbody\n' > memory/a.md
  printf -- '---\nmetadata:\n  type: reference\n---\nbody\n' > memory/b.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — thin prose\n- [B](b.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — thin prose\n- [B](b.md) — now `tokenised`\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  run jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$output"
  # b.md IS flagged over the same fixture, in the same channel: without it the
  # absence of a.md is satisfied by the advisory never running at all.
  [[ "$output" == *"b.md"* ]]
  [[ "$output" != *"a.md"* ]]
}

@test "post: flags an ADDED weak line even though its authored description is kept" {
  # fill-if-empty declines to touch the frontmatter here, but the index line is
  # still the canonical routing key — so the advisory must not ride on the sync.
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: authored prose\nmetadata:\n  type: reference\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '# Memory Index\n' > "$stash"
  printf -- '# Memory Index\n- [A](a.md) — hidden channel, model dependent\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  json="$output"
  run grep '^description:' memory/a.md
  [ "$output" = 'description: authored prose' ]   # untouched, as before
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [[ "$output" == *"a.md"* ]]
  [[ "$output" == *"trigger"* ]]
}

@test "post: warns past the byte threshold, states pct and the hard limit only" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" GITLORE_INDEX_BUDGET_BYTES=200
  hook="$(printf '%0.sx' $(seq 1 190))"
  # frontmatter already matches the hook, so the routine sync stays silent
  # (no "replaced" bullets) and the additionalContext carries ONLY the
  # budget advisory — isolates the assertion below from the sync's own bullets.
  printf -- '---\ndescription: "%s"\nmetadata:\n  type: feedback\n---\n' "$hook" > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — %s\n' "$hook" > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  json="$output"
  pct=$(( $(wc -c < memory/MEMORY.md) * 100 / 200 ))
  # Exact blocks, not a presence check paired with the absence of wording no
  # producer emits. The fixture keeps the sync itself silent, so each channel
  # carries the advisory and nothing else — and an equality catches an added
  # rationale line, a dropped clause and a reworded one alike, where refuting a
  # phrase production never had could only ever pass.
  run jq -r '.systemMessage' <<<"$json"
  [ "$output" = "gitlore: MEMORY.md is at ${pct}% of the 200-byte always-loaded budget" ]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$output" = "MEMORY.md is at ${pct}% of the 200-byte budget. Past 24.4KB, Claude Code's own loader silently truncates the tail of this file — entries beyond the cutoff never reach a session." ]
}

@test "post: does NOT re-warn the SAME session on a later over-threshold batch" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" GITLORE_INDEX_BUDGET_BYTES=200
  export TEST_SESSION_ID=same-session
  printf -- '---\nmetadata:\n  type: feedback\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — %s\n' "$(printf '%0.sx' $(seq 1 190))" > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  run jq -r '.systemMessage' <<<"$output"
  [[ "$output" == *"budget"* ]]

  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — %s\n' "$(printf '%0.sx' $(seq 1 190))" > "$stash"
  printf -- '- [A](a.md) — %s\n' "$(printf '%0.sy' $(seq 1 190))" > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  run jq -r '.systemMessage // ""' <<<"$output"
  [[ "$output" != *"budget"* ]]
}

@test "post: a DIFFERENT session still gets the full budget warning" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" GITLORE_INDEX_BUDGET_BYTES=200
  printf -- '---\nmetadata:\n  type: feedback\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — %s\n' "$(printf '%0.sx' $(seq 1 190))" > memory/MEMORY.md
  run post_stdin "$(TEST_SESSION_ID=session-one batch_payload "$PWD/memory/MEMORY.md")"
  run jq -r '.systemMessage' <<<"$output"
  [[ "$output" == *"budget"* ]]

  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — %s\n' "$(printf '%0.sx' $(seq 1 190))" > "$stash"
  printf -- '- [A](a.md) — %s\n' "$(printf '%0.sy' $(seq 1 190))" > memory/MEMORY.md
  run post_stdin "$(TEST_SESSION_ID=session-two batch_payload "$PWD/memory/MEMORY.md")"
  run jq -r '.systemMessage' <<<"$output"
  [[ "$output" == *"budget"* ]]
}

@test "gitlore_index_budget_nudge_reset: re-arms the warning for its session" {
  make_parent_with_memory
  session="reset-session"
  marker=$(gitlore_index_budget_nudge_file memory "$session")
  mkdir -p "$(dirname "$marker")"
  touch "$marker"
  [ -f "$marker" ]
  gitlore_index_budget_nudge_reset memory "$session"
  [ ! -f "$marker" ]
}

# shellcheck disable=SC2016   # literal backticks/$VAR are the fixture text
@test "post: stays silent about the budget below the threshold" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" GITLORE_INDEX_BUDGET_BYTES=100000
  printf -- '---\nmetadata:\n  type: feedback\n---\ndescription\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old\n' > "$stash"
  printf -- '- [A](a.md) — new `token`\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  run jq -r '.systemMessage // ""' <<<"$output"
  [[ "$output" != *"budget"* ]]
}

# shellcheck disable=SC2016   # literal backticks are the fixture text
@test "post: an advisory-only batch still emits (nothing was propagated)" {
  # The frontmatter already matches, so the sync itself has no news — the
  # advisory must not be gated behind a replacement.
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: "thin prose here"\nmetadata:\n  type: reference\n---\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  printf -- '- [A](a.md) — old `hook`\n' > "$stash"
  printf -- '- [A](a.md) — thin prose here\n' > memory/MEMORY.md
  run post_stdin "$(batch_payload "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$output"
  [[ "$output" == *"trigger"* ]]
}
