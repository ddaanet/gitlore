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

@test "set_frontmatter_description: no .gitlore.tmp survives when awk itself fails (not the redirect)" {
  printf -- '---\ndescription: old\n---\n' > f.md
  # Shadow awk with a stub that always fails, so the redirect (which creates
  # f.md.gitlore.tmp) succeeds but the command itself does not — distinct
  # from the chmod-555 case, which fails the redirect before awk ever runs.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  printf '#!/bin/sh\nexit 1\n' > "$fakebin/awk"
  chmod +x "$fakebin/awk"
  PATH="$fakebin:$PATH" run gitlore_set_frontmatter_description f.md "new"
  [ "$status" -ne 0 ]                      # failure status preserved
  [ ! -e f.md.gitlore.tmp ]                # no leftover temp file
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

POST="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"

post_stdin() { printf '%s' "$1" | bash "$POST"; }

# PostToolBatch payload: every call of the turn under .tool_calls[], so the
# sync runs once per batch however many Edits it contains. $1.. = file paths.
batch_payload() {
  local f json='[]'
  for f in "$@"; do
    json=$(jq -c --arg f "$f" '. + [{tool_name:"Edit",tool_input:{file_path:$f}}]' <<<"$json")
  done
  jq -n --argjson c "$json" --arg s "${TEST_SESSION_ID:-test-session}" \
    '{hook_event_name:"PostToolBatch", session_id:$s, tool_calls:$c, tool_results:[]}'
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
