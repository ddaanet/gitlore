#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
# The fixture suite below is heredoc'd whole and carries literal `$BATS_*`
# references for the inner bats run to expand, not this one.
# shellcheck disable=SC2016

load helpers/setup

MUT="$PLUGIN_ROOT/scripts/mutate-and-run.sh"

# A throwaway repo holding a one-line subject and a suite that pins its output,
# so a mutation of the subject has somewhere real to be killed or survive.
setup() {
  setup_tmp_repo
  printf '#!/usr/bin/env bash\necho one\n' > prod.sh
  chmod +x prod.sh
  cat > subject.bats <<'EOF'
#!/usr/bin/env bats
@test "prod says one" {
  run bash "$BATS_TEST_DIRNAME/prod.sh"
  [ "$output" = one ]
}
@test "prod exits 0" {
  run bash "$BATS_TEST_DIRNAME/prod.sh"
  [ "$status" -eq 0 ]
}
EOF
  git add -A
  git commit -qm fixture
}
teardown() { teardown_tmp_repo; }

# The backup a crashed run would leave, as this repo's gitdir holds it.
backup_path() { printf '%s/subject.bak\n' "$(git rev-parse --git-path gitlore/mutate)"; }

# The subject as HEAD records it, with nothing left behind by the run.
assert_subject_restored() {
  [ "$(cat prod.sh)" = "$(git show HEAD:prod.sh)" ]
  [ -z "$(git status --porcelain)" ]
  [ ! -e "$(backup_path)" ]
}

@test "mutate-and-run is discovered by the shell linter and ships executable" {
  # Discovery is by tracked path with a shell extension, and the recorded mode
  # is what a clone reproduces — a 100644 here would ship a tool nobody can run.
  [ -x "$PLUGIN_ROOT/scripts/mutate-and-run.sh" ]
  run git -C "$PLUGIN_ROOT" ls-files -s -- scripts/mutate-and-run.sh
  [ "$status" -eq 0 ]
  [[ "$output" == 100755* ]]
  run git -C "$PLUGIN_ROOT" ls-files -- '*.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/mutate-and-run.sh"* ]]
}

@test "a mutation the suite catches is reported KILLED, with the failing test named" {
  run "$MUT" prod.sh 's/one/two/' subject.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"KILLED"* ]]
  [[ "$output" != *"SURVIVED"* ]]
  # The reviewer needs the test that died, not just the verdict.
  [[ "$output" == *"not ok 1 prod says one"* ]]
  assert_subject_restored
}

@test "a mutation no test discriminates is reported SURVIVED" {
  # Behaviour-preserving: the subject changes, every assertion still holds.
  run "$MUT" prod.sh 's|/usr/bin/env bash|/bin/bash|' subject.bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"SURVIVED"* ]]
  [[ "$output" != *"KILLED"* ]]
  assert_subject_restored
}

@test "a filter narrows the run, and one that selects no test is refused" {
  run "$MUT" prod.sh 's/one/two/' subject.bats 'says one'
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 test(s) ran"* ]]
  assert_subject_restored

  run "$MUT" prod.sh 's/one/two/' subject.bats 'no such test'
  [ "$status" -eq 2 ]
  [[ "$output" == *"selected no test"* ]]
  assert_subject_restored
}

@test "a subject with uncommitted changes is refused, staged or not" {
  printf 'echo extra\n' >> prod.sh
  dirty="$(cat prod.sh)"
  run "$MUT" prod.sh 's/one/two/' subject.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [ "$(cat prod.sh)" = "$dirty" ]
  [ ! -e "$(backup_path)" ]

  git add prod.sh
  run "$MUT" prod.sh 's/one/two/' subject.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [ "$(cat prod.sh)" = "$dirty" ]
  [ ! -e "$(backup_path)" ]
}

@test "an untracked subject is refused, because the restore could not be verified" {
  printf '#!/usr/bin/env bash\necho one\n' > loose.sh
  run "$MUT" loose.sh 's/one/two/' subject.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"not tracked"* ]]
  [ "$(cat loose.sh)" = "$(printf '#!/usr/bin/env bash\necho one')" ]
}

@test "a mutation that changes nothing is refused as empty" {
  run "$MUT" prod.sh 's/never-appears/two/' subject.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"unchanged"* ]]
  [[ "$output" != *"SURVIVED"* ]]
  assert_subject_restored
}

@test "a sed script that will not parse is refused" {
  run "$MUT" prod.sh 's/[unclosed/two/' subject.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"sed script failed"* ]]
  assert_subject_restored
}

@test "a backup left by a crashed run refuses the next one and names the restore" {
  work="$(git rev-parse --git-path gitlore/mutate)"
  mkdir -p "$work"
  printf '#!/usr/bin/env bash\necho one\n' > "$work/subject.bak"
  printf '%s\0' "$TMP_REPO/prod.sh" > "$work/subject.path"
  # The crashed run's mutant is still in place; nothing may overwrite it.
  printf '#!/usr/bin/env bash\necho two\n' > prod.sh

  run "$MUT" prod.sh 's/one/three/' subject.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"previous run left a backup"* ]]
  [[ "$output" == *"$work/subject.bak"* ]]
  [[ "$output" == *"$TMP_REPO/prod.sh"* ]]
  # The refusal is inert: the backup and the crashed run's mutant both stand.
  [ -f "$work/subject.bak" ]
  [ "$(cat prod.sh)" = "$(printf '#!/usr/bin/env bash\necho two')" ]

  # The command it printed is the one that repairs the tree.
  cat "$work/subject.bak" > "$TMP_REPO/prod.sh" && rm -f "$work/subject.bak" "$work/subject.path"
  assert_subject_restored
}

@test "a signal during the run restores the subject and exits refused" {
  cat > slow.bats <<'EOF'
#!/usr/bin/env bats
@test "prod says one, slowly" {
  sleep 1
  run bash "$BATS_TEST_DIRNAME/prod.sh"
  [ "$output" = one ]
}
EOF
  git add slow.bats
  git commit -qm slow

  "$MUT" prod.sh 's/one/two/' slow.bats > /dev/null 2>&1 &
  pid=$!
  # Signal only once the mutant is actually in place, so the trap is what puts
  # the subject back rather than the run never having touched it.
  mutated=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if grep -q two prod.sh; then mutated=1; break; fi
    sleep 0.1
  done
  [ "$mutated" -eq 1 ]
  kill -TERM "$pid"
  # The trap fires once the foreground bats child returns, so this waits out
  # the fixture's sleep rather than racing it.
  wait "$pid" || status=$?
  [ "${status:-0}" -eq 2 ]
  assert_subject_restored
}

@test "a wrong argument count and a missing path are usage errors" {
  run "$MUT" prod.sh 's/one/two/'
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: mutate-and-run.sh"* ]]

  run "$MUT" prod.sh 's/one/two/' subject.bats 'filter' 'extra'
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: mutate-and-run.sh"* ]]

  run "$MUT" absent.sh 's/one/two/' subject.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"no such file"* ]]

  run "$MUT" prod.sh 's/one/two/' absent.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"no such suite"* ]]
}
