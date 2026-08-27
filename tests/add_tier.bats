#!/usr/bin/env bats
# scripts/add-tier.sh — mount (or create then mount) a memory tier. D17 3-iii.
# Each @test is its own subshell; per-test exports are consumed within that same
# test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

ADD_TIER="$PLUGIN_ROOT/scripts/add-tier.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  # Submodule adds from a local path need this; scoped to the test process
  # rather than written into anyone's global config.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always
}
teardown() { teardown_tmp_repo; }

# Write the add-tier intent file where the script looks for it.
write_intent() {
  mkdir -p .claude
  printf '%s\n' "$@" > .claude/gitlore-add-tier
}

# --- invocation path -------------------------------------------------------

@test "add-tier: the script is discoverable and executable" {
  [ -x "$ADD_TIER" ]
}

# --- mount -----------------------------------------------------------------

@test "add-tier: mount registers the tier in the memory store's own .gitmodules" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  [ -e memory/ddaanet/.git ]
  [ "$(git config --file memory/.gitmodules --get submodule.ddaanet.path)" = "ddaanet" ]
  # Discovery by enclosure: the PARENT's .gitmodules must not learn about it.
  run git config --file .gitmodules --get submodule.ddaanet.path
  [ "$status" -ne 0 ]
}

@test "add-tier: mount leaves the tier detached at live" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  git -C memory/ddaanet show-ref --verify --quiet refs/heads/live
  run git -C memory/ddaanet symbolic-ref -q HEAD
  [ "$status" -ne 0 ]                                    # detached
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$(git -C memory/ddaanet rev-parse live)" ]
}

# `submodule add` records the remote's DEFAULT branch, and the detach above then
# moves the tier onto `live`. `submodule update` pins from the memory store's
# INDEX (D43), so an unstaged move is walked back to the default branch at the
# next SessionStart — while the root index composed from the live carrier
# survives to describe facts the tier no longer holds. The mount advances a tier,
# so it owes the same staging every other advancing path performs.
@test "add-tier: mount stages the gitlink its detach moved" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  # `live` ahead of the default branch, so the detach genuinely moves HEAD and
  # the staged gitlink is not the one `submodule add` recorded.
  push_tier_fact ddaanet "- [x](x.md) — from live" >/dev/null
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  [ "$(git -C memory rev-parse :ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
}

@test "add-tier: mount makes NO commit inside the memory store" {
  make_parent_with_memory
  before=$(git -C memory rev-parse HEAD)
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  # The FR11 gate stays the sole committer; the staged .gitmodules is already
  # enough for discovery, which reads the working tree.
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
  run gitlore_tier_paths memory
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}

@test "add-tier: mount activates the tier as its own final step" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  # The intent already named this exact tier — no separate deliberate edit
  # needed to activate it.
  [ -f memory/.gitlore-tiers ]
  [ "$(cat memory/.gitlore-tiers)" = "ddaanet" ]
  [[ "$output" == *"activated"* ]]
  [[ "$output" == *".gitlore-tiers"* ]]
}

@test "add-tier: a second mount appends at the bottom, below an already-active tier" {
  make_parent_with_memory
  set_tier_manifest existing
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  # Lowest precedence: never outranks a tier this repo already trusted.
  [ "$(cat memory/.gitlore-tiers)" = "$(printf 'existing\nddaanet')" ]
}

@test "add-tier: a second mount does not weld onto an unterminated manifest" {
  # .gitlore-tiers is documented as hand-editable, so a writer that leaves the
  # last line bare (a hand edit, an agent Edit) must not have its entry welded
  # onto the next append — that silently drops both tiers from the manifest.
  make_parent_with_memory
  printf 'existing' > memory/.gitlore-tiers   # no trailing newline
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  [ "$(cat memory/.gitlore-tiers)" = "$(printf 'existing\nddaanet')" ]
  run gitlore_active_tiers memory
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'existing\nddaanet')" ]
}

@test "add-tier: mount reports the tier's routing guidance" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"org-wide facts for ddaanet projects"* ]]
}

@test "add-tier: mount reports the import line for a tier carrying shared-claude.md" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet live shared)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  # Repo-root relative, so appending it verbatim to CLAUDE.md resolves.
  [[ "$output" == *"@memory/ddaanet/shared-claude.md"* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
}

@test "add-tier: a tier with no shared-claude.md gets no import line" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  # A dangling `@` import loads nothing and says nothing, so the line is
  # reported only once the file is actually in the mounted tier.
  [[ "$output" != *"shared-claude"* ]]
}

@test "add-tier: mount stays quiet when CLAUDE.md already carries the import" {
  make_parent_with_memory
  printf '# Agent instructions\n\n@memory/ddaanet/shared-claude.md\n' > CLAUDE.md
  bare=$(make_tier_remote ddaanet live shared)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  # Same tier as the positive above; only CLAUDE.md differs.
  [[ "$output" != *"Append to CLAUDE.md"* ]]
}

@test "add-tier: mount consumes nothing — the caller owns the intent file" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  # The hook consumes it; keeping that in one place means a direct run is
  # repeatable and the hook's one-shot rule is testable on its own.
  [ -f .claude/gitlore-add-tier ]
}

@test "add-tier: a tier remote with no live branch mounts with a warning, not a failure" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet nolive)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [ -e memory/ddaanet/.git ]
  [[ "$output" == *"warnings"* ]]
  [[ "$output" == *"live"* ]]
}

# --- intent parsing --------------------------------------------------------

@test "add-tier: a description containing '=' and spaces survives parsing" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare" \
    "description=facts where a=b holds, spaces and all"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
}

@test "add-tier: an unknown intent key is an error, not a silent drop" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare" "descripton=typo"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown intent key"* ]]
  [ ! -e memory/ddaanet ]
}

@test "add-tier: a line that is not key=value is an error naming its number" {
  make_parent_with_memory
  write_intent "mode=mount" "just some prose"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 2"* ]]
}

@test "add-tier: blank lines and comments are ignored" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "# what this tier is for" "" "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [ -e memory/ddaanet/.git ]
}

@test "add-tier: a missing intent file fails without touching the store" {
  make_parent_with_memory
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no add-tier intent file"* ]]
}

# --- validation ------------------------------------------------------------

@test "add-tier: an unknown mode is refused" {
  make_parent_with_memory
  write_intent "mode=borrow" "name=ddaanet" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown mode"* ]]
}

@test "add-tier: mount without a url is refused" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"url="* ]]
}

@test "add-tier: create without a description is refused" {
  make_parent_with_memory
  write_intent "mode=create" "name=ddaanet" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"description="* ]]
}

@test "add-tier: a name containing a slash is refused" {
  make_parent_with_memory
  write_intent "mode=mount" "name=org/ddaanet" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"slash"* ]]
}

@test "add-tier: a name containing whitespace is refused (the manifest could never list it)" {
  make_parent_with_memory
  write_intent "mode=mount" "name=two words" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"whitespace"* ]]
  [ ! -e "memory/two words" ]
}

@test "add-tier: re-mounting an already-mounted tier is refused" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  write_intent "mode=mount" "name=ddaanet" "url=$TMP_REPO/.bare-ddaanet.git"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already"* ]]
}

@test "add-tier: a name whose directory already exists is refused" {
  make_parent_with_memory
  mkdir memory/ddaanet
  write_intent "mode=mount" "name=ddaanet" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

# --- url transport bounds -------------------------------------------------
#
# git's own protocol.ext.allow already defaults to `never` (2.47.3 refuses with
# "transport 'ext' not allowed"), so these pin the guard that makes the bound
# hold regardless of the user's git config — the hook runs outside the agent's
# sandbox, with network.

@test "add-tier: an ext:: transport-helper url is refused before git is reached" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=ext::sh -c 'touch $TMP_REPO/PWNED'"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"transport helper"* ]]
  [ ! -e "$TMP_REPO/PWNED" ]
  [ ! -e memory/ddaanet ]
}

@test "add-tier: an unknown url scheme is refused" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=ftp://example.com/repo.git"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scheme"* ]]
}

@test "add-tier: a url starting with '-' is refused (git would read it as an option)" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=--upload-pack=touch"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"option"* ]]
}

@test "add-tier: create refuses a transport-helper url before pushing to it" {
  make_parent_with_memory
  write_intent "mode=create" "name=orgwide" "url=ext::sh -c 'touch $TMP_REPO/PWNED'" \
    "description=org facts"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"transport helper"* ]]
  [ ! -e "$TMP_REPO/PWNED" ]
}

@test "add-tier: the ordinary remote spellings are accepted" {
  make_parent_with_memory
  # Reaching git is enough — these must fail on the network/path, not the
  # guard. A closed local port refuses instantly; a DNS-based unreachable
  # host (example.invalid) can stall for 10+ seconds per scheme behind a
  # proxying sandbox, which made this loop the suite's slowest single test.
  for u in "https://127.0.0.1:1/x.git" "ssh://git@127.0.0.1:1/x.git" \
           "git@127.0.0.1:x.git" "git://127.0.0.1:1/x.git"; do
    write_intent "mode=mount" "name=t" "url=$u"
    run bash "$ADD_TIER"
    [ "$status" -ne 0 ]                       # connection refused, of course
    [[ "$output" == *"submodule add failed"* ]]   # …but it got past the guard
  done
}

@test "add-tier: a bad url fails with git's own message and mounts nothing" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=$TMP_REPO/.no-such-remote.git"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"submodule add failed"* ]]
  [ ! -e memory/ddaanet ]
  run git config --file memory/.gitmodules --get submodule.ddaanet.path
  [ "$status" -ne 0 ]
}

@test "add-tier: refuses when the repo has no memory submodule" {
  # Bare repo from setup_tmp_repo, no memory.
  mkdir -p .claude
  printf 'mode=mount\nname=x\nurl=y\n' > .claude/gitlore-add-tier
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"memory submodule"* ]]
}

# --- create ----------------------------------------------------------------

@test "add-tier: create seeds the tier, pushes main and live, then mounts it" {
  make_parent_with_memory
  # An empty bare remote standing in for a freshly created GitHub repo.
  git init -q --bare "$TMP_REPO/.new-tier.git"
  write_intent "mode=create" "name=orgwide" "url=$TMP_REPO/.new-tier.git" \
    "description=Cross-project facts shared by all org repositories"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  # Default branch main with live alongside — a live default would be checked
  # out as a branch and break the ff-only propagation-in fetch.
  [ "$(git -C "$TMP_REPO/.new-tier.git" symbolic-ref --short HEAD)" = "main" ]
  git -C "$TMP_REPO/.new-tier.git" show-ref --verify --quiet refs/heads/main
  git -C "$TMP_REPO/.new-tier.git" show-ref --verify --quiet refs/heads/live

  # Mounted, detached at live, self-describing.
  [ -e memory/orgwide/.git ]
  run git -C memory/orgwide symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  grep -q 'description: "Cross-project facts shared by all org repositories"' \
    memory/orgwide/MEMORY.md
}

@test "add-tier: a description containing quotes seeds readable frontmatter" {
  # The description is agent-supplied prose. Interpolated raw into a double-
  # quoted YAML scalar it truncates at the first `"`, and the seeded carrier
  # then reads back as two garbage lines for the life of the tier.
  make_parent_with_memory
  git init -q --bare "$TMP_REPO/.new-tier.git"
  desc='Facts about the "core" team, a\b and all'
  write_intent "mode=create" "name=orgwide" "url=$TMP_REPO/.new-tier.git" \
    "description=$desc"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  run gitlore_get_frontmatter_description memory/orgwide/MEMORY.md
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$output" = "$desc" ]
}

@test "add-tier: create activates the tier too" {
  make_parent_with_memory
  git init -q --bare "$TMP_REPO/.new-tier.git"
  write_intent "mode=create" "name=orgwide" "url=$TMP_REPO/.new-tier.git" \
    "description=org facts"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [ "$(cat memory/.gitlore-tiers)" = "orgwide" ]
  [[ "$output" == *"activated"* ]]
}

@test "add-tier: create against an unreachable url mounts nothing" {
  make_parent_with_memory
  write_intent "mode=create" "name=orgwide" "url=$TMP_REPO/.no-such-remote.git" \
    "description=org facts"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not push"* ]]
  [ ! -e memory/orgwide ]
}

# --- the composed whole ----------------------------------------------------

@test "add-tier: mount activates the tier for composition without a further edit" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"
  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  run gitlore_active_tiers memory
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}
