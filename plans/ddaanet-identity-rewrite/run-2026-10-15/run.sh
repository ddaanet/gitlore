#!/usr/bin/env bash
# Option H, end to end: record, archive and force-push the tier and the memory
# store, force-push gitlore and its tags, cross the thirteen other clones (tier
# crossing, approved memory commit, memory push, parent commit of `memory`
# only), then repoint this checkout. Parent pushes of the other clones are left
# to their owner: most hold unrelated unpushed work.
#
# Usage, under bash: bash run.sh go
#
# Every step is idempotent: it reads the state it would produce and skips what
# is already there. After any failure, fix the cause and run it again.
# Preflight accepts each ref at its old id or its new one, and nothing else.
# Paths, URLs and the newline-separated CLONES can be overridden from the
# environment for a rehearsal.
set -euo pipefail

main() {
  [ "${1:-}" = go ] || die "pass 'go' once the laptop runs gitlore 0.10.0 and no session is live in any clone, on any machine."
  CLONE_LIST=()
  while IFS= read -r n || [ -n "$n" ]; do
    [ -z "$n" ] || CLONE_LIST+=("$n")
  done <<<"$CLONES"
  preflight
  push_store tier "$TIER_URL" "$TIER_OLD" "$TIER_NEW"
  push_store memory "$MEM_URL" "$MEM_LIVE_OLD" "$MEM_LIVE_NEW"
  push_ref memory "$MEM_URL" refs/heads/main "$MEM_MAIN_OLD" "$MEM_MAIN_NEW"
  push_gitlore
  cross_clones
  repoint_checkout
  echo
  echo "DONE. Parents of the other clones are committed, not pushed."
}

preflight() {
  step "0. preflight"
  for m in tier memory gitlore; do
    [ -d "$W/$m-before.git" ] || die "mirror $W/$m-before.git is missing; redo the run."
    [ -d "$W/$m-after.git" ] || die "mirror $W/$m-after.git is missing; redo the run."
  done
  for c in "$TIER_NEW" "$MEM_LIVE_NEW" "$MEM_MAIN_NEW" "$MEM_LOCAL_MAIN_NEW" "$GL_NEW" "$GL_LOCAL_NEW"; do
    found=0
    for m in tier memory gitlore; do
      if git -C "$W/$m-after.git" cat-file -e "$c^{commit}" 2>/dev/null; then found=1; fi # absence is the case tested
    done
    [ "$found" = 1 ] || die "no after-mirror holds $c: wrong or stale mirrors."
  done
  [ -f "$CACHE/scripts/cross-rewrite.sh" ] || die "$CACHE is gone: the 0.10.0 plugin cache was removed."

  remote_at "$TIER_URL" refs/heads/live "$TIER_OLD" "$TIER_NEW"
  remote_at "$MEM_URL" refs/heads/live "$MEM_LIVE_OLD" "$MEM_LIVE_NEW"
  remote_at "$MEM_URL" refs/heads/main "$MEM_MAIN_OLD" "$MEM_MAIN_NEW"
  remote_at "$GL_URL" refs/heads/main "$GL_OLD" "$GL_NEW"

  # Lost commits: the final reset replaces main and tier-triage-nudge, so both
  # must hold nothing the mirrors lack — still at the mirrored id, or rewritten.
  [ "$(git -C "$L" symbolic-ref -q HEAD)" = refs/heads/main ] || die "$L is not on main."
  local_at "$L" refs/heads/main "$GL_LOCAL_OLD" "$GL_LOCAL_NEW"
  local_at "$L" refs/heads/tier-triage-nudge "$NUDGE_OLD" "$NUDGE_NEW"
  local_at "$L/memory" refs/heads/live "$MEM_LIVE_OLD" "$MEM_LIVE_NEW"
  local_at "$L/memory" refs/heads/main "$MEM_LOCAL_MAIN_OLD" "$MEM_LOCAL_MAIN_NEW"
  clean "$L" --untracked-files=no
  clean "$L/memory"
  clean "$L/memory/ddaanet"

  # Unapproved content: the crossing commit takes everything in memory, so
  # each clone's memory store and tier must be clean, untracked files included.
  for n in "${CLONE_LIST[@]}"; do
    clean "$CODE/$n/memory"
    clean "$CODE/$n/memory/ddaanet"
  done
  echo "ok: mirrors, 0.10.0 cache, remote refs, this checkout, ${#CLONE_LIST[@]} clones clean"
}

# The record, the archive branch and `live` of one rewritten store.
push_store() {
  name=$1 url=$2 old=$3 new=$4
  step "$name: record, archive, live"
  "$L/scripts/record-rewrite.sh" "$W/$name-after.git" "$W/$name-after.git/filter-repo/commit-map" "$url"
  if [ -z "$(remote_id "$url" "$ARCHIVE")" ]; then
    git -C "$W/$name-before.git" push "$url" "$old:$ARCHIVE"
  fi
  remote_at "$url" "$ARCHIVE" "$old" "$old"
  push_ref "$name" "$url" refs/heads/live "$old" "$new"
}

push_ref() {
  name=$1 url=$2 ref=$3 old=$4 new=$5
  if [ "$(remote_id "$url" "$ref")" != "$new" ]; then
    git -C "$W/$name-after.git" push --force-with-lease="$ref:$old" "$url" "$new:$ref"
  fi
  remote_at "$url" "$ref" "$new" "$new"
  echo "ok: $name $ref at ${new:0:7}"
}

push_gitlore() {
  step "gitlore: main, tags"
  push_ref gitlore "$GL_URL" refs/heads/main "$GL_OLD" "$GL_NEW"
  git -C "$W/gitlore-after.git" push -q --force "$GL_URL" '+refs/tags/v*:refs/tags/v*'
  remote_tags=$(git ls-remote "$GL_URL" 'refs/tags/*')
  mirror_tags=$(git -C "$W/gitlore-after.git" ls-remote . 'refs/tags/*')
  [ "$remote_tags" = "$mirror_tags" ] || die "remote tags differ from the rewritten mirror's."
  echo "ok: tags identical"
  [ "${SKIP_GH:-}" != 1 ] || return 0
  # Advisory: a gh failure warns, it never passes.
  if drafts=$(gh release list -R ddaanet/gitlore -L 50 --json isDraft --jq '[.[] | select(.isDraft)] | length'); then
    if [ "$drafts" = 0 ]; then echo "ok: no release is a draft"; else echo "WARN: $drafts releases are drafts; check them on GitHub."; fi
  else
    echo "WARN: gh could not list the releases; check them on GitHub."
  fi
}

cross_clones() {
  step "the other clones"
  failed=0
  for n in "${CLONE_LIST[@]}"; do
    printf -- '-- %s\n' "$n"
    # Not an `if` condition: errexit is ignored inside one.
    set +e
    (
      set -e
      cross_one "$CODE/$n"
    )
    rc=$?
    set -e
    if [ "$rc" != 0 ]; then
      echo "FAILED: $n (message above)"
      failed=$((failed + 1))
    fi
  done
  [ "$failed" = 0 ] || die "$failed clone(s) failed. Fix each and rerun: finished clones pass through unchanged."
}

# Each stage is skipped once done: the crossing says `nothing to cross`, a
# clean memory store has nothing to commit, the memory push is a no-op, and a
# parent already recording memory's HEAD needs no commit.
cross_one() {
  cd "$1"
  export CLAUDE_PLUGIN_ROOT=$CACHE
  "$CACHE/scripts/cross-rewrite.sh" memory/ddaanet
  if [ -n "$(git -C memory status --porcelain)" ]; then
    bash "$CACHE/scripts/commit-memory.sh" -F - <<'EOF'
Cross the ddaanet tier to its rewritten history

The ddaanet tier's history was rewritten to correct the author identity on 55 commits; the tier gitlink moves to the rewritten counterpart of the same content. No fact changes.
EOF
  fi
  # The push may fast-forward the tier to the new tip and add a bookkeeping
  # memory commit, so the parent commit follows it and records the pushed head.
  bash "$CACHE/scripts/push-memory.sh"
  if [ "$(git rev-parse HEAD:memory)" != "$(git -C memory rev-parse HEAD)" ]; then
    git add memory
    git commit -q -m "🔧 memory: cross the ddaanet tier to its rewritten history" -- memory
  fi
  check "memory records the tier's HEAD" [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  check "the parent records memory's HEAD" [ "$(git rev-parse HEAD:memory)" = "$(git -C memory rev-parse HEAD)" ]
  check "memory's HEAD is its pushed live" [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse origin/live)" ]
  check "the tier is on the new remote live" git -C memory/ddaanet merge-base --is-ancestor HEAD origin/live
  check "the tier reaches no wrong identity" no_wrong_identity memory/ddaanet HEAD
  echo "ok: crossed; parent at $(git rev-parse --short HEAD) on $(git symbolic-ref -q --short HEAD || echo detached)"
}

repoint_checkout() {
  step "this checkout"
  cd "$L"
  git -C memory fetch -q --no-recurse-submodules "$W/memory-after.git" "$MEM_LOCAL_MAIN_NEW"
  scripts/cross-rewrite.sh memory/ddaanet
  scripts/cross-rewrite.sh memory
  git fetch -q --no-recurse-submodules "$W/gitlore-after.git" '+refs/heads/main:refs/rewrite/main' '+refs/heads/tier-triage-nudge:refs/heads/tier-triage-nudge' '+refs/tags/*:refs/tags/*'
  git reset -q --hard refs/rewrite/main
  git update-ref -d refs/rewrite/main
  git fetch -q --no-recurse-submodules origin
  local_at . HEAD "$GL_LOCAL_NEW" "$GL_LOCAL_NEW"
  local_at . refs/remotes/origin/main "$GL_NEW" "$GL_NEW"
  local_at . HEAD:memory "$MEM_LIVE_NEW" "$MEM_LIVE_NEW"
  local_at memory HEAD "$MEM_LIVE_NEW" "$MEM_LIVE_NEW"
  local_at memory refs/heads/main "$MEM_LOCAL_MAIN_NEW" "$MEM_LOCAL_MAIN_NEW"
  local_at memory/ddaanet HEAD "$CHECKOUT_TIER" "$CHECKOUT_TIER"
  clean . --untracked-files=no
  check "gitlore reaches no wrong identity" no_wrong_identity . --branches --tags
  check "memory reaches no wrong identity" no_wrong_identity memory --branches
  check "the tier reaches no wrong identity" no_wrong_identity memory/ddaanet refs/heads/live refs/heads/main
  echo "ok: checkout repointed"
}

# The log is captured first, so a failing git is an error rather than zero hits.
no_wrong_identity() {
  d=$1
  shift
  idents=$(git -C "$d" log "$@" --format='%ae%n%ce')
  ! grep -qx -F -e t@e.c -e gitlore@local -e gitlore@localhost <<<"$idents"
}

check() {
  what=$1
  shift
  "$@" || die "check failed: $what."
}

clean() {
  [ -e "$1/.git" ] || die "$1 is not checked out."
  st=$(git -C "$1" status --porcelain "${@:2}")
  [ -z "$st" ] || die "$1 has changes:"$'\n'"$st"
}

remote_id() {
  out=$(git ls-remote "$1" "$2")
  printf '%s' "${out%%[[:space:]]*}"
}

remote_at() {
  got=$(remote_id "$1" "$2")
  [ "$got" = "$3" ] || [ "$got" = "$4" ] || die "$1 $2 is '${got:-absent}', expected $3 or $4."
}

local_at() {
  got=$(git -C "$1" rev-parse --verify -q "$2") || die "$1 has no $2."
  [ "$got" = "$3" ] || [ "$got" = "$4" ] || die "$1 $2 is $got, expected $3 or $4."
}

step() { printf '\n== %s\n' "$1"; }

die() {
  printf 'STOP: %s\nFix the cause and rerun "bash run.sh go": finished steps are skipped.\n' "$1" >&2
  exit 1
}

W=${W:-/tmp/claude-1000/identity-rewrite-h2}
L=${L:-/Users/david/code/gitlore}
CODE=${CODE:-/Users/david/code}
CACHE=${CACHE:-/Users/david/.claude/plugins/cache/ddaanet/gitlore/0.10.0}
TIER_URL=${TIER_URL:-git@github.com:ddaanet/ddaanet-memory.git}
MEM_URL=${MEM_URL:-git@github.com:ddaanet/gitlore-memory.git}
GL_URL=${GL_URL:-git@github.com:ddaanet/gitlore.git}
CLONES=${CLONES:-"claude-plugin-dev
craft
cwd-safety
edify
ghmem
handoff
micro-contrib
micro-craft
onekeys
plugin-craft
prohibitions
sandbox-lies
shell-gotchas"}
ARCHIVE=refs/heads/gitlore/archive/2026-10-15

TIER_OLD=9662781221a887f9a7f050f3bce0ecf4552db6d9
TIER_NEW=68954767eea7d050704e6181f23b76cb917ad91f
CHECKOUT_TIER=9103be7403df44f0a663e101264060b6b4e596af
MEM_LIVE_OLD=a116ed627a5b80930ba4b42fdf9a12b2a39e3fde
MEM_LIVE_NEW=3878a6d0e5e3d4cd82f4d754611cb9a6ed3306df
MEM_MAIN_OLD=497ac390c253735bf19a4540e92c21d92badb0e9
MEM_MAIN_NEW=daf75b558f33da97d28a172e6d2539b7e7ce5676
MEM_LOCAL_MAIN_OLD=daf5f59e663b067969d4dd5bf9e43b2ac4f1c123
MEM_LOCAL_MAIN_NEW=a46bdd2f47656fbcd7d897b9c71c90975e371468
GL_OLD=e993b49a295e956b032a7b8bcccd09fdd0b785c6
GL_NEW=09e6ad88cddf08c548bdff8f140b8d7448bb912d
GL_LOCAL_OLD=22519aaba95b93f1fd733e8fce4603a1c7ed714b
GL_LOCAL_NEW=349818227d4ef57b02d1da2d49a268083adbe5e6
NUDGE_OLD=76f9d8b1fb1213881feb54ffd02838460e743d62
NUDGE_NEW=17a1bb3a2dadc64c808bbe49f5e213970f11a917

main "$@"
