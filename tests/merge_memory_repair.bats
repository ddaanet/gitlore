#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/merge-memory

# A take's repair of a defective arrival: duplicate pointers, CRLF
# preservation, and the walk-back arms when the commit build, the scratch
# directory, the checkout follow, or the local `live` advance each fail.

@test "a take repairs a duplicate pointer that arrived and adopts the repair" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")
  # Premise: the arrival really carries the duplicate on the tier's own remote,
  # and the check refuses it, so the check passing R below is the repair's doing.
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md" > "$BATS_TEST_TMPDIR/arrival.md"
  [ "$(grep -cxF -- '- [A](a.md) — x' "$BATS_TEST_TMPDIR/arrival.md")" -eq 2 ]
  [ -n "$(gitlore_compose_check_index "$BATS_TEST_TMPDIR/arrival.md")" ]
  gitdir_before=$(tier_gitdir_files ddaanet)
  tmp_env="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$tmp_env"

  TMPDIR="$tmp_env" run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  # One parent, and it is the arrival: a commit on top, never a merge.
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory/ddaanet log -1 --format=%s "$R")" = "Repair the MEMORY.md structure ddaanet received" ]
  [[ "$(git -C memory/ddaanet log -1 --format=%b "$R")" == *"dropped a duplicate pointer line: - [A](a.md) — x"* ]]
  git -C memory/ddaanet show "$R:MEMORY.md" > "$BATS_TEST_TMPDIR/repaired.md"
  [ -z "$(gitlore_compose_check_index "$BATS_TEST_TMPDIR/repaired.md")" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line: - [A](a.md) — x"* ]]
  [[ "$output$stderr" == *"/gitlore:push publishes it"* ]]
  # Adopted and recorded: memory commits the gitlink R with root's line once.
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
  [ "$(grep -cxF -- '- [A](ddaanet/a.md) — x' memory/MEMORY.md)" -eq 1 ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(tier_gitdir_files ddaanet)" = "$gitdir_before" ]
  [ -z "$(repair_scratch_dirs "$tmp_env")" ]
  # A take publishes nothing: the tier's remote still holds the arrival.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$remote_sha" ]
}

@test "a repair keeps the arrival's CRLF bytes" {
  # The repair commit is built by hashing the rewritten arrival, and the tier
  # whose line endings these are is the one whose config decides what a filter
  # would do to them. `core.autocrlf=input` cleans CRLF out on the way into the
  # object database and leaves checkout alone, so it is the clean filter alone
  # that the hash has to refuse: the repair rewrites the lines it names and
  # nothing else, and a line ending is not one of them.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet config core.autocrlf input
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\r\n- [A](a.md) — x\r')")
  # Premise: the arrival really carries CRLF on the tier's own remote.
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" cat-file blob "$remote_sha:MEMORY.md" \
    > "$BATS_TEST_TMPDIR/arrival.md"
  [ "$(tr -dc '\r' < "$BATS_TEST_TMPDIR/arrival.md" | wc -c | tr -d ' ')" -eq 2 ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  # One duplicate dropped, and the line that stays keeps its carriage return.
  git -C memory/ddaanet cat-file blob "$R:MEMORY.md" > "$BATS_TEST_TMPDIR/repaired.md"
  [ "$(tr -dc '\r' < "$BATS_TEST_TMPDIR/repaired.md" | wc -c | tr -d ' ')" -eq 1 ]
}

@test "a repair whose commit build fails walks back and points upstream" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory/ddaanet rev-parse HEAD)
  push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')" >/dev/null

  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_git=$(command -v git)
  cat > "$fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" commit-tree "*) echo "fatal: shim refuses commit-tree" >&2; exit 1 ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"
  tmp_env="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$tmp_env"

  TMPDIR="$tmp_env" PATH="$fakebin:$PATH" run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"shim refuses commit-tree"* ]]
  [[ "$stderr" == *"building the repair commit failed"* ]]
  [[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md"* ]]
  [[ "$stderr" == *"its local 'live' keeps what arrived. Run /gitlore:merge again."* ]]
  [[ "$stderr" != *"Fix the store"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ -z "$(repair_scratch_dirs "$tmp_env")" ]
}

# The scratch directory is removed once the commit is built, so it is observed
# mid-repair: the stub lists both candidate locations when `commit-tree` runs.
@test "a repair's scratch directory lives under TMPDIR, not the tier's gitdir" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")

  gitdir=$(git -C memory/ddaanet rev-parse --absolute-git-dir)
  tmp_env="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$tmp_env"
  seen="$BATS_TEST_TMPDIR/seen"

  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_git=$(command -v git)
  cat > "$fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" commit-tree "*)
    # One of the two globs is expected to match nothing; ls reports it on stderr.
    ls -d "$gitdir"/gitlore-repair.* "$tmp_env"/gitlore-repair.* >> "$seen" 2>/dev/null
    ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"

  TMPDIR="$tmp_env" PATH="$fakebin:$PATH" run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  # Premise: the stub really ran during the repair.
  [ -e "$seen" ]
  [ "$(grep -c -F -- "$gitdir/gitlore-repair." "$seen")" -eq 0 ]
  [ "$(grep -c -F -- "$tmp_env/gitlore-repair." "$seen")" -eq 1 ]
  [ -z "$(repair_scratch_dirs "$tmp_env")" ]
  # The repair is adopted: a commit on the arrival, in `live` and memory's gitlink.
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory/ddaanet log -1 --format=%s "$R")" = "Repair the MEMORY.md structure ddaanet received" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
  [ "$(grep -cxF -- '- [A](ddaanet/a.md) — x' memory/MEMORY.md)" -eq 1 ]
}

@test "a repair whose scratch directory cannot be made walks back and points upstream" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory/ddaanet rev-parse HEAD)
  push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')" >/dev/null

  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_mktemp=$(command -v mktemp)
  cat > "$fakebin/mktemp" <<EOF
#!/bin/sh
case " \$* " in
  *gitlore-repair.*) : > "$BATS_TEST_TMPDIR/mktemp-hit"; exit 1 ;;
esac
exec "$real_mktemp" "\$@"
EOF
  chmod +x "$fakebin/mktemp"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  # Premise: the stub refused the repair's own scratch directory.
  [ -e "$BATS_TEST_TMPDIR/mktemp-hit" ]
  [[ "$stderr" == *"no scratch directory could be made"* ]]
  [[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md"* ]]
  [[ "$stderr" == *"its local 'live' keeps what arrived. Run /gitlore:merge again."* ]]
  [[ "$stderr" != *"Fix the store"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
}

@test "a repair whose checkout follow fails walks back and keeps the repair" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory/ddaanet rev-parse HEAD)
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")

  # The take's own fast-forward checks `live` out first, so the repair's own
  # checkout is the SECOND `checkout -q --detach live` call; every other call
  # forwards to the real git.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_git=$(command -v git)
  count_file="$BATS_TEST_TMPDIR/checkout-live-count"
  cat > "$fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" checkout -q --detach live "*)
    n=\$(cat "$count_file" 2>/dev/null || echo 0)
    n=\$((n + 1))
    printf '%s' "\$n" > "$count_file"
    if [ "\$n" -eq 2 ]; then
      echo "fatal: shim refuses the second checkout" >&2
      exit 1
    fi
    ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"shim refuses the second checkout"* ]]
  # The take's own fast-forward words its failure "could not follow" too; this
  # is the repair arm's line.
  [[ "$stderr" == *"its repair advanced its local 'live' but its working tree could not follow"* ]]
  [[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md"* ]]
  [[ "$stderr" == *"its local 'live' keeps the repair. Run /gitlore:merge again."* ]]
  [[ "$stderr" != *"Fix the store"* ]]
  R=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory/ddaanet log -1 --format=%s "$R")" = "Repair the MEMORY.md structure ddaanet received" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
}

@test "a repair whose live advance fails walks back and keeps the arrival" {
  export GITLORE_GIT_RETRY_SCHEDULE=0
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory/ddaanet rev-parse HEAD)
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")

  # Root's own stranded-`live` repair and the tier's take fast-forward each make
  # one `push -q . …:refs/heads/live` call ahead of the repair, so the repair's
  # own advance is the THIRD such call; every other call forwards to the real
  # git.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_git=$(command -v git)
  count_file="$BATS_TEST_TMPDIR/push-live-count"
  cat > "$fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" push -q . "*":refs/heads/live "*)
    n=\$(cat "$count_file" 2>/dev/null || echo 0)
    n=\$((n + 1))
    printf '%s' "\$n" > "$count_file"
    if [ "\$n" -eq 3 ]; then
      echo "fatal: shim refuses the third live advance" >&2
      exit 1
    fi
    ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  # Premise: the stub actually ran on the repair's own advance.
  [ "$(cat "$count_file")" -eq 3 ]
  [[ "$stderr" == *"shim refuses the third live advance"* ]]
  [[ "$stderr" == *"its repair could not advance its local 'live'"* ]]
  [[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md"* ]]
  [[ "$stderr" == *"its local 'live' keeps what arrived. Run /gitlore:merge again."* ]]
  [[ "$stderr" != *"Fix the store"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  # The advance never landed: `live` still holds the arrival, not the repair.
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
}

@test "a take's repair keeps the duplicate its pin lacks" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  push_tier_fact ddaanet '- [A](a.md) — old' >/dev/null
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  [ "$(git -C memory/ddaanet show "$pin:MEMORY.md" | grep -cxF -- '- [A](a.md) — old')" -eq 1 ]
  # The arrival adds a second, differing line for the same path after the
  # pinned one, so a repair blind to the pin would keep the first, older line.
  remote_sha=$(push_tier_fact ddaanet '- [A](a.md) — new')

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  git -C memory/ddaanet show "$R:MEMORY.md" > "$BATS_TEST_TMPDIR/repaired.md"
  [ "$(grep -cxF -- '- [A](a.md) — new' "$BATS_TEST_TMPDIR/repaired.md")" -eq 1 ]
  ! grep -qF -- '— old' "$BATS_TEST_TMPDIR/repaired.md" || false
  [[ "$output$stderr" == *"dropped a duplicate pointer line: - [A](a.md) — old"* ]]
  [ "$(grep -cxF -- '- [A](ddaanet/a.md) — new' memory/MEMORY.md)" -eq 1 ]
  ! grep -qF -- 'ddaanet/a.md) — old' memory/MEMORY.md || false
}

# The files under a tier's gitdir outside what git itself keeps moving —
# objects, logs, refs, FETCH_HEAD, ORIG_HEAD — one per line, sorted. A take's
# scratch copy or temporary index left behind shows up as a difference.
