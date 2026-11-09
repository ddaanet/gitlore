#!/usr/bin/env bats
# SessionStart moves no module (no-pin-loop plan, "Design"): a module is the
# root memory store or a tier, and the hook clones one that is missing, fetches
# read-only and reports. It does not put a tier back on, or ahead to, the
# commit memory records; it does not detach a tier or the memory store that sits
# on a named branch; and the pending check meets a tier off its pin as it
# stands, because nothing at SessionStart moves it onto the pin first — it
# refuses one ahead of its pin naming the take, which composes its lines up and
# records it, and writes no index.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory
load helpers/take-order

# --- fixtures -----------------------------------------------------------------

# Run SessionStart over the store as it stands. $hook_json keeps the output past
# later `run`s; $sys and $ctx are its two channels.
session_start_over_store() {
  enable_gitlore
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  hook_json="$output"
  sys=$(jq -r '.systemMessage // ""' <<<"$hook_json")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$hook_json")
}

# Every byte of memory's state a SessionStart must leave alone: root's index and
# the carrier, both statuses, the index's tier entries and the cached diff.
store_fingerprint() {
  cat memory/MEMORY.md memory/ddaanet/MEMORY.md
  git -C memory status --porcelain
  git -C memory/ddaanet status --porcelain
  git -C memory ls-files -s
  git -C memory diff --cached --stat
  git -C memory rev-parse HEAD
  git -C memory/ddaanet rev-parse HEAD
}

# The composed, committed store with its tier DETACHED, so a test that asserts
# "still attached" or "not moved" is not decided by the mount's named branch.
detached_pinned_store() {
  pinned_store_with_tier
  git -C memory/ddaanet checkout -q --detach
}

# --- a tier ahead of its pin stays where it is ---------------------------------

@test "SessionStart leaves a tier ahead of its pin on its own commit" {
  detached_pinned_store
  pin=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  ahead=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$ahead" != "$pin" ]

  session_start_over_store
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$ahead" ] || {
    printf 'the tier was moved from %s to %s (the pin is %s)\n' "$ahead" "$(git -C memory/ddaanet rev-parse HEAD)" "$pin" >&2
    return 1
  }
  [ "$(git -C memory rev-parse :ddaanet)" = "$pin" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}

@test "SessionStart over a tier ahead of its pin refuses it naming the take on both channels and writes no index" {
  # Fails under a hook that composes the tier's new line into root or stages
  # its gitlink, and under a pending check that reports a pass to run
  # (`gitlore-compose`) instead of refusing the tier ahead.
  detached_pinned_store
  pin=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  head=$(git -C memory/ddaanet rev-parse HEAD)
  before=$(store_fingerprint)

  session_start_over_store
  [ "$(store_fingerprint)" = "$before" ]
  tierline="tier 'ddaanet' is checked out at ${head:0:12}, ahead of the commit the memory store records at ${pin:0:12}: it was moved outside a completed take, so the root index has not taken its lines. Run /gitlore:merge, which composes them into the root index and records the tier."
  jq -e --arg l "$tierline" '.systemMessage | split("\n\n") | any(.[]; contains("gitlore: the memory indexes cannot be composed until these are fixed:") and contains($l))' <<<"$hook_json" >/dev/null || {
    printf 'no refusal paragraph for a tier ahead of its pin; systemMessage:\n%s\n' "$sys" >&2
    return 1
  }
  [[ "$ctx" == *"$tierline"* ]] || {
    printf 'no refusal for the agent; additionalContext lacks the tier line\n' >&2
    return 1
  }
  [[ "$sys" != *"gitlore-compose"* ]]
  [[ "$ctx" != *"gitlore-compose"* ]]
}

# --- a tier behind its pin stays where it is, and is reported ------------------

# The tier holds a second commit that memory records; the checkout is then sent
# back to the first, which is the state a raw pull in memory leaves.
tier_behind_its_pin() {
  detached_pinned_store
  old_pin=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  new_pin=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory add -- ddaanet
  git -C memory commit -qm "record the tier's second commit"
  git -C memory push -q . HEAD:refs/heads/live
  # Published, so the checkout `submodule update` used to make could succeed.
  git -C memory/ddaanet push -q origin HEAD:refs/heads/live
  git -C memory/ddaanet checkout -q --detach "$old_pin"
}

@test "SessionStart leaves a tier behind its pin where it is" {
  tier_behind_its_pin

  session_start_over_store
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$old_pin" ] || {
    printf 'the tier was moved to %s; the pin it is behind is %s\n' "$(git -C memory/ddaanet rev-parse HEAD)" "$new_pin" >&2
    return 1
  }
  [ "$(git -C memory rev-parse :ddaanet)" = "$new_pin" ]
}

@test "SessionStart reports a tier behind its pin, naming /gitlore:merge on both channels" {
  tier_behind_its_pin

  session_start_over_store
  [[ "$sys" == *"${old_pin:0:12}"* ]] || {
    printf 'no report names the tier commit %s; systemMessage:\n%s\n' "${old_pin:0:12}" "$sys" >&2
    return 1
  }
  [[ "$ctx" == *"${old_pin:0:12}"* ]]
  # The paragraph that names the commit carries the remedy.
  jq -e --arg c "${old_pin:0:12}" '.systemMessage | split("\n\n") | any(.[]; contains($c) and contains("/gitlore:merge"))' <<<"$hook_json" >/dev/null
  jq -e --arg c "${old_pin:0:12}" '.hookSpecificOutput.additionalContext | split("\n\n") | any(.[]; contains($c) and contains("/gitlore:merge"))' <<<"$hook_json" >/dev/null
}

# --- no detach of a store on a named branch ------------------------------------

@test "SessionStart leaves a tier on a named branch attached" {
  pinned_store_with_tier
  # The mount leaves the tier on the remote's default branch.
  branch=$(git -C memory/ddaanet symbolic-ref -q --short HEAD)
  head=$(git -C memory/ddaanet rev-parse HEAD)

  session_start_over_store
  [ "$(git -C memory/ddaanet symbolic-ref -q --short HEAD)" = "$branch" ] || {
    printf 'the tier left %s and is now detached\n' "$branch" >&2
    return 1
  }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$head" ]
}

@test "SessionStart leaves the memory store on a named branch attached" {
  make_parent_with_memory
  git -C memory checkout -q -b legacy-branch
  head=$(git -C memory rev-parse HEAD)

  session_start_over_store
  [ "$(git -C memory symbolic-ref -q --short HEAD)" = "legacy-branch" ] || {
    printf 'memory left legacy-branch and is now detached\n' >&2
    return 1
  }
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
}

# --- the cross-slice case: the refusal comes before any three-way --------------

# A tier ahead of its pin whose carrier rewords the line root also rewords: a
# three-way compose of it would leave a chunk. The pending check runs here at
# SessionStart with no on-pin guard in front of it, and refuses the tier ahead
# before any merge is attempted; the take is what composes it.
tier_ahead_with_a_chunk() {
  take_base_store
  old_pin=$(git -C memory rev-parse :ddaanet)
  content=$(cat memory/MEMORY.md)
  printf '%s\n' "${content//"a portable fact"/"reworded in root"}" > memory/MEMORY.md
  git -C memory add -A
  git -C memory commit -qm "root rewords the tier line"
  git -C memory push -q . HEAD:refs/heads/live
  # The tier's remote rewords the same line apart from root; the checkout is
  # brought to that commit with nothing composed and nothing staged.
  work="$(mktemp -d "$TMP_REPO/twork.XXXXXX")"
  git clone -q "$TMP_REPO/.bare-ddaanet.git" "$work"
  (
    cd "$work" || exit 1
    git config user.email other@example.com
    git config user.name Other
    git checkout -q -B live origin/live
    sed 's/a portable fact/reworded in tier/' MEMORY.md > MEMORY.md.new
    mv MEMORY.md.new MEMORY.md
    git commit -qam "tier rewords its line"
    git push -q origin live
  )
  tier_sha=$(git -C "$work" rev-parse HEAD)
  git -C memory/ddaanet fetch -q origin live
  git -C memory/ddaanet checkout -q --detach "$tier_sha"
  [ "$(git -C memory rev-parse :ddaanet)" = "$old_pin" ]
}

@test "SessionStart over a tier ahead whose three-way merge would chunk refuses it first, leaving root, carrier and the index as they were" {
  # Fails under a hook that attempts the three-way (a chunk written into root,
  # or a chunk report instead of the refusal), one that stages the gitlink, and
  # a pending check that reports a pass to run instead of refusing the tier.
  tier_ahead_with_a_chunk
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/carrier.before"
  gitlink_before=$(git -C memory ls-files -s -- ddaanet)
  [ -z "$(git -C memory diff --cached --raw)" ]

  session_start_over_store
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before" || {
    printf 'root MEMORY.md was rewritten by SessionStart\n' >&2
    return 1
  }
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/carrier.before" || {
    printf 'the carrier was rewritten by SessionStart\n' >&2
    return 1
  }
  [ "$(git -C memory ls-files -s -- ddaanet)" = "$gitlink_before" ] || {
    printf 'the tier gitlink was staged: %s\n' "$(git -C memory ls-files -s -- ddaanet)" >&2
    return 1
  }
  [ -z "$(git -C memory diff --cached --raw)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  # The refusal, not a chunk: the tier line with both shas and the take.
  tierline="tier 'ddaanet' is checked out at ${tier_sha:0:12}, ahead of the commit the memory store records at ${old_pin:0:12}: it was moved outside a completed take, so the root index has not taken its lines. Run /gitlore:merge, which composes them into the root index and records the tier."
  jq -e --arg l "$tierline" '.systemMessage | split("\n\n") | any(.[]; contains("gitlore: the memory indexes cannot be composed until these are fixed:") and contains($l))' <<<"$hook_json" >/dev/null || {
    printf 'no refusal paragraph over the tier ahead of its pin; systemMessage:\n%s\n' "$sys" >&2
    return 1
  }
  [[ "$ctx" == *"$tierline"* ]]
  [[ "$sys" != *"gitlore-compose"* ]]
}

# --- the orphan report: reported, never refused --------------------------------

@test "SessionStart reports a line written into a tier's own index that root never carried, without refusing or moving anything" {
  detached_pinned_store
  # A bullet written straight into the carrier for a real file: root has a block
  # for the tier and has never carried this path, so a pass leaves it alone.
  seed_tier_bullet ddaanet orphan.md "written into the carrier only"
  [[ "$(gitlore_compose_orphans memory)" == *"orphan.md"* ]]
  [ -z "$(gitlore_compose_pending memory)" ]
  before=$(store_fingerprint)

  session_start_over_store
  [ "$(store_fingerprint)" = "$before" ]
  [[ "$ctx" == *"orphan.md"* ]] || {
    printf 'the agent is not told about the orphan line; additionalContext:\n%s\n' "$ctx" >&2
    return 1
  }
  [[ "$sys" == *"root index"* ]] || {
    printf 'the user is not told about the orphan line; systemMessage:\n%s\n' "$sys" >&2
    return 1
  }
  # Reporting without refusing: the pending check's refusal is not raised.
  [[ "$sys" != *"cannot be composed"* ]]
  [[ "$ctx" != *"cannot be composed"* ]]
}

# --- what must survive ---------------------------------------------------------

@test "passing pin: a tier registered but never checked out is materialized at its recorded commit" {
  pinned_store_with_tier
  recorded=$(git -C memory rev-parse :ddaanet)
  git -C memory submodule deinit -q -f -- ddaanet
  [ ! -e memory/ddaanet/.git ]
  export GIT_ALLOW_PROTOCOL=file

  session_start_over_store
  [ -e memory/ddaanet/.git ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$recorded" ]
}
