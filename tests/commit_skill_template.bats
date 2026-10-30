#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# The gitlore:commit skill teaches a summary format and bin/gitlore-commit
# parses it. Drift between the two (the first template put the subject line
# above the first section header and was refused on first real use) shows only
# when the skill's own template is piped to the command, so this suite extracts
# the template from the skill body, fills its placeholders, and commits it.

SKILL="$PLUGIN_ROOT/skills/commit/SKILL.md"
GITLORE_COMMIT="$PLUGIN_ROOT/bin/gitlore-commit"

# The skill's template is the first ```text fenced block after the line
# "Template".
extract_template() {
  awk '
    /^Template/ { seen = 1; next }
    seen && !open && /^```text[[:space:]]*$/ { open = 1; next }
    open && /^```[[:space:]]*$/ { exit }
    open { print }
  ' "$SKILL"
}

# Fill every placeholder: tier and slug names, and each subject line.
fill_template() {
  sed -e 's/<tier>/ddaanet/g' \
    -e 's/<slug>/notes/g' \
    -e 's/^<subject line for the tier commit>$/ddaanet: record the shared hook/' \
    -e 's/^<subject line for the root commit>$/memory: record the root fact/'
}

make_two_dirty_stores() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  echo "root fact" > memory/notes.md
  seed_tier_bullet ddaanet shared.md "fresh hook"
}

@test "the skill's template is extractable and fills to a summary with no placeholder left" {
  template="$(extract_template)"
  [ -n "$template" ]
  [[ "$template" == *"== <tier> =="* ]]
  [[ "$template" == *"== memory =="* ]]
  filled="$(printf '%s\n' "$template" | fill_template)"
  [[ "$filled" == *"== ddaanet =="* ]]
  # A placeholder the fill does not know is a template change this suite must
  # learn, not a line to pipe through as literal text.
  [[ "$filled" != *"<"*">"* ]]
}

@test "the skill's filled template commits through bin/gitlore-commit, one section per store" {
  make_two_dirty_stores
  tier_before=$(git -C memory/ddaanet rev-parse HEAD)
  root_before=$(git -C memory rev-parse HEAD)
  extract_template | fill_template > "$BATS_TEST_TMPDIR/summary.txt"

  run --separate-stderr bash -c "'$GITLORE_COMMIT' < '$BATS_TEST_TMPDIR/summary.txt'"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$tier_before" ]
  [ "$(git -C memory rev-parse HEAD)" != "$root_before" ]
  [ "$(git -C memory/ddaanet log -1 --pretty=%s)" = "ddaanet: record the shared hook" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the root fact" ]
  # The tier paragraphs land in the tier, the root paragraph in root, and no
  # header line leaks into either message.
  [[ "$(git -C memory/ddaanet log -1 --pretty=%B)" == *"**New ddaanet/notes:**"* ]]
  [[ "$(git -C memory/ddaanet log -1 --pretty=%B)" != *"**Remove"* ]]
  [[ "$(git -C memory log -1 --pretty=%B)" == *"**Remove notes:**"* ]]
  [[ "$(git -C memory log -1 --pretty=%B)" != *"**New"* ]]
  [[ "$(git -C memory/ddaanet log -1 --pretty=%B)$(git -C memory log -1 --pretty=%B)" != *"=="* ]]
  [ -z "$(git -C memory status --porcelain)" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}
