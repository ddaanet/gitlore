#!/usr/bin/env bats
# A tier whose HEAD strictly descends its pin is not a fault: the memory commit
# records it through `add -A`, never putting it back on the pin, and aborts
# naming gitlore-compose only when a compose pass would change root. The pin
# guard that remains refuses a tier behind its pin, over every mounted tier
# (dormant ones included, not the manifest's), and `/gitlore:merge` clears it.
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

# --- a tier ahead of its pin commits through ----------------------------------

@test "a tier ahead of its pin, with root lines a pass would not change, commits through and records the tier's HEAD" {
  take_base_store
  pin=$(git -C memory rev-parse ":ddaanet")
  tier_body_commit ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  root_project_fact
  # The fixture's shape: HEAD strictly descends the pin, the commit touched no
  # index line, and the tier's local `live` is still on the pin.
  [ "$moved" != "$pin" ]
  git -C memory/ddaanet merge-base --is-ancestor "$pin" "$moved"
  [ -z "$(git -C memory/ddaanet diff "$pin" "$moved" --name-only -- MEMORY.md)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$pin" ]

  run --separate-stderr commit_sections "memory: record the project fact"
  [ "$status" -eq 0 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; false; }
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$moved" ] \
    || { printf 'the commit recorded %s for the tier, expected its HEAD %s\n' \
           "$(git -C memory rev-parse HEAD:ddaanet)" "$moved" >&2; false; }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$pin" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a tier ahead of its pin whose local live holds its commits is not put back on the pin by the commit" {
  take_base_store
  pin=$(git -C memory rev-parse ":ddaanet")
  tier_body_commit ddaanet
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  root_project_fact
  [ "$moved" != "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]

  run --separate-stderr commit_sections "memory: record the project fact"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ] \
    || { printf 'the tier is at %s, expected to stay at %s (its pin is %s)\n' \
           "$(git -C memory/ddaanet rev-parse HEAD)" "$moved" "$pin" >&2; false; }
  [ "$status" -eq 0 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; false; }
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$moved" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]
}

# --- the half-landed retry ----------------------------------------------------

@test "a half-landed tier commit retried with a local live neither rewinds the tier nor loses the carrier's line" {
  half_landed_tier_with_live
  pin_before=$(git -C memory rev-parse ":ddaanet")
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

  rm -f "$lock"
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -eq 0 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; false; }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ] \
    || { printf 'the retry moved the tier to %s, expected it to stay at %s\n' \
           "$(git -C memory/ddaanet rev-parse HEAD)" "$landed" >&2; false; }
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$landed" ]
  git -C memory/ddaanet show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/carrier.md"
  assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \
    '- [shared](shared.md) — fresh hook'
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [shared](shared.md) — fresh hook'
  [ -z "$(git -C memory status --porcelain)" ]
}

# --- a commit a pass would change aborts --------------------------------------

@test "a commit that a pass would change, with a tier ahead holding no live of its own, aborts naming gitlore-compose" {
  take_base_store
  pin=$(git -C memory rev-parse ":ddaanet")
  move_tier_off_pin ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  root_project_fact
  memory_before=$(git -C memory rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$pin" ]

  run --separate-stderr commit_sections "memory: record the project fact"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"gitlore-compose"* ]] \
    || { printf 'the abort never names gitlore-compose; stderr:\n%s\n' "$stderr" >&2; false; }
  [[ "$stderr" == *"MEMORY.md"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]
}

@test "a commit that a pass would change, with a tier ahead whose live holds its commits, aborts and leaves the tier where it is" {
  take_base_store
  pin=$(git -C memory rev-parse ":ddaanet")
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  root_project_fact
  memory_before=$(git -C memory rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]

  run --separate-stderr commit_sections "memory: record the project fact"
  [ "$status" -ne 0 ] || { printf 'the commit went through; the tier is at %s, its pin is %s\n' \
    "$(git -C memory/ddaanet rev-parse HEAD)" "$pin" >&2; false; }
  [[ "$stderr" == *"gitlore-compose"* ]] \
    || { printf 'the abort never names gitlore-compose; stderr:\n%s\n' "$stderr" >&2; false; }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ] \
    || { printf 'the tier is at %s, expected to stay at %s\n' \
           "$(git -C memory/ddaanet rev-parse HEAD)" "$moved" >&2; false; }
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
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

@test "passing pin: a dormant tier ahead of its pin does not stop the commit and its HEAD is recorded" {
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

  run --separate-stderr commit_sections "memory: record the root fact"
  [ "$status" -eq 0 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; false; }
  [ "$(git -C memory rev-parse HEAD:dorm)" = "$d_head" ]
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
