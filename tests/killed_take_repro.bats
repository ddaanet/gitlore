#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2030,SC2031
#
# Regression guard for a killed take: gitlore_compose_up writes the
# ROOT memory index from a tier's arrived carrier, and only afterward does the
# take stage the pair (root MEMORY.md + the tier gitlink). A kill between
# those two acts leaves root describing the tier at its arrived commit while
# the memory store's INDEX still pins the tier at its old commit.
#
# Real take shape (scripts/lib/resolve-adopt.sh): gitlore_adopt_advanced_live starts
# from a CLEAN tier ON its pin whose LOCAL `live` is ahead of HEAD and checks the
# tier out at `live`; gitlore_compose_moved_tiers then runs gitlore_compose_up
# and stages the pair. `strand_live_ahead_of_pin` (tests/helpers/tier-fixtures.bash,
# reused by the same-shaped tests in tests/merge_memory_tiers.bats and
# tests/merge_memory_repair_arrivals.bats) builds exactly that starting state,
# and the take is driven through its real entry point,
# scripts/merge-memory.sh — the same script /gitlore:merge invokes.
#
# The kill is induced with a PATH-shadowed `git`: it delegates
# every call to the real binary except the take's pair-staging call
# (`add -- MEMORY.md ddaanet`), which it refuses — reproducing on disk exactly
# what a process kill at that point would leave, without depending on timing.
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth

CMD="$PLUGIN_ROOT/scripts/merge-memory.sh"
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}
teardown() { teardown_tmp_repo; }

# Copied from tests/helpers/merge-memory.bash (not exported by any
# helpers/*.bash): the memory store's own remote, wired the way every take
# test in the merge_memory* suites needs.
wire_memory_remote() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

# Install a `git` on PATH that runs the real binary for everything except the
# take's pair-staging call, which it refuses — the on-disk equivalent of a kill
# landing right there. Echoes the bin dir to prepend to PATH.
_kill_at_pair_staging() {
  local bin="$BATS_TEST_TMPDIR/killbin" real_git
  mkdir -p "$bin"
  real_git=$(command -v git)
  cat > "$bin/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *' add -- MEMORY.md ddaanet '*)
    printf 'killed-take-stub: refusing the pair-staging add\n' >&2
    exit 137
    ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$bin/git"
  printf '%s\n' "$bin"
}

# The fixture every gitlore_adopt_advanced_live test in
# tests/merge_memory_tiers.bats and tests/merge_memory_repair_arrivals.bats
# starts from: a clean tier ON its pin, local `live` one commit ahead — exactly
# what gitlore_adopt_advanced_live is written to adopt.
_tier_live_ahead_of_pin() {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  strand_live_ahead_of_pin ddaanet
}

@test "killed take: SessionStart leaves the tier on the arrival and reports no dangling pointer, then the later take records it" {
  _tier_live_ahead_of_pin
  pin=$(git -C memory rev-parse ":ddaanet")
  live_sha=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$live_sha" != "$pin" ]

  bin=$(_kill_at_pair_staging)

  # --- Drive the real take, killed inside the pair-staging window. ---
  PATH="$bin:$PATH" run --separate-stderr bash "$CMD"
  # BENIGN: the take's own staging call is best-effort
  # (gitlore_compose_moved_tiers in scripts/lib/resolve-adopt-report.sh reports and
  # continues on a failed `add`), so the take script itself does not fail even
  # though nothing was staged, and it prints the exact hand-recovery command.
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"killed-take-stub: refusing the pair-staging add"* ]]
  [[ "$output$stderr" == *"held commits the memory store never recorded; adopted them at $(git -C memory/ddaanet rev-parse --short "$live_sha")."* ]]
  [[ "$output$stderr" == *"pointer could not be staged in the memory store. Run \`git -C \"$(cd memory && pwd)\" add -- \"MEMORY.md\" \"ddaanet\"\`"* ]]

  # On-disk state the kill leaves:
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]      # tier moved to the arrival
  [ "$(git -C memory/ddaanet rev-parse live)" = "$live_sha" ]      # live unchanged, still at the arrival
  # DEFECT (the claim's premise): the memory store's index still pins the OLD
  # commit — the gitlink never moved, because the staging call that would have
  # moved it was the one refused.
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]
  # DEFECT: root's MEMORY.md carries the adopted carrier's lines already
  # (gitlore_compose_up's own write), left uncommitted and unstaged — nothing
  # after it staged or committed it.
  [ -n "$(git -C memory status --porcelain -- MEMORY.md)" ]
  [ -n "$(git -C memory status --porcelain -- ddaanet)" ]
  [ -z "$(git -C memory diff --cached --name-only)" ]
  grep -qxF -- '- [local](ddaanet/local.md) — committed here, never recorded' memory/MEMORY.md

  # --- The next SessionStart. ---
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  # shellcheck disable=SC2016  # $1 is bash -c's own positional param, expanded at run time, not here
  GITLORE_LAUNCHED=1 run --separate-stderr bash -c 'echo "{}" | bash "$1"' _ "$SESSION_START"
  [ "$status" -eq 0 ]
  # SessionStart moves no module: the tier stays on the arrival the take put it
  # on, however far that is from the pin the kill left in the index.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  # Root's carried-over line and the carrier it came from agree, so nothing is
  # dangling and nothing is pending: the file the line names is in the tier.
  [[ "$output$stderr" != *"ddaanet/local.md names no file in the memory store"* ]]
  # The carrier keeps the line, and the tier is clean.
  grep -qxF -- '- [local](local.md) — committed here, never recorded' memory/ddaanet/MEMORY.md
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]

  # --- A later take, run again after SessionStart. ---
  # Real git this time: the kill shadow is gone. The tier is where the killed
  # take left it, off its pin, and the end compose records it.
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$live_sha" ]      # recorded now
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}

# The killed take, then the next SessionStart: the tier stays on the arrival the
# take put it on, off the pin the index still records, and root carries the
# adopted line, so root and carrier agree. Leaves $pin, $live_sha, $bin and
# $hook_json.
_killed_take_then_session_start() {
  _tier_live_ahead_of_pin
  pin=$(git -C memory rev-parse ":ddaanet")
  live_sha=$(git -C memory/ddaanet rev-parse live)
  bin=$(_kill_at_pair_staging)
  PATH="$bin:$PATH" run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  root_before=$(cat memory/MEMORY.md)
  # shellcheck disable=SC2016  # $1 is bash -c's own positional param, expanded at run time, not here
  GITLORE_LAUNCHED=1 run --separate-stderr bash -c 'echo "{}" | bash "$1"' _ "$SESSION_START"
  [ "$status" -eq 0 ]
  hook_json="$output"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  [ "$(cat memory/MEMORY.md)" = "$root_before" ]
}

@test "killed take: SessionStart reports no dangling pointer and no pending compose for the tier it left on the arrival" {
  _killed_take_then_session_start
  # Root's line and the carrier's agree, so a pass changes nothing: no compose
  # command is named on either channel, and the file the line names is in the
  # tier, so no pointer is reported missing.
  echo "$hook_json" | jq -e '.systemMessage | test("gitlore-compose") | not'
  echo "$hook_json" | jq -e '.hookSpecificOutput.additionalContext | test("gitlore-compose") | not'
  echo "$hook_json" | jq -e '.systemMessage | test("names no file") | not'
  echo "$hook_json" | jq -e '.hookSpecificOutput.additionalContext | test("names no file") | not'
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ -z "$(gitlore_compose_pending memory)" ]
}

@test "killed take: gitlore-compose between SessionStart and the take changes nothing, and the take records the tier" {
  # The tier stays on the arrival and carries the line root carries, so the
  # compose projects nothing into it: it stays clean, and the take that follows
  # does not refuse on dirt a compose produced.
  _killed_take_then_session_start
  run --separate-stderr "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"has uncommitted changes, so nothing was taken"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$live_sha" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$live_sha" ]      # the arrival is still held
}

@test "killed take retried immediately, with no SessionStart in between, records the tier" {
  # A tier off its pin is all the state a killed take leaves, and all the retry
  # needs: its end compose writes root and commits what the kill left unrecorded.
  _tier_live_ahead_of_pin
  pin=$(git -C memory rev-parse ":ddaanet")
  live_sha=$(git -C memory/ddaanet rev-parse live)

  bin=$(_kill_at_pair_staging)
  PATH="$bin:$PATH" run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]   # still unstaged

  # Retry with a real, unshadowed git and no SessionStart in between.
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"tier 'ddaanet' — already holds everything its remote does."* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$live_sha" ]
  git -C memory show HEAD:MEMORY.md | grep -qxF -- '- [local](ddaanet/local.md) — committed here, never recorded'
  [ -z "$(git -C memory status --porcelain)" ]
}
