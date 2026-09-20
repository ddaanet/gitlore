#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Routing-key advisories: the literal-token heuristic, frontmatter type
# lookup, the index size budget, and the post hook's advisory channel.

load helpers/setup
load helpers/fixtures
load helpers/index-sync

# shellcheck disable=SC1090
setup() { setup_tmp_repo; . "$SRC"; }
teardown() { teardown_tmp_repo; }

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

@test "post: notes the size past the byte threshold, states pct and the hard limit only" {
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
  [ "$output" = "gitlore: MEMORY.md is at ${pct}% of the 200-byte always-loaded budget — a size notice, nothing to act on" ]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$output" = "MEMORY.md is at ${pct}% of the 200-byte budget. This is ambient information about the store, not a task: the fact just written stands, and nothing here asks for curation now or says any particular line should go. What the number is for: past 24.4KB, Claude Code's own loader silently truncates the tail of this file, so entries beyond the cutoff never reach a session. Curation is a deliberate store-wide pass — /gitlore:index-audit — run when it is asked for." ]
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
