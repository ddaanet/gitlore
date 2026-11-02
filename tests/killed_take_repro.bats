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
# from a CLEAN tier ON its pin whose LOCAL `live` is ahead of HEAD, checks the
# tier out at `live`, then gitlore_adopt_tier_into_root runs gitlore_compose_up
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

@test "killed take: SessionStart resets the tier to its pin and leaves the carrier clean, then the later take succeeds" {
  _tier_live_ahead_of_pin
  pin=$(git -C memory rev-parse ":ddaanet")
  live_sha=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$live_sha" != "$pin" ]

  bin=$(_kill_at_pair_staging)

  # --- Drive the real take, killed inside the pair-staging window. ---
  PATH="$bin:$PATH" run --separate-stderr bash "$CMD"
  # BENIGN: the take's own staging call is best-effort
  # (gitlore_adopt_stage_pair_and_commit in scripts/lib/resolve-adopt-report.sh reports and
  # continues on a failed `add`), so the take script itself does not fail even
  # though nothing was staged, and it prints the exact hand-recovery command.
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"killed-take-stub: refusing the pair-staging add"* ]]
  [[ "$output$stderr" == *"held commits the memory store never recorded; adopted them at $(git -C memory/ddaanet rev-parse --short "$live_sha")."* ]]
  [[ "$output$stderr" == *"pointer could not be staged in the memory store. Run \`git -C \"$(cd memory && pwd)\" add -- MEMORY.md \"ddaanet\"\`"* ]]

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
  # BENIGN: `submodule update` reads the gitlink from memory's INDEX (still $pin,
  # since the take's staging never moved it) and resets the tier's worktree to
  # it — the ordinary "return an off-pin tier to its recorded commit" behavior
  # (the tier-pin step of scripts/cc-hooks/session-start.sh).
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  # Reported: root's index is flagged as dangling, because ddaanet/local.md
  # genuinely names no file in the (now reset-back) memory store.
  [[ "$output$stderr" == *"ddaanet/local.md names no file in the memory store"* ]]
  # THE GUARD: SessionStart does not compose, so the reset-back carrier is
  # exactly what the pin holds. Root's carried-over line is not projected down
  # into it, and the tier is clean.
  run grep -qxF -- '- [local](local.md) — committed here, never recorded' memory/ddaanet/MEMORY.md
  [ "$status" -ne 0 ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]

  # --- A later take, run again after SessionStart's reset. ---
  # Real git this time: the kill shadow is gone. The tier is clean and `live` is
  # ahead of its HEAD, which is the shape the take adopts.
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"has uncommitted changes, so nothing was adopted"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$live_sha" ]        # the pair is staged now
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}

# The killed take, then the next SessionStart: the tier is back on its pin, local
# `live` still holds the arrival, and root still carries the adopted line, so the
# store has a pending compose. Leaves $pin, $live_sha, $bin and $hook_json.
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
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$(cat memory/MEMORY.md)" = "$root_before" ]
}

@test "killed take: SessionStart names /gitlore:merge for the tier and not gitlore-compose" {
  _killed_take_then_session_start
  # Composing first dirties the tier and the take refuses, so the report sends
  # the user to the take, on both channels.
  echo "$hook_json" | jq -e '.systemMessage | test("/gitlore:merge")'
  echo "$hook_json" | jq -e '.hookSpecificOutput.additionalContext | test("/gitlore:merge")'
  echo "$hook_json" | jq -e '.systemMessage | test("gitlore-compose") | not'
  echo "$hook_json" | jq -e '.hookSpecificOutput.additionalContext | test("gitlore-compose") | not'
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  # The state is the one the pending-compose diagnostic would otherwise fire on:
  # a pass would write the carrier, so naming /gitlore:merge is what keeps it out.
  [ -n "$(gitlore_compose_pending memory)" ]
}

@test "killed take: gitlore-compose between SessionStart and the take dirties the tier and the take refuses" {
  # Pins today's behaviour on the route the report above steers away from: the
  # compose projects root's carried-over line into the reset-back tier, and the
  # take then refuses on dirt the compose produced. The recovery commit it asks
  # for succeeds, reports divergence, prepares no merge, and `live` keeps the arrival.
  _killed_take_then_session_start
  run --separate-stderr "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
  grep -qxF -- '- [local](local.md) — committed here, never recorded' memory/ddaanet/MEMORY.md
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"tier 'ddaanet' — its local 'live' holds commits the memory store never recorded, but the tier has uncommitted changes, so nothing was adopted."* ]] || false
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]

  # RECOVERY, and why the residual is accepted: the carrier line is committed
  # on the pin, the tier's `live` cannot fast-forward because it still holds
  # the arrival, and that is reported as divergence. The commit prepares no
  # merge: /gitlore:merge or /gitlore:push joins the line to the file it names.
  run --separate-stderr commit_sections "memory: follow the printed remedy"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"/gitlore:merge"* || "$stderr" == *"/gitlore:push"* ]]
  [ -z "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$live_sha" ]      # the arrival is still held
}

@test "killed take retried immediately, with no SessionStart in between, neither heals nor worsens" {
  # The other branch: no reset happens between the
  # kill and the retry, merge-memory.sh never calls the down-projection/pin
  # guard on its own, and the tier is
  # already at `live` (nothing left ahead of HEAD to adopt) — so the retry is
  # a pure no-op. BENIGN: it neither heals the unstaged pair nor makes
  # anything worse; the half-landed state just sits, exactly as the take's own
  # printed remedy after the kill said it would, until SessionStart or a hand
  # `git add` moves it.
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
  [[ "$output$stderr" == *"the memory store has uncommitted changes. Anything this take staged rides the next memory commit"* ]]
  # BENIGN: neither ref moved and neither store's dirt changed shape — the
  # retry is a genuine no-op, not a second silent write.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ -n "$(git -C memory status --porcelain -- MEMORY.md)" ]
  [ -n "$(git -C memory status --porcelain -- ddaanet)" ]
}
