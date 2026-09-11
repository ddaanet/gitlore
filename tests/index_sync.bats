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
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]
  grep -qF 'reset frontmatter to match MEMORY.md' "$marker"
  grep -qF '• a.md:' "$marker"
}

# The positive half: a keyed marker staged directly (Item 3.1 slice 1,
# already committed) is folded into the next unkeyed post-hook run that
# itself reaches the report path — it must have a baseline and an actual
# change of its own, since both hooks exit upstream of the report path (and
# so of the drain) when nothing they watch changed.
@test "an unkeyed index-sync run folds in the marker" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  gitlore_relay_write memory a1 "keyed relay sysmsg a1" "keyed relay ctx a1"
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]
  payload=$(jq -n --arg f "$abs" \
    '{tool_name:"Edit",tool_input:{file_path:$f},agent_type:"general-purpose"}')
  printf '%s' "$payload" | bash "$PRE"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  run post_stdin "$(TEST_AGENT_TYPE=general-purpose batch_payload "$abs")"
  [ "$status" -eq 0 ]
  json="$output"
  # Per channel, not over the raw JSON blob: the framing line and the body
  # both reach additionalContext too, so a substring match on the whole object
  # passes for a fold that reached only the model's channel and never the
  # user's.
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reset frontmatter to match MEMORY.md"* ]]
  [[ "$output" == *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"keyed relay sysmsg a1"* ]]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"keyed relay ctx a1"* ]]
  [ ! -f "$marker" ]
}

# The constraint the pair above cannot see, on this hook's own emission guard
# (index-sync-post.sh:243): a parent-side run whose ONLY report is a relayed
# one must still emit. A fold placed after that guard passes both cases above
# — each gives the hook a report of its own — and silently drops the relay
# here.
#
# The index change is real: the pre-image holds `old hook` and the post-batch
# index `new hook`, so the hook runs past the `cmp -s` bail and through the
# loop. It has nothing to say about it because a.md already carries that
# description, so nothing is news. The description goes in UNQUOTED and the
# sync normalizes it, which is what proves the loop ran rather than the hook
# exiting upstream of the report path — with an empty own-report there is no
# other observable.
@test "an unkeyed index-sync run with no report of its own still emits the relay" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: new hook\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  gitlore_relay_write memory a1 "keyed relay sysmsg a1" "keyed relay ctx a1"
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]
  payload=$(jq -n --arg f "$abs" \
    '{tool_name:"Edit",tool_input:{file_path:$f},agent_type:"general-purpose"}')
  printf '%s' "$payload" | bash "$PRE"
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md
  run post_stdin "$(TEST_AGENT_TYPE=general-purpose batch_payload "$abs")"
  [ "$status" -eq 0 ]
  json="$output"
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new hook"' ]
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reset frontmatter to match MEMORY.md"* ]]
  [[ "$output" == *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"keyed relay sysmsg a1"* ]]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"keyed relay ctx a1"* ]]
  [ ! -f "$marker" ]
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

# --- relay markers (Item 3.1) -------------------------------------------------
#
# A hook firing inside a subagent has its report confined to that subagent's
# own transcript, so the relay stages it in a keyed marker for the next
# parent-side (unkeyed) run to fold in and remove. Two channels — sysmsg is
# the user's, ctx is the model's — must not cross-contaminate on drain.

@test "relay_marker_file suffixes the agent id" {
  make_parent_with_memory
  base=$(git -C memory rev-parse --git-path gitlore-relay)
  # Unsuffixed halves first: under errexit an assertion behind a failing one
  # never runs, and these are the two that hold against an inert stub.
  # Equality against the `rev-parse --git-path` name rather than a trailing
  # glob, for the reason the preimage/compose cases above give: it pins the
  # file inside the memory submodule's gitdir and rejects a `-` appended for
  # an empty id, a doubled suffix and a partial one.
  run gitlore_relay_marker_file memory
  [ "$status" -eq 0 ]
  [ "$output" = "$base" ]
  run gitlore_relay_marker_file memory ""
  [ "$status" -eq 0 ]
  [ "$output" = "$base" ]
  run gitlore_relay_marker_file memory a1
  [ "$status" -eq 0 ]
  [ "$output" = "$base-a1" ]
}

@test "relay_write then relay_drain splits the two channels and removes the marker" {
  make_parent_with_memory
  run gitlore_relay_write memory a1 "S1" "C1"
  [ "$status" -eq 0 ]
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]

  # Not `run`: the drain's whole output is two variables, which a subshell
  # would discard. `|| rc=$?` keeps errexit from turning a non-zero return
  # into an aborted test instead of a failed assertion.
  rc=0
  gitlore_relay_drain memory || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"C1"* ]]
  # Each block carries one framing line naming its agent, in both channels.
  [[ "$GITLORE_RELAY_SYSMSG" == *"a1"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"a1"* ]]
  # The cross-check: a drain that emitted the marker whole into both
  # variables — never splitting on the `--- gitlore-relay-ctx ---` line —
  # passes every assertion above.
  [[ "$GITLORE_RELAY_SYSMSG" != *"C1"* ]]
  [[ "$GITLORE_RELAY_CTX" != *"S1"* ]]
  # A drain that folds without unlinking re-emits the block on every later
  # parent-side batch.
  [ ! -f "$marker" ]
}

# Item 3.1 slice 2.5: two PostToolBatch hooks — index-sync-post.sh and
# index-compose.sh — now stage to this SAME keyed marker within one batch, and
# gitlore_relay_write's single `>` redirect makes the second call truncate the
# first's report instead of merging with it. This is the mechanism, isolated
# from either hook: two writes under the same agent id, one drain.
@test "relay_write merges a second report into an existing marker" {
  make_parent_with_memory
  run gitlore_relay_write memory a1 "S1" "C1"
  [ "$status" -eq 0 ]
  marker=$(gitlore_relay_marker_file memory a1)
  # The single-write path first, byte for byte. Merging per channel was chosen
  # over keying a second marker precisely because a first write to a fresh
  # marker stays byte-identical to today's, so every committed slice-1
  # contract case still describes the helper — and nothing else in the suite
  # pins those bytes: the slice-1 cases all read the DRAINED channels, which
  # several different file formats produce. `$(cat …)` drops the file's final
  # newline, so the literal stops at C1.
  [ "$(cat "$marker")" = '--- gitlore-relay-sysmsg ---
S1
--- gitlore-relay-ctx ---
C1' ]

  run gitlore_relay_write memory a1 "S2" "C2"
  [ "$status" -eq 0 ]

  # ONE marker, not two — counted before the drain removes them, and over the
  # whole `gitlore-relay-*` family rather than the `a1` name alone. An
  # implementation that side-steps the merge by keying a second file
  # (`gitlore-relay-a1-2`) leaves the `a1` marker in place and drains both, so
  # it satisfies every assertion phrased in terms of `$marker`, and every
  # count of the `--- gitlore-relay agent a1 ---` line too — that literal does
  # not occur in the `agent a1-2` frame the second file earns. Measured: with
  # `relay_write` mutated to that shape, both suites pass entire.
  # `-print0` into `read -r -d ''` rather than a glob, mirroring the drain's
  # own enumeration: nothing sanitizes the gitdir prefix and it may hold a
  # space.
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  markers=0
  while IFS= read -r -d '' _; do
    markers=$((markers + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' -print0)
  [ "$markers" -eq 1 ]

  rc=0
  gitlore_relay_drain memory || rc=$?
  [ "$rc" -eq 0 ]

  # Exact blocks, not substrings: one framing line for a1, both bodies under
  # it in write order, each on its own channel. A substring pair — `*"S1"*"S2"*`
  # plus `!= *"C1"*` — states the same thing more weakly and buys a vacuity
  # problem with it, since under errexit each cross-check runs only when the
  # one before it held. The expected text is written out here rather than
  # rebuilt from the marker, so the assertion knows the answer independently
  # of the code under test. It pins the join too: bodies are line-oriented and
  # concatenate with a single newline, the same way index-sync-post.sh already
  # joins its own several sysmsg blocks.
  [ "$GITLORE_RELAY_SYSMSG" = '--- gitlore-relay agent a1 ---
S1
S2
' ]
  [ "$GITLORE_RELAY_CTX" = '--- gitlore-relay agent a1 ---
C1
C2
' ]
}

@test "relay_drain folds two markers in filename order, over a gitdir path holding a space" {
  # Built out of line rather than through make_parent_with_memory: the
  # contract requires the enumeration to survive a space in the gitdir path,
  # and the cached fixture's path has none, so an `ls` pipeline or an
  # unquoted glob passes every other case in this section. Two markers at
  # once because the fold is specified in filename order.
  root="$TMP_REPO/has space"
  _gitlore_build_parent_with_memory "$root" memory
  mem="$root/memory"
  case "$(gitlore_relay_marker_file "$mem")" in
    *\ *) : ;;                             # the fixture really is spaced
    *) echo "fixture gitdir path has no space" >&2; return 1 ;;
  esac

  run gitlore_relay_write "$mem" a1 "S-one" "C-one"
  [ "$status" -eq 0 ]
  run gitlore_relay_write "$mem" a2 "S-two" "C-two"
  [ "$status" -eq 0 ]

  rc=0
  gitlore_relay_drain "$mem" || rc=$?
  [ "$rc" -eq 0 ]
  # Order, not mere presence: `*"S-one"*"S-two"*` fails on a reversed fold.
  [[ "$GITLORE_RELAY_SYSMSG" == *"S-one"*"S-two"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"C-one"*"C-two"* ]]
  [ ! -f "$(gitlore_relay_marker_file "$mem" a1)" ]
  [ ! -f "$(gitlore_relay_marker_file "$mem" a2)" ]
}

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
  gitlore_relay_drain memory || rc=$?
  [ "$rc" -eq 0 ]
  [ -z "$GITLORE_RELAY_SYSMSG" ]
  [ -z "$GITLORE_RELAY_CTX" ]
  [ -f "$decoy" ]
}

# Item 3.1 slice 4, Group A. The drain enumerates keyed markers only
# (gitlore_relay_drain's own `-name 'gitlore-relay-*'` glob), so an unkeyed
# write strands a file nothing folds and nothing removes. Red today: the guard
# does not exist, so this write currently succeeds and lands on the bare,
# unsuffixed `gitlore-relay` name.
#
# The runbook names one case over both of the write's failure inputs; it is two
# bodies here because the squatted-path half below already passes. Behind this
# one it would never run under bats' errexit, and its first real execution
# would be at GREEN — the shape that makes a born-green assertion evidence of
# nothing.
@test "relay_write refuses an empty agent id" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  run gitlore_relay_write memory "" "S" "C"
  [ "$status" -ne 0 ]
  bare=$(gitlore_relay_marker_file memory "")
  [ ! -e "$bare" ]

  # Nothing landed anywhere in the gitdir either — over the whole
  # `gitlore-relay*` family rather than the single name checked above, so a
  # write that fell back to some other suffix is caught too.
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay*' -print0)
  [ "$count" -eq 0 ]
}

# Item 3.1 slice 4, Group B. Something else already occupies the keyed name as
# a directory — the shape a failed relay write leaves behind (F5). Born green:
# the write's redirect fails with "Is a directory" and writes nothing, so this
# is a regression pin rather than a red. Proven non-vacuous by the mutation
# recorded in the slice-4 test review — give gitlore_relay_write a trailing
# `return 0` and this case reds on its status assertion, which is the whole
# "returns non-zero" half of the contract.
#
# The squat directory is left standing: teardown_tmp_repo's `rm -rf` removes
# the fixture tree whether or not the body ran to the end, and a cleanup line
# here would not run on a mid-body failure anyway.
@test "relay_write refuses a squatted marker path" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  squat=$(gitlore_relay_marker_file memory a1)
  mkdir "$squat"
  run gitlore_relay_write memory a1 "S" "C"
  [ "$status" -ne 0 ]
  [ -d "$squat" ]
  [ ! -f "$squat" ]

  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay*' -print0)
  [ "$count" -eq 0 ]
}

# Item 3.1 slice 4, Group B. The slice 2.5 review fixed this and could not pin
# it: no frozen case writes an empty ctx. Reachable in production —
# index-sync-post.sh's `failed` block sets a sysmsg with no ctx, so a subagent
# batch whose frontmatter sync fails and whose compose then reports takes
# exactly this path.
@test "relay_write joins a channel only when the old body is non-empty" {
  make_parent_with_memory
  run gitlore_relay_write memory a1 "S" ""
  [ "$status" -eq 0 ]
  run gitlore_relay_write memory a1 "S2" "C2"
  [ "$status" -eq 0 ]

  rc=0
  gitlore_relay_drain memory || rc=$?
  [ "$rc" -eq 0 ]
  # Exact block, not a substring on "C2" alone: an unguarded join opens the
  # ctx channel with a leading blank line ("" + "\n" + "C2"), which a
  # substring match would not catch.
  [ "$GITLORE_RELAY_CTX" = '--- gitlore-relay agent a1 ---
C2
' ]
}

# Item 3.1 slice 4, Group A (item-3-1-s3-code-review.md "Concern 1"). A marker
# whose mode is 0200 is found by `find -type f` (which screens non-files, not
# permissions) but cannot be opened by the drain's `awk`, which exits 2. Both
# real callers run the drain bare under `set -euo pipefail`, so today that
# takes the WHOLE caller down before it can emit anything of its own — not
# merely the relay.
#
# `run bash -c '...'` rather than `run gitlore_relay_drain memory`: bats'
# `run` itself suspends errexit for the call, which would mask exactly the
# defect under test. The synthetic script below reproduces a real hook's own
# shape — `set -euo pipefail`, the drain called bare, then a line standing in
# for the hook's own report — so the errexit that kills the caller today is
# the caller's own, not bats'.
@test "an unreadable marker costs the relay, not the hook" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  run gitlore_relay_write memory a1 "S" "C"
  [ "$status" -eq 0 ]
  marker=$(gitlore_relay_marker_file memory a1)
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
    gitlore_relay_drain "$2"
    printf "OWN REPORT\n"
  ' _ "$SRC" "$PWD/memory"
  # Guarded, not unconditional: a fixed drain folds the unreadable marker as an
  # empty block and removes it, and a bare chmod would then fail on a missing
  # path — killing the test on its own cleanup instead of on an assertion.
  [ -e "$marker" ] && chmod 0600 "$marker"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OWN REPORT"* ]]
  # ...and the marker it could not read is gone. Without this a drain that
  # skipped unreadable markers instead of folding-and-removing them satisfies
  # both assertions above while stranding the file, which costs every later
  # session the same drain — the failure the runbook names for this fix.
  [ ! -e "$marker" ]
}

# Item 3.1 slice 5 (item-3-1-s4-code-review.md §6). One layer out from the
# case above: the drain's own doc line claims "Always returns 0", but that
# does not hold for its bare `rm -f "$marker"` when the GITDIR ITSELF — not
# the marker — cannot be written. `-type f` screens the marker's own shape,
# not the permissions one level up, so a marker this drain can read fine
# still costs its caller everything once the remove fails. Both real callers
# run the drain bare under the hooks' own `set -euo pipefail`, so today that
# takes the whole caller down before it emits anything of its own.
@test "the drain survives a gitdir it cannot write" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  run gitlore_relay_write memory a1 "S" "C"
  [ "$status" -eq 0 ]
  marker=$(gitlore_relay_marker_file memory a1)
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  # r-x, no w: `find` can still enumerate and `awk` can still read the marker
  # (both need only read+execute on the directory), but the drain's `rm -f`
  # needs write on the directory it lives in, which this removes.
  chmod 0500 "$gitdir"

  # Plain `run`, not `run --separate-stderr`: the assertion below is a
  # substring on the synthetic hook's own line, which no diagnostic supplies,
  # and `--separate-stderr` stops shellcheck recognising `bash -c` and
  # linting the script below, trading that for nothing (same reasoning as the
  # marker-mode case above).
  run bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    . "$1"
    gitlore_relay_drain "$2"
    printf "OWN REPORT\n"
  ' _ "$SRC" "$PWD/memory"

  # Guarded, not unconditional: a fixed drain still fails its own `rm -f` here
  # (the point of the fixture), so the gitdir survives either way and the
  # guard is only for defensive symmetry with the marker-mode case above —
  # but restoring before the assertions is what lets teardown_tmp_repo's
  # `rm -rf` remove the tree afterwards regardless of which way this goes.
  # Nothing that can fail may be inserted between the chmod above and this
  # line: `run` never aborts the body, but an assertion there would leave the
  # gitdir at 0500, and teardown's `rm -rf` cannot unlink a single entry
  # inside it — measured, the whole fixture tree survives the run.
  [ -e "$gitdir" ] && chmod 0700 "$gitdir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OWN REPORT"* ]]
}

# Atomic relay write (follow-up to Item 3.1). The write's single `>`
# truncates the marker before any of its four printfs run, so a process that
# dies mid-write (kill, ENOSPC, EIO) leaves a torn prefix on the marker path,
# and the drain has no way to tell that from a whole one:
# `_gitlore_relay_sysblock` takes everything to EOF when the ctx delimiter
# never arrives, so the torn body is folded into the parent's report and its
# evidence rm -f'd — and since the write became a merge, a torn write now
# destroys the previously staged report too, not only its own. The fix
# writes to `$marker.tmp` and installs it with `mv` only once the write
# finishes, so a killed writer leaves a `.tmp` a fixed drain excludes and
# cleans up. These four cases pin the exclusion, that the exclusion is
# selective, the write's atomicity, and the cleanup of a stranded temp.
#
# The torn fixtures below are written directly rather than through
# gitlore_relay_write: the shape has to be an exact prefix of that function's
# four printfs cut after the second — sysmsg delimiter, body, nothing — which
# no completed call to the helper produces.

@test "relay_drain does not fold a stranded .tmp marker" {
  make_parent_with_memory
  # Derived from the helper rather than spelled out against the gitdir: a
  # killed writer's temp is whatever gitlore_relay_marker_file names for its
  # agent id, plus `.tmp`. A hand-built path would keep passing after a
  # rename of the marker family, testing a name nothing writes.
  tmp="$(gitlore_relay_marker_file memory orphan).tmp"
  {
    printf -- '--- gitlore-relay-sysmsg ---\n'
    printf 'TORN-BODY\n'
  } > "$tmp"

  # Alone in the gitdir, a .tmp must fold as if nothing were there — the
  # both-empty case a drain that treats it as a real marker cannot produce.
  rc=0
  gitlore_relay_drain memory || rc=$?
  [ "$rc" -eq 0 ]
  [ -z "$GITLORE_RELAY_SYSMSG" ]
  [ -z "$GITLORE_RELAY_CTX" ]
  # ...and the torn write's own evidence is still on disk. A drain that
  # excluded the .tmp from the fold but swept every .tmp in the gitdir
  # satisfies both assertions above while destroying exactly what the temp
  # exists to preserve — this one belongs to no marker the drain touched, so
  # only the writer that died knows what it holds. Red today for its own
  # reason (today's drain enumerates it and rm -f's it), proven so by a
  # reordered run recorded in the test review, since under errexit the two
  # assertions above die first.
  [ -e "$tmp" ]
}

# The selective half of the case above, as a test of its own rather than
# trailing it: behind a failing assertion it would never run under bats'
# errexit and its first real execution would be at GREEN — the shape the
# slice-4 cases above already name as making an assertion evidence of
# nothing.
@test "relay_drain still folds a real marker standing beside a stranded .tmp" {
  make_parent_with_memory
  tmp="$(gitlore_relay_marker_file memory orphan).tmp"
  {
    printf -- '--- gitlore-relay-sysmsg ---\n'
    printf 'TORN-BODY\n'
  } > "$tmp"
  run gitlore_relay_write memory a1 "S1" "C1"
  [ "$status" -eq 0 ]

  rc=0
  gitlore_relay_drain memory || rc=$?
  [ "$rc" -eq 0 ]
  # a1 is folded and framed on both channels, so the exclusion is selective
  # rather than the drain returning early at the first name it will not take.
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" == *"agent a1"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"C1"* ]]
  # ...and neither the torn body nor the agent id the .tmp's filename would
  # yield reaches either channel. Two strings, not one: the body proves the
  # content was not folded, `orphan` proves no framing line was emitted for
  # an agent that staged nothing.
  [[ "$GITLORE_RELAY_SYSMSG" != *"TORN-BODY"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" != *"orphan"* ]]
  [[ "$GITLORE_RELAY_CTX" != *"TORN-BODY"* ]]
  [[ "$GITLORE_RELAY_CTX" != *"orphan"* ]]
}

@test "relay_write does not destroy a staged report when its temp cannot be written" {
  make_parent_with_memory
  run gitlore_relay_write memory a1 "S1" "C1"
  [ "$status" -eq 0 ]
  marker=$(gitlore_relay_marker_file memory a1)
  before=$(cat "$marker")

  # The atomic write builds the new marker at `$marker.tmp` and only then
  # renames it into place; squatting that path with a directory is the
  # "squatted marker path" mechanism from slice 4, one path segment over, so
  # the write fails with the marker itself never opened. No root skip: a
  # redirect onto a directory is EISDIR, not a permission bit, so it fails
  # for root too — the same reason the slice-4 squat case carries none.
  #
  # The squat is left standing rather than rmdir'd at the end, for the reason
  # that case gives: teardown_tmp_repo's `rm -rf` removes the fixture tree
  # whether or not the body ran to the end, and a cleanup line here would not
  # run on a mid-body failure anyway.
  mkdir "$marker.tmp"

  run gitlore_relay_write memory a1 "S2" "C2"
  [ "$status" -ne 0 ]

  # The squat is untouched (nothing landed there) and the FIRST report is
  # still on disk byte for byte -- S2/C2 never overwrote it.
  [ -d "$marker.tmp" ]
  [ "$(cat "$marker")" = "$before" ]
}

# The cleanup half of the fix, pinned over a gitdir path holding a space,
# because this is the only case in the section that puts a `.tmp` on such a
# path: `rm -f "$marker.tmp"` is a new expansion of the unsanitized gitdir
# prefix, and unquoted it would remove the wrong paths, leave this one
# standing, and still exit 0. (The `mv` half needs no case of its own — the
# two-marker spaced case above writes and drains on the same fixture, and an
# unquoted rename there fails the write's own status assertion.)
#
# Born green: today's drain has no `.tmp` exclusion, so `gitlore-relay-a1.tmp`
# is enumerated as a marker in its own right (agent id `a1.tmp`) and the
# loop's ordinary `rm -f "$marker"` removes it — both files vanish today, but
# because each is independently drained-and-removed as a legitimate report,
# not because the cleanup step exists. Proven non-vacuous by mutation: add
# `'!' -name '*.tmp'` to the drain's `find` WITHOUT the `rm -f "$marker.tmp"`
# and this case reds on `[ ! -e "$marker.tmp" ]`, the exclusion alone meaning
# nothing ever reaches the temp to remove it.
@test "relay_drain removes a .tmp stranded alongside the marker it drains" {
  root="$TMP_REPO/has space"
  _gitlore_build_parent_with_memory "$root" memory
  mem="$root/memory"
  marker=$(gitlore_relay_marker_file "$mem" a1)
  case "$marker" in
    *\ *) : ;;                             # the fixture really is spaced
    *) echo "fixture gitdir path has no space" >&2; return 1 ;;
  esac

  run gitlore_relay_write "$mem" a1 "S1" "C1"
  [ "$status" -eq 0 ]
  # A temp a killed writer left behind for the SAME agent id -- distinct from
  # the orphan cases above, whose .tmp belongs to no real marker at all.
  {
    printf -- '--- gitlore-relay-sysmsg ---\n'
    printf 'STRANDED\n'
  } > "$marker.tmp"

  rc=0
  gitlore_relay_drain "$mem" || rc=$?
  [ "$rc" -eq 0 ]
  # The real marker was drained, not merely unlinked: without this a drain
  # that removed every `gitlore-relay-*` name and folded nothing satisfies
  # both existence assertions below.
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1"* ]]
  [ ! -e "$marker" ]
  [ ! -e "$marker.tmp" ]
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
