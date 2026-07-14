#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

SRC="$PLUGIN_ROOT/scripts/lib/index-sync.sh"

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
