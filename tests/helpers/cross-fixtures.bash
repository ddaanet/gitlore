#!/usr/bin/env bash
# shellcheck disable=SC2153,SC2154
# Fixtures for the crossing script (D62): a tier or a memory store whose remote
# was rewritten, with the clone still on the old history. Builds on
# rewrite-fixtures.bash (load it first).
#
# Tier (memory/ddaanet), via cx_tier_setup:
#   P - O1 - O2   rewritten to   P - N1 - N2      (map: O1 N1, O2 N2)
#   chain: a second rewrite     P - X1 - X2       (appended: N1 X1, N2 X2)
#   globals: RW_P RW_O1 RW_O2 RW_N1 RW_N2 and, for chain, CX_X1 CX_X2
#
# Memory store (memory), via cx_memory_setup, on top of the tier above:
#   MP - M1 - M2   rewritten to   MP - M1' - M2'
#   M1/M2 pin the tier at O1/O2; M1'/M2' pin it at the mapped ids (mode-dependent).
#   globals: CX_MP CX_M1 CX_M2 CX_M1N CX_M2N
#   The record on the memory remote: M1 M1', M2 M2'.

export CX_ZEROS=0000000000000000000000000000000000000000

# Mount the tier, rewrite its remote, optionally a second time.
# Args: $1=single|chain
cx_tier_setup() {
  make_parent_with_memory || return 1
  mount_tier_at_live ddaanet || return 1
  rewrite_remote_history memory/ddaanet "$TMP_REPO/.bare-ddaanet.git" || return 1
  if [ "$1" = chain ]; then
    cx_chain_remote "$TMP_REPO/.bare-ddaanet.git" || return 1
  fi
}

# A second rewrite of a bare remote whose `live` is N2: new ids X1/X2, the record
# appended (never replaced). Own committer, so X cannot equal N when both land in
# one second.
# Args: $1=bare
cx_chain_remote() {
  local bare="$1"
  CX_X1=$(cx_commit "$bare" "$RW_N1^{tree}" "$RW_P" second "$(git -C "$bare" log -1 --format=%s "$RW_N1")") || return 1
  CX_X2=$(cx_commit "$bare" "$RW_N2^{tree}" "$CX_X1" second "$(git -C "$bare" log -1 --format=%s "$RW_N2")") || return 1
  [ "$CX_X1" != "$RW_N1" ] && [ "$CX_X2" != "$RW_N2" ] || return 1
  git -C "$bare" update-ref refs/heads/live "$CX_X2" || return 1
  cx_record_commit "$bare" "$(cx_record_map "$bare")
$RW_N1 $CX_X1
$RW_N2 $CX_X2" append || return 1
  export CX_X1 CX_X2
}

# commit-tree with a named identity.
# Args: $1=repo  $2=tree  $3=parent  $4=identity name  $5=message
cx_commit() {
  GIT_AUTHOR_NAME="$4" GIT_AUTHOR_EMAIL="$4@t" \
  GIT_COMMITTER_NAME="$4" GIT_COMMITTER_EMAIL="$4@t" \
    git -C "$1" commit-tree "$2" -p "$3" -m "$5"
}

# The record's current map text on a bare remote.
cx_record_map() { git --git-dir="$1" show refs/heads/gitlore/rewrites:map; }

# Point the remote's record at a new commit holding version 1 and the given map.
# Args: $1=bare  $2=map text  $3=replace|append (append puts it on the old tip)
cx_record_commit() {
  local bare="$1" mblob vblob tree commit parent=()
  [ "${3:-replace}" != append ] || parent=(-p "$(git --git-dir="$bare" rev-parse refs/heads/gitlore/rewrites)")
  mblob=$(printf '%s\n' "$2" | git --git-dir="$bare" hash-object -w --stdin) || return 1
  vblob=$(printf '1\n' | git --git-dir="$bare" hash-object -w --stdin) || return 1
  tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" \
    | git --git-dir="$bare" mktree) || return 1
  commit=$(git --git-dir="$bare" -c user.email=t@t -c user.name=t \
    commit-tree "$tree" "${parent[@]}" -m "record rewrite") || return 1
  git --git-dir="$bare" update-ref refs/heads/gitlore/rewrites "$commit"
}

# Put a store's HEAD (detached), `live` and optionally `main` on given commits.
# The commits' objects must already be in the store. Fetches nothing.
# Args: $1=store  $2=HEAD  $3=live  $4=main (optional)
cx_position() {
  git -C "$1" checkout -q --detach "$2" || return 1
  git -C "$1" update-ref refs/heads/live "$3" || return 1
  [ -z "${4:-}" ] || git -C "$1" update-ref refs/heads/main "$4"
}

# What a refusal must leave alone, for a store: rewrite_store_snapshot plus the
# rewrite record ref (a refusal before the fetch leaves it absent).
# Args: $1=store
cx_snapshot() {
  rewrite_store_snapshot "$1"
  git -C "$1" rev-parse -q --verify refs/gitlore/rewrites || true
  git -C "$1" rev-parse -q --verify refs/remotes/origin/live || true
}

# True when HEAD is detached.
cx_detached() { ! git -C "$1" symbolic-ref -q HEAD >/dev/null; }

# assert_no_archive_fetched keyed on a given archive tip.
# Args: $1=store  $2=archive tip sha
cx_assert_no_archive() {
  local saved="$RW_O2" rc=0
  RW_O2="$2"
  assert_no_archive_fetched "$1" || rc=1
  RW_O2="$saved"
  return "$rc"
}

# --- the memory store ---

# Build the memory store's rewrite on top of cx_tier_setup, and leave the clone
# on the old history (HEAD = live = M2) with the tier at the old commit O2 (or
# at P for `unmapped`). Mode picks what M1'/M2' pin:
#   mapped    N1/N2 (the tier's mapped ids)
#   chain     X1/X2 (the tier's chained ids; needs cx_tier_setup chain)
#   unmapped  P for old and new (the tier's P has no line in its record)
#   wrong     N1/N1 (M2' pins a commit the record does not map O2 to)
#   moved     old P/P, new P/N1 (P has no line, yet M2' pins another commit)
#   extra     as mapped, but M2' also adds a file M2 lacks (a non-gitlink
#             difference in a tree whose gitlink maps correctly)
# Args: $1=mapped|chain|unmapped|wrong|moved|extra
cx_memory_setup() {
  local mode="$1" bare="$TMP_REPO/.bare-memory.git" work
  local g1_old g2_old g1_new g2_new extra=()
  case "$mode" in
    mapped)   g1_old=$RW_O1 g2_old=$RW_O2 g1_new=$RW_N1 g2_new=$RW_N2 ;;
    chain)    g1_old=$RW_O1 g2_old=$RW_O2 g1_new=$CX_X1 g2_new=$CX_X2 ;;
    unmapped) g1_old=$RW_P  g2_old=$RW_P  g1_new=$RW_P  g2_new=$RW_P ;;
    wrong)    g1_old=$RW_O1 g2_old=$RW_O2 g1_new=$RW_N1 g2_new=$RW_N1 ;;
    moved)    g1_old=$RW_P  g2_old=$RW_P  g1_new=$RW_P  g2_new=$RW_N1 ;;
    extra)    g1_old=$RW_O1 g2_old=$RW_O2 g1_new=$RW_N1 g2_new=$RW_N2 extra=(cx-extra.md extra) ;;
    *) echo "cx_memory_setup: unknown mode $mode" >&2; return 1 ;;
  esac
  git -C memory push -q origin live || return 1
  CX_MP=$(git -C memory rev-parse live)
  work=$(mktemp -d "${TMP_REPO}/cx-work.XXXXXX") || return 1
  git clone -q "$bare" "$work" || return 1
  CX_M1=$(cx_commit "$work" "$(cx_tree "$work" "$CX_MP^{tree}" "$g1_old" cx-m1.md one)" "$CX_MP" old "memory one") || return 1
  CX_M2=$(cx_commit "$work" "$(cx_tree "$work" "$CX_MP^{tree}" "$g2_old" cx-m1.md one cx-m2.md two)" "$CX_M1" old "memory two") || return 1
  git -C "$work" branch old-tip "$CX_M2"
  git -C memory fetch -q "$work" "refs/heads/old-tip:refs/gitlore-fixture/old-tip" || return 1
  CX_M1N=$(cx_commit "$work" "$(cx_tree "$work" "$CX_MP^{tree}" "$g1_new" cx-m1.md one)" "$CX_MP" rewritten "memory one") || return 1
  CX_M2N=$(cx_commit "$work" "$(cx_tree "$work" "$CX_MP^{tree}" "$g2_new" cx-m1.md one cx-m2.md two ${extra[@]+"${extra[@]}"})" "$CX_M1N" rewritten "memory two") || return 1
  git -C "$work" push -q origin "$CX_M2:refs/heads/gitlore/archive/2026-10-15" || return 1
  git -C "$work" push -q -f origin "$CX_M2N:refs/heads/live" || return 1
  cx_record_commit "$bare" "$CX_M1 $CX_M1N
$CX_M2 $CX_M2N" || return 1
  rm -rf "$work"
  export CX_MP CX_M1 CX_M2 CX_M1N CX_M2N
  # The memory store first (its checkout leaves the tier worktree alone), then
  # the tier, so the pinned gitlink and the tier's HEAD agree.
  cx_position memory "$CX_M2" "$CX_M2" || return 1
  if [ "$mode" != unmapped ] && [ "$mode" != moved ]; then
    cx_position memory/ddaanet "$RW_O2" "$RW_O2" || return 1
  fi
  [ -z "$(git -C memory status --porcelain)" ] \
    || { echo "cx_memory_setup: memory is not clean: $(git -C memory status --porcelain)" >&2; return 1; }
}

# A tree like $2 in repo $1 with its gitlink swapped for $3 and files added.
# Args: $1=repo  $2=base tree-ish  $3=gitlink sha  then name/content pairs
cx_tree() {
  local repo="$1" base="$2" link="$3" name blob
  shift 3
  {
    git -C "$repo" ls-tree "$base" | awk -F'\t' -v link="$link" '{
      split($1, a, " ")
      if (a[1] == "160000") printf "160000 commit %s\t%s\n", link, $2; else print }'
    while [ $# -ge 2 ]; do
      name="$1"
      blob=$(printf '%s\n' "$2" | git -C "$repo" hash-object -w --stdin) || return 1
      printf '100644 blob %s\t%s\n' "$blob" "$name"
      shift 2
    done
  } | git -C "$repo" mktree --missing
}

# What the tier's crossing leaves behind, by hand: the tier on its mapped id
# (fetched from its remote's live) with the gitlink staged in the memory store.
# Args: $1=the tier's final id for O2
cx_fixture_cross_tier() {
  git -C memory/ddaanet fetch -q origin +refs/heads/live:refs/remotes/origin/live || return 1
  cx_position memory/ddaanet "$1" "$1" || return 1
  git -C memory add ddaanet
}

# Every refusal is prefixed, so a message is attributable.
refused() {
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"cross-rewrite:"* ]]
}

# A tier on old history: HEAD = live = O2, main on the shared prefix.
tier_old() {
  cx_tier_setup single
  cx_position "$TIER" "$RW_O2" "$RW_O2"
}
