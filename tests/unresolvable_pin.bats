#!/usr/bin/env bats
# An unresolvable pin is an integrity error at every level (no-pin-loop plan,
# "What a module reports" and question 4): a recorded commit the repository that
# should hold it lacks, whether memory's gitlink on a tier or the parent's pin on
# memory. SessionStart and /gitlore:resolve name the commit and the remote that
# lacks it, plus the repo `.gitmodules` names when that is a different repo. The
# remedy is per level: for a tier gitlink the checkout that recorded it runs
# /gitlore:push; for the parent's pin the memory holding it has not been merged
# upstream, with no command. /gitlore:resolve does not say "healthy" over it.
# By D64 `.gitmodules` records https while a module's own remote can stay on ssh,
# so "a different repo" is not a string comparison.
#
# The plan fixes none of the sentences. Tests match paragraphs of the
# systemMessage (notices are joined by a blank line) by the commit's first 12
# hex digits, the remote's url, and the command names or the phrase `merged
# upstream`.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory
load helpers/take-order
load helpers/unresolvable-pin

# --- SessionStart: a tier gitlink ---------------------------------------------

@test "SessionStart names the tier commit nobody holds and the tier remote that lacks it, with the push remedy" {
  tier_gitlink_nobody_holds
  session_start
  sys_has "${lost:0:12}" "$tier_remote" '/gitlore:push'
  ctx_has "${lost:0:12}" '/gitlore:push'
}

@test "the report of a tier commit nobody holds does not send anyone to /gitlore:merge or to a checkout" {
  tier_gitlink_nobody_holds
  session_start
  # Positive first: the paragraph exists. Then no paragraph naming the commit,
  # that one or another, carries the wrong remedy.
  sys_has "${lost:0:12}" '/gitlore:push'
  ctx_has "${lost:0:12}" '/gitlore:push'
  sys_none "${lost:0:12}" '/gitlore:merge' 'checkout --detach'
  ctx_none "${lost:0:12}" '/gitlore:merge' 'checkout --detach'
}

@test "the report of a tier commit nobody holds does not direct deleting the root lines its lost commit carried" {
  tier_gitlink_nobody_holds
  session_start
  # The push remedy makes the lines' files resolve again, and /gitlore:resolve
  # reverts them with the commit: a paragraph naming a line the lost commit
  # carried (ddaanet/lost.md) must not tell the user to delete it.
  sys_none "lost.md" 'delete'
  ctx_none "lost.md" 'delete'
  # Not satisfied by saying nothing at all: the unresolvable pin is reported.
  sys_has "${lost:0:12}" '/gitlore:push'
  ctx_has "${lost:0:12}" '/gitlore:push'
}

@test "a tier commit the tier's remote does hold is not reported as nobody's: no push remedy for it" {
  take_base_store
  held=$(push_tier_fact ddaanet "- [held](held.md) — on the remote")
  git -C memory update-index --add --cacheinfo "160000,$held,ddaanet"
  git -C memory commit -qm "record a tier commit its remote holds"
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
  session_start
  # The tier is behind its pin; the paragraph naming the commit sends the user
  # to /gitlore:merge, which fetches it.
  sys_has "${held:0:12}" '/gitlore:merge'
  sys_none "${held:0:12}" '/gitlore:push'
}

@test "SessionStart names the repo .gitmodules records for the tier when it is a different repo" {
  tier_gitlink_nobody_holds
  other=$(git init -q --bare "$TMP_REPO/.bare-other-tier.git" && printf '%s\n' "$TMP_REPO/.bare-other-tier.git")
  git config --file memory/.gitmodules submodule.ddaanet.url "$other"
  git -C memory add .gitmodules
  git -C memory commit -qm "point .gitmodules at another repo"
  git -C memory push -q . HEAD:refs/heads/live
  session_start
  sys_has "${lost:0:12}" "$tier_remote" "$other"
}

@test "SessionStart does not call https against ssh for one GitHub repo a different repo" {
  tier_gitlink_nobody_holds
  # The tier's own remote stays on ssh (D64), and git's own readers see the ssh
  # form; the stub serves the fetch from the local bare repository so nothing
  # leaves the machine.
  git -C memory/ddaanet config remote.origin.url "git@github.com:acme/tier.git"
  serve_ssh_from "$TMP_REPO/.bare-ddaanet.git" memory/ddaanet
  git config --file memory/.gitmodules submodule.ddaanet.url "https://github.com/acme/tier.git"
  git -C memory add .gitmodules
  git -C memory commit -qm "record the https form"
  git -C memory push -q . HEAD:refs/heads/live
  session_start
  sys_has "${lost:0:12}" "git@github.com:acme/tier.git"
  sys_none "${lost:0:12}" "https://github.com/acme/tier.git"
}

# --- SessionStart: the parent's pin on memory ---------------------------------

@test "SessionStart names the memory commit the parent records and memory's remote lacks, as not merged upstream" {
  parent_pin_nobody_holds
  session_start
  sys_has "${lost:0:12}" "$memory_remote" 'merged upstream'
  ctx_has "${lost:0:12}" 'merged upstream'
}

@test "the report of a parent pin nobody holds names no command and no url change" {
  parent_pin_nobody_holds
  session_start
  sys_has "${lost:0:12}" 'merged upstream'
  ctx_has "${lost:0:12}" 'merged upstream'
  sys_none "${lost:0:12}" '/gitlore:' 'git submodule sync' 'set-url'
  ctx_none "${lost:0:12}" '/gitlore:' 'git submodule sync' 'set-url'
}

@test "SessionStart names the repo .gitmodules records for memory when it is a different repo" {
  parent_pin_nobody_holds
  recorded=$(git config --file .gitmodules --get submodule.gitlore-memory.url)
  [ "$recorded" != "$memory_remote" ]
  session_start
  sys_has "${lost:0:12}" "$memory_remote" "$recorded"
}

@test "SessionStart does not call https against ssh for memory's GitHub repo a different repo" {
  parent_pin_nobody_holds
  git -C memory config remote.origin.url "git@github.com:acme/mem.git"
  serve_ssh_from "$memory_remote" memory
  git config --file .gitmodules submodule.gitlore-memory.url "https://github.com/acme/mem.git"
  git add .gitmodules
  git commit -qm "record the https form"
  session_start
  sys_has "${lost:0:12}" "git@github.com:acme/mem.git"
  sys_none "${lost:0:12}" "https://github.com/acme/mem.git"
}

# --- /gitlore:resolve ---------------------------------------------------------

@test "/gitlore:resolve over a tier commit nobody holds does not say healthy, and names the commit, the remote and the push remedy" {
  tier_gitlink_nobody_holds
  CLAUDECODE='' run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  all=$(said)
  [[ "$all" != *"healthy"* ]] || {
    printf 'resolve calls the store healthy over an unresolvable pin:\n%s\n' "$all" >&2
    return 1
  }
  [[ "$all" == *"${lost:0:12}"* ]] || { printf 'resolve never names %s:\n%s\n' "${lost:0:12}" "$all" >&2; return 1; }
  [[ "$all" == *"$tier_remote"* ]]
  [[ "$all" == *"/gitlore:push"* ]]
}

@test "/gitlore:resolve over a parent pin nobody holds does not say healthy, and names the commit, the remote and that it was not merged upstream" {
  parent_pin_nobody_holds
  CLAUDECODE='' run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  all=$(said)
  [[ "$all" != *"healthy"* ]] || {
    printf 'resolve calls the store healthy over an unresolvable pin:\n%s\n' "$all" >&2
    return 1
  }
  [[ "$all" == *"${lost:0:12}"* ]] || { printf 'resolve never names %s:\n%s\n' "${lost:0:12}" "$all" >&2; return 1; }
  [[ "$all" == *"$memory_remote"* ]]
  [[ "$all" == *"merged upstream"* ]]
}

@test "passing pin: /gitlore:resolve over a store with no unresolvable pin still says healthy" {
  take_base_store
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  [ "$status" -eq 0 ]
  [[ "$(said)" == *"healthy"* ]]
}

# --- the commit ---------------------------------------------------------------

@test "passing pin: the commit refusing a tier pin it cannot check out prints no checkout --detach for it" {
  tier_gitlink_nobody_holds
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  seed_root_bullet "proj.md" "a project fact"
  run --separate-stderr commit_sections "memory: a project fact"
  say="$output$stderr"
  # The commit refuses (a pass would change a carrier, or the pin guard fires);
  # either way it must not hand over a checkout that fails on a missing object.
  [ "$status" -ne 0 ] || {
    printf 'the commit went through over an unresolvable pin:\n%s\n' "$say" >&2
    return 1
  }
  [[ "$say" != *"checkout --detach $lost"* ]]
  [[ "$say" != *"checkout --detach ${lost:0:12}"* ]]
}

# --- /gitlore:resolve reverts the whole memory commit --------------------------

# For a tier gitlink whose holder no longer exists, resolve reverts the whole
# memory commit on `live`, never a reset, so the root lines the lost tier commit
# carried go with it. The plan does not say whether the default run does it or
# names a command that does. Run the resolver; if the store is not reverted
# afterwards, run the one command its output gives that mentions a revert,
# written as the merge directive writes a continuation (`cd "<dir>" && ...`).
resolve_until_reverted() {
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  resolve_said=$(said)
  if ! reverted; then
    revert_cmd=$(printf '%s\n' "$resolve_said" \
      | sed -n 's/^[[:space:]]*\(gitlore:[[:space:]]*\)\{0,1\}\(cd "[^"]*" && .*\)$/\2/p' \
      | grep -i 'revert' | head -n 1 || true)
    [ -n "$revert_cmd" ] || {
      printf 'resolve left the lost commit in place and names no revert command:\n%s\n' "$resolve_said" >&2
      return 1
    }
    run --separate-stderr bash -c "$revert_cmd"
    [ "$status" -eq 0 ] || { printf 'the revert command failed:\n%s\n' "$stderr" >&2; return 1; }
  fi
}

# `live` holds the recording commit and something on top of it.
reverted() {
  [ "$(git -C memory rev-parse live)" != "$recording" ] \
    && git -C memory merge-base --is-ancestor "$recording" live
}

@test "/gitlore:resolve reverts the memory commit that recorded a tier commit nobody holds, keeping it in history" {
  tier_gitlink_nobody_holds
  resolve_until_reverted
  git -C memory merge-base --is-ancestor "$recording" live
  [ "$(git -C memory rev-parse live)" != "$recording" ]
  # The tier is back at the gitlink it held before, on live.
  [ "$(git -C memory rev-parse live:ddaanet)" = "$gitlink_before" ] || {
    printf 'live records the tier at %s, not the %s it held before\n' "$(git -C memory rev-parse live:ddaanet)" "$gitlink_before" >&2
    return 1
  }
}

@test "the revert takes the whole memory commit: the root line the lost tier commit carried and the project fact beside it both go" {
  tier_gitlink_nobody_holds
  resolve_until_reverted
  run git -C memory show live:MEMORY.md
  [[ "$output" != *"ddaanet/lost.md"* ]] || { printf 'live still carries the lost commit'\''s line:\n%s\n' "$output" >&2; return 1; }
  [[ "$output" != *"proj.md"* ]]
  run git -C memory cat-file -e live:proj.md
  [ "$status" -ne 0 ]
}

@test "the revert leaves memory checked out on live with a clean tree, root's index without the lost line" {
  tier_gitlink_nobody_holds
  resolve_until_reverted
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  [ -z "$(git -C memory status --porcelain)" ]
  run grep -F 'ddaanet/lost.md' memory/MEMORY.md
  [ "$status" -ne 0 ]
  [ ! -e memory/proj.md ]
}

# --- the revert's success message lists every path the commit changed ----------

# Run `resolve.sh revert-pin ddaanet` as agent ($1 = 1) or user ($1 = ''), and
# leave everything it printed in $resolve_said.
revert_pin_said() {
  CLAUDECODE="$1" run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh" revert-pin ddaanet
  [ "$status" -eq 0 ] || { printf 'revert-pin failed:\n%s\n' "$stderr" >&2; return 1; }
  resolve_said=$(said)
}

# Succeed when $resolve_said holds a line that is exactly "  <path>".
lists_path() {
  printf '%s\n' "$resolve_said" | grep -Fxq -- "  $1" || {
    printf 'no line lists [%s]; message:\n%s\n' "$1" "$resolve_said" >&2
    return 1
  }
}

@test "the revert-pin message lists every path the reverted commit changed, the tier's gitlink and a fact file among them, to the agent" {
  tier_gitlink_nobody_holds
  revert_pin_said 1
  lists_path ddaanet
  lists_path MEMORY.md
  lists_path proj.md
}

@test "the revert-pin message lists the same paths to the user" {
  tier_gitlink_nobody_holds
  revert_pin_said ''
  lists_path ddaanet
  lists_path MEMORY.md
  lists_path proj.md
}

@test "the revert-pin message prints a path with a space intact" {
  tier_gitlink_nobody_holds
  revert_pin_said 1
  lists_path "proj notes.md"
}

@test "the revert-pin message prints a path with a newline in git's quoted form, so it adds no line of its own" {
  tier_gitlink_nobody_holds
  revert_pin_said 1
  lists_path '"odd\nname.md"'
  run ! grep -Fxe 'name.md' -e '  name.md' <<<"$resolve_said"
}

@test "the revert-pin message says how to see the full diff, with the memory path quoted" {
  tier_gitlink_nobody_holds
  revert_pin_said 1
  printf '%s\n' "$resolve_said" | grep -Fq -- "git -C \"memory\" show ${recording:0:12}" || {
    printf 'no show line; message:\n%s\n' "$resolve_said" >&2
    return 1
  }
}
