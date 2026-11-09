#!/usr/bin/env bats
# A tier whose HEAD strictly descends its pin is a fault outside a take: no
# normal operation leaves one, and recording it through `add -A` would hide the
# killed take or hand git that produced it. The commit's pin guard
# (gitlore_sync_memory_to_live, run ahead of the pending check) refuses it
# naming /gitlore:merge, which composes its lines into the root index and
# records the tier; nothing is written, moved or recorded. The guard runs over
# every mounted tier (dormant ones included, not the manifest's), refuses a tier
# behind its pin the same way, and `/gitlore:merge` clears both.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order

# --- fixtures -----------------------------------------------------------------

# A project line in root, so the commit has content beyond the gitlink.
root_project_fact() {
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  seed_root_bullet "proj.md" "a project fact"
}

# One tier commit that edits a fact's body and no index line: tier $1 moves
# ahead of its pin while the carrier stays what it was.
tier_body_commit() {
  printf 'more body\n' >> "memory/$1/shared.md"
  git -C "memory/$1" add -A
  git -C "memory/$1" commit -qm "edit a fact body"
}

# The half-landed fixture with what every real tier has and the fixture lacks: a
# local `live`, with the tier detached on it.
half_landed_tier_with_live() {
  half_landed_tier_fixture
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
}

# A tier mounted in memory and left out of the manifest: dormant. The memory
# remote carries the mount.
mount_dormant_tier() {
  mount_tier_at_live dorm
  git -C memory push -q origin live
}

# Publish to the memory remote a commit that records tier $1 at commit $2 and
# changes nothing else, the way another checkout's `/gitlore:push` does.
memory_remote_records_gitlink() {
  local tier="$1" sha="$2" work
  work="$(mktemp -d "$TMP_REPO/mwork.XXXXXX")"
  git clone -q -b live "$MEMORY_REMOTE" "$work"
  (
    cd "$work" || exit 1
    git config user.email "other@example.com"
    git config user.name "Other"
    git update-index --cacheinfo "160000,$sha,$tier"
    git commit -qm "other checkout records $tier"
    git push -q origin live
  )
  rm -rf "$work"
}

# Dormant tier `dorm` behind its pin after a raw pull in memory: the memory
# remote records a newer commit of it, and the checkout under it stays at the
# old one. Sets $d_old and $d_new.
dormant_tier_behind_its_pin() {
  take_base_store
  mount_dormant_tier
  d_old=$(git -C memory/dorm rev-parse HEAD)
  d_new=$(push_tier_fact dorm "- [x](x.md) — newer")
  memory_remote_records_gitlink dorm "$d_new"
  git -C memory -c protocol.file.allow=always pull -q --no-rebase --no-edit origin live
  # The fixture's shape, asserted rather than assumed: the index records the
  # newer commit, the checkout is on the older, and the tier is not in the
  # manifest.
  [ "$d_old" != "$d_new" ]
  [ "$(git -C memory rev-parse ":dorm")" = "$d_new" ]
  [ "$(git -C memory/dorm rev-parse HEAD)" = "$d_old" ]
  run ! grep -Fx dorm memory/.gitlore-tiers
}

# --- a tier ahead of its pin is refused at the commit ------------------------

# The pin guard's refusal on stderr: its header, the verbatim pin-check line for
# tier $1 checked out at $2 over the pin $3, the take as the remedy — and not
# the pending check's abort, which the guard runs ahead of.
assert_commit_refused_ahead() {
  [[ "$stderr" == *"a tier was moved off the commit the memory store records for it"* ]] \
    || { printf 'no pin-guard header; stderr:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"tier '$1' is checked out at ${2:0:12}, ahead of the commit the memory store records at ${3:0:12}"* ]] \
    || { printf 'the refusal does not name the tier ahead; stderr:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"Run /gitlore:merge"* ]]
  [[ "$stderr" != *"gitlore-compose"* ]]
}

# Root and the tier's carrier, byte-identical to the copies a test took before
# the commit attempt.
assert_stores_untouched() {
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}

snapshot_stores() {
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}

@test "a tier ahead of its pin, with root lines a pass would not change, is refused at the commit naming /gitlore:merge" {
  # Fails under a commit that records the tier's HEAD through `add -A`: the
  # move no take completed would be committed in silence.
  take_base_store
  pin=$(git -C memory rev-parse ":ddaanet")
  tier_body_commit ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  root_project_fact
  memory_before=$(git -C memory rev-parse HEAD)
  # The fixture's shape: HEAD strictly descends the pin, the commit touched no
  # index line, and the tier's local `live` is still on the pin.
  [ "$moved" != "$pin" ]
  git -C memory/ddaanet merge-base --is-ancestor "$pin" "$moved"
  [ -z "$(git -C memory/ddaanet diff "$pin" "$moved" --name-only -- MEMORY.md)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$pin" ]
  snapshot_stores

  run --separate-stderr commit_sections "memory: record the project fact"
  [ "$status" -ne 0 ] || { printf 'the commit went through; HEAD records the tier at %s\n' \
    "$(git -C memory rev-parse HEAD:ddaanet)" >&2; false; }
  assert_commit_refused_ahead ddaanet "$moved" "$pin"
  assert_stores_untouched
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$pin" ]
}

@test "a tier ahead of its pin whose local live holds its commits is refused at the commit and left where it is" {
  # The shape a lost gitlink leaves after a tier commit moved both refs. Fails
  # under a guard that reads `live` for the pin, or a commit that re-pins.
  take_base_store
  pin=$(git -C memory rev-parse ":ddaanet")
  tier_body_commit ddaanet
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  root_project_fact
  memory_before=$(git -C memory rev-parse HEAD)
  [ "$moved" != "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]
  snapshot_stores

  run --separate-stderr commit_sections "memory: record the project fact"
  [ "$status" -ne 0 ] || { printf 'the commit went through; HEAD records the tier at %s\n' \
    "$(git -C memory rev-parse HEAD:ddaanet)" >&2; false; }
  assert_commit_refused_ahead ddaanet "$moved" "$pin"
  assert_stores_untouched
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ] \
    || { printf 'the tier is at %s, expected to stay at %s (its pin is %s)\n' \
           "$(git -C memory/ddaanet rev-parse HEAD)" "$moved" "$pin" >&2; false; }
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]
}

# --- the half-landed retry ----------------------------------------------------

@test "a half-landed tier commit retried with a local live is refused naming the take, and neither rewinds the tier nor loses the carrier's line" {
  # The commit path committed inside the tier, then memory's `add -A` met the
  # lock: the tier is one commit ahead of its pin, the shape a killed take
  # leaves. The retry meets the pin guard. Fails under a retry that re-pins the
  # tier (losing the landed carrier line) or records its HEAD through.
  half_landed_tier_with_live
  pin_before=$(git -C memory rev-parse ":ddaanet")
  memory_before=$(git -C memory rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$pin_before" ]

  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  # The fixture's shape, asserted rather than assumed: the tier commit landed,
  # memory's index still records the pin, and the lock is what stopped it.
  [ -f "$lock" ]
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$landed" != "$pin_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  snapshot_stores

  rm -f "$lock"
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ] || { printf 'the retry went through; HEAD records the tier at %s\n' \
    "$(git -C memory rev-parse HEAD:ddaanet)" >&2; false; }
  assert_commit_refused_ahead ddaanet "$landed" "$pin_before"
  assert_stores_untouched
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ] \
    || { printf 'the retry moved the tier to %s, expected it to stay at %s\n' \
           "$(git -C memory/ddaanet rev-parse HEAD)" "$landed" >&2; false; }
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  # The landed commit and the working carrier both hold the composed line.
  git -C memory/ddaanet show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/carrier.md"
  assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \
    '- [shared](shared.md) — fresh hook'
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [shared](shared.md) — fresh hook'
}

# --- a commit a pass would change meets the pin guard first -------------------

@test "a commit that a pass would change, with a tier ahead holding no live of its own, is refused by the pin guard, not the pending check" {
  # Root lacks the tier's arrived line, so a pending check alone would abort
  # naming gitlore-compose, which cannot take the line. The pin guard runs
  # first and names the take. Fails when the guard runs after the check.
  take_base_store
  pin=$(git -C memory rev-parse ":ddaanet")
  move_tier_off_pin ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  root_project_fact
  memory_before=$(git -C memory rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$pin" ]
  snapshot_stores

  run --separate-stderr commit_sections "memory: record the project fact"
  [ "$status" -ne 0 ]
  assert_commit_refused_ahead ddaanet "$moved" "$pin"
  assert_stores_untouched
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]
}

@test "a commit that a pass would change, with a tier ahead whose live holds its commits, is refused and leaves the tier where it is" {
  take_base_store
  pin=$(git -C memory rev-parse ":ddaanet")
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  root_project_fact
  memory_before=$(git -C memory rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]
  snapshot_stores

  run --separate-stderr commit_sections "memory: record the project fact"
  [ "$status" -ne 0 ] || { printf 'the commit went through; the tier is at %s, its pin is %s\n' \
    "$(git -C memory/ddaanet rev-parse HEAD)" "$pin" >&2; false; }
  assert_commit_refused_ahead ddaanet "$moved" "$pin"
  assert_stores_untouched
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ] \
    || { printf 'the tier is at %s, expected to stay at %s\n' \
           "$(git -C memory/ddaanet rev-parse HEAD)" "$moved" >&2; false; }
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]
}

# --- the pin guard loops over mounted tiers -----------------------------------

@test "a dormant tier behind its pin is refused at the commit, naming /gitlore:merge, and nothing is recorded" {
  dormant_tier_behind_its_pin
  printf 'rootfact\n' > memory/rootfact.md
  memory_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr commit_sections "memory: record the root fact"
  [ "$status" -ne 0 ] \
    || { printf 'the commit went through; HEAD records dorm at %s, the pin is %s\n' \
           "$(git -C memory rev-parse HEAD:dorm)" "$d_new" >&2; false; }
  [[ "$stderr" == *"/gitlore:merge"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse HEAD:dorm)" = "$d_new" ]
}

@test "a dormant tier ahead of its pin is refused at the commit, naming /gitlore:merge, and nothing is recorded" {
  # The guard walks every mounted tier, not the manifest's: `add -A` would
  # record a dormant tier's HEAD as much as an active one's. Fails under a
  # guard over the active tiers only.
  take_base_store
  mount_dormant_tier
  d_old=$(git -C memory/dorm rev-parse HEAD)
  printf 'dorm body\n' > memory/dorm/extra.md
  git -C memory/dorm add -A
  git -C memory/dorm commit -qm "a dormant tier moves ahead"
  d_head=$(git -C memory/dorm rev-parse HEAD)
  [ "$d_head" != "$d_old" ]
  [ "$(git -C memory rev-parse ":dorm")" = "$d_old" ]
  printf 'rootfact\n' > memory/rootfact.md
  memory_before=$(git -C memory rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"

  run --separate-stderr commit_sections "memory: record the root fact"
  [ "$status" -ne 0 ] || { printf 'the commit went through; HEAD records dorm at %s\n' \
    "$(git -C memory rev-parse HEAD:dorm)" >&2; false; }
  assert_commit_refused_ahead dorm "$d_head" "$d_old"
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":dorm")" = "$d_old" ]
  [ "$(git -C memory/dorm rev-parse HEAD)" = "$d_head" ]
}

@test "passing pin: after /gitlore:merge the dormant tier behind its pin is fast-forwarded and the commit passes" {
  dormant_tier_behind_its_pin

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; false; }
  [ "$(git -C memory/dorm rev-parse HEAD)" = "$d_new" ] \
    || { printf 'the tier is at %s, expected the pin %s; stderr:\n%s\n' \
           "$(git -C memory/dorm rev-parse HEAD)" "$d_new" "$stderr" >&2; false; }

  printf 'rootfact\n' > memory/rootfact.md
  run --separate-stderr commit_sections "memory: record the root fact"
  [ "$status" -eq 0 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; false; }
  [ "$(git -C memory rev-parse HEAD:dorm)" = "$d_new" ]
}
