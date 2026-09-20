#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# index_pairs / set_frontmatter_description / get_frontmatter_description
# library units, plus the per-agent pre-image / compose-stamp path helpers.
# The pre/post hook behaviour lives in tests/index_sync_post.bats,
# tests/index_sync_propagation.bats, tests/index_sync_relay.bats,
# tests/index_sync_relay_refusals.bats and tests/index_sync_advisories.bats.

load helpers/setup
load helpers/fixtures
load helpers/index-sync

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
