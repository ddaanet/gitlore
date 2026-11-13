#!/usr/bin/env bats
# The in-session hooks reach the take-refusal check (the pin guard's yield) and
# so a tier's remote. SessionStart fetches each store's remote once per
# run and bounds every fetch with GITLORE_FETCH_TIMEOUT seconds (default 5),
# reporting a fetch that timed out; the PostToolBatch compose hook does no
# network access at all.
#
# State S: tier ddaanet ("A") is dirty in its carrier with arrivals on its
# remote and its local `live` in HEAD; tier org ("B") is off its pin with
# /gitlore:merge as the remedy. "red" tests fail against the current code;
# "lock-in" tests pass before and after.
#
# A hanging remote is an ssh-style URL whose GIT_SSH_COMMAND is a script that
# records its pid and sleeps: no network, no `timeout` tool. Teardown kills it.
bats_require_minimum_version 1.5.0
load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order
load helpers/cc-hook-session-start
load helpers/cc-hook-index-compose
load helpers/index-compose

# A hang outlasts any SessionStart a bounded fetch allows, even under a loaded
# parallel run, so the elapsed bound is the hang itself: an unbounded fetch
# takes at least that long, a bounded one far less.
HANG_SECONDS=30

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export GITLORE_LAUNCHED=1
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
  HANG_PIDS="$BATS_TEST_TMPDIR/hang.pids"
  unset GITLORE_FETCH_TIMEOUT
}

teardown() {
  local pid
  if [ -f "$HANG_PIDS" ]; then
    while IFS= read -r pid || [ -n "$pid" ]; do
      # A dead pid is the expected case here; kill -0 is the probe.
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then kill "$pid"; fi
    done < "$HANG_PIDS"
  fi
  teardown_tmp_repo
}

# --- fixtures ---------------------------------------------------------------------

# State S, with a root change for the commit to carry.
state_s() {
  take_base_store ddaanet org
  local_tier_commit_recorded org loc.md
  git -C memory/org checkout -q --detach HEAD~1
  push_tier_fact ddaanet "- [up](up.md) — from upstream" >/dev/null
  seed_tier_bullet ddaanet new.md "an uncommitted tier fact"
}

# Store $1's origin (a path under $TMP_REPO/memory, "memory" or "memory/<tier>")
# becomes an ssh-style URL whose transport sleeps $HANG_SECONDS seconds. The
# sleeper keeps git's stdin and stdout, so git waits on it as on a stalled
# connection (with them closed git reads EOF and fails at once), and drops
# stderr, so a sleeper surviving git holds no pipe the hook's caller reads.
# GIT_SSH_VARIANT=ssh stops git probing the command with `-G` first, so each
# fetch starts exactly one transport and records exactly one pid.
make_hanging_remote() {
  local store="$1"
  mkdir -p "$BATS_TEST_TMPDIR/hang-bin"
  cat > "$BATS_TEST_TMPDIR/hang-bin/ssh.sh" <<SCRIPT
#!/bin/sh
echo \$\$ >> "$HANG_PIDS"
exec sleep $HANG_SECONDS 2>/dev/null
SCRIPT
  chmod 755 "$BATS_TEST_TMPDIR/hang-bin/ssh.sh"
  export GIT_SSH_COMMAND="$BATS_TEST_TMPDIR/hang-bin/ssh.sh"
  export GIT_SSH_VARIANT=ssh
  git -C "$store" config remote.origin.url "ssh://hang.invalid/repo.git"
}

# A git on PATH that logs the physical directory of every fetch, whatever its
# shape: global options before the subcommand are skipped (`-C` dirs compose as
# git composes them, `-c` and the other value-taking ones take their value), and
# the directory is the cwd when no `-C` is given. Fetches git starts itself
# (submodule recursion) resolve through git's exec-path and are not seen.
make_fetch_log_git() {
  local real
  real=$(command -v git)
  mkdir -p "$TMP_REPO/stub"
  cat > "$TMP_REPO/stub/git" <<STUB
#!/bin/sh
dir=. want=
for a in "\$@"; do
  if [ -n "\$want" ]; then
    if [ "\$want" = C ]; then
      case "\$a" in /*) dir=\$a ;; *) dir=\$dir/\$a ;; esac
    fi
    want=
    continue
  fi
  case "\$a" in
    -C) want=C ;;
    -c|--git-dir|--work-tree|--namespace|--super-prefix) want=value ;;
    -*) ;;
    *)
      if [ "\$a" = fetch ]; then
        (cd "\$dir" && pwd -P) >> "$TMP_REPO/fetch.log"
      fi
      break ;;
  esac
done
exec "$real" "\$@"
STUB
  chmod 755 "$TMP_REPO/stub/git"
  : > "$TMP_REPO/fetch.log"
}

# Fetches logged for tier $1; for the memory store itself, `memory_fetches`.
fetches_of() { grep -cE "(^|/)memory/$1\$" "$TMP_REPO/fetch.log" || true; }
memory_fetches() { grep -cE "(^|/)memory\$" "$TMP_REPO/fetch.log" || true; }

# SessionStart over the fixture; sets $hook_json, $sys, $ctx and $elapsed.
run_session_start() {
  enable_gitlore
  local t0=$SECONDS
  run --separate-stderr bash "$SESSION_START"
  elapsed=$((SECONDS - t0))
  hook_json="$output"
  sys=$(jq -r '.systemMessage // ""' <<<"$hook_json")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$hook_json")
}

# Pids of hanging transports still running (a zombie awaiting its reaper is
# dead). `ps -o stat= -p` is the same on BSD and procps.
hang_survivors() {
  local pid st
  while IFS= read -r pid || [ -n "$pid" ]; do
    [ -n "$pid" ] || continue
    st=$(ps -o stat= -p "$pid") || continue
    case "$st" in *Z*|"") ;; *) printf '%s\n' "$pid" ;; esac
  done < "$HANG_PIDS"
}

# The hang was reached by exactly one fetch, and the timeout killed its whole
# transport, not only git: a sleeper reparented on git's death survives a kill
# of git alone. The kill is asynchronous, so allow it 5 seconds.
assert_hang_reaped() {
  local i=0
  [ "$(grep -c . "$HANG_PIDS")" -eq 1 ]
  while [ -n "$(hang_survivors)" ]; do
    i=$((i + 1))
    if [ "$i" -gt 50 ]; then
      echo "transport still running: $(hang_survivors)"
      return 1
    fi
    sleep 0.1
  done
}

# Each store's position line in state S when its remote answers.
DDAANET_LINE="gitlore: tier 'ddaanet' has upstream facts waiting"
ORG_LINE="gitlore: tier 'org' holds commits its remote 'live' lacks"
MEMORY_LINE="gitlore: memory holds 1 commit its remote's live lacks"

# A line of $1 holding both literals $2 and $3.
assert_line_with() {
  grep -F -e "$2" <<<"$1" | grep -qF -e "$3"
}

# --- red: one fetch per store per run ---------------------------------------------

# Exactly once, not at most once: SessionStart still checks every remote, and
# ddaanet's arrival can only be reported from a fetch. Today ddaanet is fetched
# four times (the position fetch and three yield checks), org and memory once.
@test "red: SessionStart in state S fetches each store's remote exactly once" {
  state_s
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run_session_start
  [ "$status" -eq 0 ]
  [[ "$sys" == *"$DDAANET_LINE"* ]]
  [ "$(fetches_of ddaanet)" -eq 1 ]
  [ "$(fetches_of org)" -eq 1 ]
  [ "$(memory_fetches)" -eq 1 ]
}

# --- red: every fetch is bounded and a timeout is reported --------------------------

@test "red: SessionStart bounds a hanging tier fetch, completes, and reports the timeout" {
  state_s
  make_hanging_remote memory/ddaanet
  GITLORE_FETCH_TIMEOUT=2 run_session_start
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt "$HANG_SECONDS" ]
  assert_hang_reaped
  assert_line_with "$sys" "gitlore: tier 'ddaanet'" "timed out after 2s"
  # The other stores still report.
  [[ "$sys" == *"$ORG_LINE"* ]]
  [[ "$sys" == *"$MEMORY_LINE"* ]]
}

@test "red: SessionStart bounds a hanging memory fetch, completes, and reports the timeout" {
  state_s
  make_hanging_remote memory
  GITLORE_FETCH_TIMEOUT=2 run_session_start
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt "$HANG_SECONDS" ]
  assert_hang_reaped
  assert_line_with "$sys" "could not fetch memory's remote 'live'" "timed out after 2s"
  [[ "$sys" == *"$DDAANET_LINE"* ]]
  [[ "$sys" == *"$ORG_LINE"* ]]
}

@test "red: GITLORE_FETCH_TIMEOUT defaults to 5 seconds" {
  state_s
  make_hanging_remote memory
  run_session_start
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt "$HANG_SECONDS" ]
  assert_hang_reaped
  assert_line_with "$sys" "could not fetch memory's remote 'live'" "timed out after 5s"
}

# --- red: the PostToolBatch hook runs no fetch --------------------------------------

@test "red: the PostToolBatch compose hook in state S runs no fetch" {
  state_s
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run feed
  [ "$status" -eq 0 ]
  # The hook composed: its pass is the one that reaches the yield check.
  grep -qF 'p.md' memory/MEMORY.md
  [ "$(fetches_of ddaanet)" -eq 0 ]
  [ "$(fetches_of org)" -eq 0 ]
  [ "$(memory_fetches)" -eq 0 ]
}

# --- lock-in ------------------------------------------------------------------------

# The counter behind the fetch assertions sees a fetch in any shape the scripts
# could give it, and only a fetch.
@test "lock-in: the fetch counter sees a fetch whatever its argument shape" {
  state_s
  make_fetch_log_git
  local stub="$TMP_REPO/stub:$PATH"
  PATH="$stub" git -C memory/org fetch -q origin live
  PATH="$stub" git -C memory -c gitlore.probe=1 -C org fetch -q origin live
  (cd memory/ddaanet && PATH="$stub" git fetch -q origin live)
  PATH="$stub" env git -C memory --no-pager fetch -q origin live
  PATH="$stub" git -C memory/org config --get remote.origin.url >/dev/null
  PATH="$stub" git -C memory/org log -1 --format=%s --grep=fetch >/dev/null
  [ "$(fetches_of org)" -eq 2 ]
  [ "$(fetches_of ddaanet)" -eq 1 ]
  [ "$(memory_fetches)" -eq 1 ]
}

@test "lock-in: gitlore-commit in state S fetches each tier at most once and yields B" {
  state_s
  printf -- '---\nname: dirty\ndescription: ""\n---\n\nbody\n' > memory/dirty.md
  seed_root_bullet dirty.md "an uncommitted root fact"
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run commit_sections "memory: record"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier 'org' is checked out off the commit the memory store records for it"* ]]
  [[ "$output" == *"Run /gitlore:merge next"* ]]
  [ "$(fetches_of ddaanet)" -le 1 ]
  [ "$(fetches_of org)" -le 1 ]
}

@test "lock-in: SessionStart in state S with healthy remotes reports each store and no timeout" {
  state_s
  run_session_start
  [ "$status" -eq 0 ]
  [[ "$sys" == *"$DDAANET_LINE"* ]]
  [[ "$sys" == *"$ORG_LINE"* ]]
  [[ "$sys" == *"$MEMORY_LINE"* ]]
  [[ "$sys$ctx" != *"timed out"* ]]
  [[ "$sys$ctx" != *"could not fetch"* ]]
}

# --- red: the rewrite-record fetch on the diverged arm is bounded -----------------

# A git on PATH whose fetch of the rewrite record hangs like a stalled remote,
# recording its pid; every other git call runs the real git. Memory's `live`
# fetch therefore succeeds and the diverged arm is reached.
make_hanging_rewrites_git() {
  local real
  real=$(command -v git)
  mkdir -p "$TMP_REPO/stub"
  cat > "$TMP_REPO/stub/git" <<STUB
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    *refs/heads/gitlore/rewrites*)
      echo \$\$ >> "$HANG_PIDS"
      exec sleep $HANG_SECONDS ;;
  esac
done
exec "$real" "\$@"
STUB
  chmod 755 "$TMP_REPO/stub/git"
}

@test "red: SessionStart bounds a hanging rewrite-record fetch on memory's diverged arm and reports the timeout" {
  state_s
  push_memory_fact
  make_hanging_rewrites_git
  GITLORE_FETCH_TIMEOUT=2 PATH="$TMP_REPO/stub:$PATH" run_session_start
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt "$HANG_SECONDS" ]
  assert_hang_reaped
  assert_line_with "$sys" "rewrite record gitlore/rewrites could not be fetched" "timed out after 2s"
  assert_line_with "$ctx" "rewrite record gitlore/rewrites could not be fetched" "timed out after 2s"
  [[ "$sys" == *"$DDAANET_LINE"* ]]
}

# --- red: gitlore-commit reads a timeout that is not a positive integer as unset --

# Tier ddaanet is dirty with arrivals, so the take is refused and the commit
# yields org; that answer needs ddaanet's fetch to succeed. setup leaves
# GITLORE_FETCH_TIMEOUT unset; a test sets it on the call.
commit_in_state_s() {
  state_s
  run commit_sections "memory: record"
}

ORG_YIELD="tier 'org' is checked out off the commit the memory store records for it"

@test "lock-in: gitlore-commit in state S with GITLORE_FETCH_TIMEOUT unset yields org" {
  commit_in_state_s
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ORG_YIELD"* ]]
  [[ "$output" == *"Run /gitlore:merge next"* ]]
}

@test "red: gitlore-commit in state S with GITLORE_FETCH_TIMEOUT=0 fetches and yields org as with it unset" {
  GITLORE_FETCH_TIMEOUT=0 commit_in_state_s
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ORG_YIELD"* ]]
  [[ "$output" == *"Run /gitlore:merge next"* ]]
}

@test "red: gitlore-commit in state S with GITLORE_FETCH_TIMEOUT=abc fetches and yields org as with it unset" {
  GITLORE_FETCH_TIMEOUT=abc commit_in_state_s
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ORG_YIELD"* ]]
  [[ "$output" == *"Run /gitlore:merge next"* ]]
}
