#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# D70: the summary is the script's only input, on stdin, and carries one
# `== <store> ==` section per store with changes (`memory` for root, a tier's
# mount name for a tier). Every refusal exits 2 before anything is committed
# and points at /gitlore:commit. The summaries here are written out literally:
# the other suites build theirs with commit_sections.
#
# Not covered: a terminal on stdin. bats cannot allocate one without a pty
# harness, and the refusal it would test is the same usage exit as an empty
# summary.

# A root and a tier both holding changes: a root fact file, and a tier carrier
# line with the fact file it names.
make_two_dirty_stores() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  echo "root fact" > memory/notes.md
  seed_tier_bullet ddaanet shared.md "fresh hook"
  root_head=$(git -C memory rev-parse HEAD)
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
}

# Nothing landed in either store and the run left no file under .claude/.
assert_nothing_committed() {
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]
  [ -n "$(git -C memory status --porcelain)" ]
  [ -z "$(claude_files)" ]
}

# A refusal: exit 2, the pointer to the skill, and nothing committed.
assert_refused() {
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
  assert_nothing_committed
}

@test "an empty stdin exits 2 with nothing committed" {
  make_two_dirty_stores
  run --separate-stderr bash "$CMD" </dev/null
  assert_refused
}

@test "an all-whitespace stdin exits 2 with nothing committed" {
  make_two_dirty_stores
  run --separate-stderr bash "$CMD" <<<$'\n  \n\t\n'
  assert_refused
}

@test "an empty stdin exits 2 even when every store is clean" {
  # The refusal comes before any store is read, so a clean store does not turn
  # an empty summary into a quiet success.
  make_parent_with_memory
  run --separate-stderr bash "$CMD" </dev/null
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
}

@test "an all-whitespace stdin exits 2 even when every store is clean" {
  # With stores that have changes, a blank summary is also refused for lacking
  # a section; only clean stores show the blank check itself.
  make_parent_with_memory
  run --separate-stderr bash "$CMD" <<<$'\n  \n\t\n'
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
}

@test "a headerless summary is refused when only the tier changed, and the tier stays untouched" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  # A fresh mount has no local `live`; one gives the "unmoved" check something
  # a commit that landed would have advanced.
  git -C memory/ddaanet branch -f live
  seed_tier_bullet ddaanet shared.md "fresh hook"
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  tier_live=$(git -C memory/ddaanet rev-parse live)
  root_head=$(git -C memory rev-parse HEAD)

  run --separate-stderr commit_with "memory: record the shared fact"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
  # Nothing reached the shared store: its head, its live and its worktree.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live" ]
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ]
  [ -z "$(claude_files)" ]
}

@test "a store with changes and no section is refused" {
  make_two_dirty_stores
  run --separate-stderr commit_with "== memory ==
memory: record the root fact"
  assert_refused
}

@test "a section naming a store with nothing to commit is refused" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  echo "root fact" > memory/notes.md   # the tier stays clean
  root_before=$(git -C memory rev-parse HEAD)
  tier_before=$(git -C memory/ddaanet rev-parse HEAD)

  run --separate-stderr commit_with "== ddaanet ==
memory: record a tier fact
== memory ==
memory: record the root fact"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
  [[ "$stderr" == *"ddaanet"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$root_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_before" ]
  [ -n "$(git -C memory status --porcelain)" ]
  [ -z "$(claude_files)" ]
}

@test "a section naming an unmounted store is refused" {
  make_two_dirty_stores
  run --separate-stderr commit_with "== ddaanet ==
memory: record the tier fact
== nosuchtier ==
memory: record a fact for nobody
== memory ==
memory: record the root fact"
  assert_refused
  [[ "$stderr" == *"nosuchtier"* ]]
}

@test "a store appearing twice is refused" {
  make_two_dirty_stores
  run --separate-stderr commit_with "== ddaanet ==
memory: record the tier fact
== memory ==
memory: record the root fact
== memory ==
memory: record it again"
  assert_refused
}

@test "text before the first header is refused" {
  make_two_dirty_stores
  run --separate-stderr commit_with "a preamble that belongs to no store
== ddaanet ==
memory: record the tier fact
== memory ==
memory: record the root fact"
  assert_refused
}

@test "a MEMORY.md-only root change needs no section and gets its own index commit" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  seed_tier_bullet ddaanet shared.md "fresh hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  [ "$(git -C memory status --porcelain -- . ':!ddaanet' ':!MEMORY.md')" = "" ]

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet log -1 --pretty=%s)" = "memory: record the shared fact" ]
  # The canned message names the tier whose index line the commit captures.
  [ "$(git -C memory log -1 --pretty=%s)" = "Index lines from ddaanet" ]
  [ -z "$(git -C memory status --porcelain)" ]
  git -C memory show --name-only --pretty= HEAD | grep -qxF MEMORY.md
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ -z "$(claude_files)" ]
}

@test "a MEMORY.md change rides in root's own commit beside a memory section" {
  make_two_dirty_stores
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  root_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr commit_with "== ddaanet ==
memory: record the tier fact
== memory ==
memory: record the root fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the root fact" ]
  git -C memory show --name-only --pretty= HEAD | grep -qxF MEMORY.md
  git -C memory show --name-only --pretty= HEAD | grep -qxF notes.md
  [ -z "$(git -C memory status --porcelain)" ]
  # One root commit for both, not an index commit beside the section's.
  [ "$(git -C memory rev-list --count "$root_before"..HEAD)" -eq 1 ]
}

@test "a two-store run lands each section verbatim in its own store and no other store's text" {
  make_two_dirty_stores
  tier_text="ddaanet: record the shared hook

The tier body paragraph, which only the tier carries."
  root_text="memory: record the root fact

The root body paragraph, which only root carries."

  run --separate-stderr commit_with "== ddaanet ==
$tier_text
== memory ==
$root_text"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet log -1 --pretty=%B)" = "$tier_text" ]
  [ "$(git -C memory log -1 --pretty=%B)" = "$root_text" ]
  # Neither store's message carries the other's text, or a header line.
  [[ "$(git -C memory/ddaanet log -1 --pretty=%B)" != *"root"* ]]
  [[ "$(git -C memory log -1 --pretty=%B)" != *"tier"* ]]
  [[ "$(git -C memory/ddaanet log -1 --pretty=%B)" != *"=="* ]]
  [[ "$(git -C memory log -1 --pretty=%B)" != *"=="* ]]
  [ -z "$(git -C memory status --porcelain)" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ -z "$(claude_files)" ]
}

@test "tiers are committed before root" {
  make_two_dirty_stores
  order="$BATS_TEST_TMPDIR/commit-order"
  : > "$order"
  stub_commit_script "git() {
  case \" \$* \" in
    *\" commit \"*) printf '%s\\n' \"\$*\" >> '$order' ;;
  esac
  command git \"\$@\"
}"

  run --separate-stderr commit_with "== ddaanet ==
memory: record the tier fact
== memory ==
memory: record the root fact"
  [ "$status" -eq 0 ]
  [ -s "$order" ]
  # First commit invocation is the tier's; the last is root's.
  [[ "$(head -1 "$order")" == *"memory/ddaanet"* ]]
  [[ "$(tail -1 "$order")" != *"memory/ddaanet"* ]]
}

@test "an empty stdin exits 2 even where gitlore is not configured" {
  # The stdin check comes first, ahead of the activation guards.
  run --separate-stderr bash "$CMD" </dev/null
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
}

@test "with every store clean, any non-empty summary exits 0 and commits nothing" {
  # The guards come before the section check, so a summary the check would
  # refuse is moot when there is nothing to commit.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  root_before=$(git -C memory rev-parse HEAD)
  tier_before=$(git -C memory/ddaanet rev-parse HEAD)

  for text in "a preamble that belongs to no store" "== nosuchtier ==
memory: for nobody" "== memory ==
memory: nothing here
== memory ==
memory: twice"; do
    run --separate-stderr commit_with "$text"
    [ "$status" -eq 0 ]
  done
  [ "$(git -C memory rev-parse HEAD)" = "$root_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_before" ]
  [ -z "$(claude_files)" ]
}

@test "a tier change alone takes no section for root and gets the canned index commit" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  seed_tier_bullet ddaanet shared.md "fresh hook"

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet log -1 --pretty=%s)" = "memory: record the shared fact" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "Index lines from ddaanet" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a root MEMORY.md line with a bare path is root content and needs a memory section" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  printf -- '---\nname: local\ndescription: ""\n---\n\nbody\n' > memory/local.md
  commit_memory_state   # local.md tracked, so only the index line is a root change
  seed_tier_bullet ddaanet shared.md "fresh hook"
  seed_root_bullet "local.md" "a local fact"
  root_head=$(git -C memory rev-parse HEAD)
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]
  [ -z "$(claude_files)" ]
}

@test "a root MEMORY.md change with no link line is root content and needs a memory section" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  seed_tier_bullet ddaanet shared.md "fresh hook"
  printf 'Hand-edited note, no link.\n' >> memory/MEMORY.md
  root_head=$(git -C memory rev-parse HEAD)
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ -z "$(claude_files)" ]

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact
== memory ==
memory: record the note"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the note" ]
}

@test "a tier whose mount name has a space is a tier-only root change, not root content" {
  make_parent_with_memory
  make_tier_in_memory "my tier"
  set_tier_manifest "my tier"
  commit_memory_state
  seed_tier_bullet "my tier" shared.md "fresh hook"

  run --separate-stderr commit_with "== my tier ==
memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C "memory/my tier" log -1 --pretty=%s)" = "memory: record the shared fact" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "Index lines from my tier" ]
  [ "$(git -C memory rev-parse "HEAD:my tier")" = "$(git -C "memory/my tier" rev-parse HEAD)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "the canned index commit names every tier whose index lines it captures, not only a moved gitlink" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory other
  set_tier_manifest ddaanet other
  seed_tier_bullet other fact.md "a fact"
  git -C memory/other add -A
  GITLORE_MEMORY_COMMIT=1 git -C memory/other commit -q -m "other: fact"
  commit_memory_state
  seed_tier_bullet ddaanet shared.md "fresh hook"
  seed_root_bullet "other/fact.md" "a fact"

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "Index lines from ddaanet, other" ]
  [ -z "$(git -C memory status --porcelain)" ]
}
