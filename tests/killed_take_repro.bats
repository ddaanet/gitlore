#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
#
# Characterizes a killed take: gitlore_compose_up writes the
# ROOT memory index from a tier's arrived carrier, and only afterward does the
# take stage the pair (root MEMORY.md + the tier gitlink). A kill between
# those two acts leaves root describing the tier at its arrived commit while
# the memory store's INDEX still pins the tier at its old commit.
#
# Real take shape (scripts/lib/resolve.sh): gitlore_adopt_advanced_live starts
# from a CLEAN tier ON its pin whose LOCAL `live` is ahead of HEAD, checks the
# tier out at `live`, then gitlore_adopt_tier_into_root runs gitlore_compose_up
# and stages the pair. `strand_live_ahead_of_pin` (tests/helpers/tier-fixtures.bash,
# reused by the same-shaped tests in tests/merge_memory.bats) builds exactly
# that starting state, and the take is driven through its real entry point,
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

# Copied from tests/merge_memory.bats (not exported by any helpers/*.bash): the
# memory store's own remote, wired the way every take test in that file needs.
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

# The fixture every gitlore_adopt_advanced_live test in tests/merge_memory.bats
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

@test "killed take: root written and the pair unstaged, then SessionStart dirties the tier, then a retry refuses" {
  _tier_live_ahead_of_pin
  pin=$(git -C memory rev-parse ":ddaanet")
  live_sha=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$live_sha" != "$pin" ]

  bin=$(_kill_at_pair_staging)

  # --- Drive the real take, killed inside the pair-staging window. ---
  PATH="$bin:$PATH" run --separate-stderr bash "$CMD"
  # BENIGN: the take's own staging call is best-effort
  # (gitlore_adopt_stage_pair_and_commit in scripts/lib/resolve.sh reports and
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
  # BENIGN on its own: `submodule update` reads the gitlink from memory's
  # INDEX (still $pin, since the take's staging never moved it) and resets the
  # tier's worktree to it — the ordinary, correct "return an off-pin tier to
  # its recorded commit" behavior (scripts/cc-hooks/session-start.sh:289).
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  # Reported: root's index is flagged as dangling, because ddaanet/local.md
  # genuinely names no file in the (now reset-back) memory store. This is
  # REAL but coincidental cover: the message is about root's own pointer,
  # traceable to gitlore_compose_up's write alone, not about what the down
  # projection is about to do to the tier's own carrier.
  [[ "$output$stderr" == *"ddaanet/local.md names no file in the memory store"* ]]
  # DEFECT (the claim under test): the pin guard is satisfied — HEAD now
  # equals the index's own (unmoved) gitlink, so nothing looks off-pin — and
  # SessionStart's own compose pass runs the down projection anyway, which
  # takes root's carried-over line unconditionally (gitlore_compose_down,
  # scripts/lib/index-compose.sh) and writes it into the reset-back tier's own
  # MEMORY.md, for a fact that tier's own working tree does not hold.
  grep -qxF -- '- [local](local.md) — committed here, never recorded' memory/ddaanet/MEMORY.md
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]
  # And this half — the TIER's own carrier having just been dirtied — is what
  # goes unreported: nothing in the output names ddaanet's carrier as changed
  # or dirty, only root's pre-existing dangling pointer.
  [[ "$output$stderr" != *"ddaanet"*"dirty"* ]]
  [[ "$output$stderr" != *"ddaanet"*"uncommitted"* ]]

  # --- A later take, run again after SessionStart's reset+recompose. ---
  PATH="$bin:$PATH" run --separate-stderr bash "$CMD"
  # DEFECT: the take now refuses outright — but on dirt SessionStart's own
  # reset-and-recompose produced, not on any unapproved edit an agent made.
  # There is nothing left in `live` ahead of this HEAD to adopt (the arrival
  # already IS this HEAD, back on the pin), so gitlore_adopt_advanced_live's
  # dirty-tier guard is what fires, and its remedy — commit, then merge again
  # — does not fit what actually happened: committing as instructed would
  # commit the phantom carrier line straight into the tier's own history.
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"tier 'ddaanet' — its local 'live' holds commits the memory store never recorded, but the tier has uncommitted changes, so nothing was adopted."* ]]
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin" ]

  # --- The memory commit that remedy asks for. ---
  # RECOVERY, and why the residual is accepted: the carrier line is committed
  # on the pin, the tier's HEAD:live push is refused because `live` still holds
  # the arrival, and that refusal is divergence — so a head-vs-live merge is
  # prepared in the tier, joining the line to the file it names. The dangling
  # report does not block this commit; the divergence gate is what stops it.
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: follow the printed remedy"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"gitlore: memory merge prepared (flavor=head-vs-live) in store:"* ]]
  [[ "$output$stderr" == *"/memory/ddaanet"* ]]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$live_sha" ]      # the arrival is still held
}

@test "killed take retried immediately, with no SessionStart in between, neither heals nor worsens" {
  # The other branch: no reset happens between the
  # kill and the retry, merge-memory.sh never calls the down-projection/pin
  # guard on its own (only SessionStart's compose does), and the tier is
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
