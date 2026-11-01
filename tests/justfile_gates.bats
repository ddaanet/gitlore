#!/usr/bin/env bats
# Guards on this repo's own `justfile`, which is the only place the gates are
# defined now that the Makefile is gone. Like plugin_distribution.bats, these
# inspect gitlore's real files rather than a fixture: the failure they exist to
# catch is a suite that no longer runs, and a fixture cannot show that.

# `run` here takes flags (`!`, `--separate-stderr`), which bats honours
# only once the suite declares the version that introduced them.
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/justfile-gates

# Every .bats file the repo has, tracked or merely written — the same set the
# recipes' globs see, so a brand-new suite counts before it is added.
all_suites() {
  git -C "$PLUGIN_ROOT" ls-files --cached --others --exclude-standard -- tests \
    | grep '\.bats$' \
    | sort
}

# What `just test` would hand to bats, with bats stubbed out. The stub writes
# its arguments to a file and prints one passing TAP line: the quiet runner
# shows nothing of a passing run, and counts a run with no test as a failure.
# Filtered to *.bats lines: the recipes also pass `--jobs <n>` and the junit
# report flags, which the stub records like any other arg but which aren't
# suites. `bats --version`, which the gate hash folds in, is answered too. Forced, because the runners are
# gates: a recorded pass would skip discovery and hand back nothing. The
# sentinels go to a scratch directory: this runs the real recipes in the real
# repo, and a stubbed pass recorded there would overwrite the verdicts of the
# very gate this suite is running under. The stub writes no junit report, and
# `run-bats-cached.sh` says so on stderr; the raw output keeps that beside the
# recipes' own for a failing run to show.
#
# Run once per file, not once per test: the run hashes the whole input tree,
# and three tests below all want the same discovery output. Its own stub dir
# (separate from the per-test one `helpers/justfile-gates.bash`'s `setup()`
# still makes for the other tests in this file) and its result live under
# `$BATS_FILE_TMPDIR`, since `setup_file` and the tests it precedes run in
# separate processes and share no variables — only files.
setup_file() {
  command -v just > /dev/null || {
    echo "just is not on PATH; the gate recipes cannot be inspected" >&2
    return 1
  }
  local stub_dir status
  stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-justfile-stub.XXXXXX")"
  cat > "$stub_dir/bats" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo "Bats stub"; exit 0; }
printf '%s\n' "$@" >> "$(dirname "$0")/args"
echo "1..1"
echo "ok 1 stub"
EOF
  chmod +x "$stub_dir/bats"
  printf '%s\n' "$stub_dir" > "$BATS_FILE_TMPDIR/discovered_suites.stub_dir"

  if ( cd "$PLUGIN_ROOT" && PATH="$stub_dir:$PATH" PLUGIN_DEV_GATE_FORCE=1 PLUGIN_DEV_GATE_DIR="$stub_dir/gates" just test-unit test-integration ) \
      > "$BATS_FILE_TMPDIR/discovered_suites.raw" 2>&1
  then status=0
  else status=$?
  fi
  printf '%s\n' "$status" > "$BATS_FILE_TMPDIR/discovered_suites.status"
  touch "$stub_dir/args"
  grep '\.bats$' "$stub_dir/args" > "$BATS_FILE_TMPDIR/discovered_suites.out" || true
}

teardown_file() {
  # Absent when `setup_file` stopped at its `just` guard.
  [ -f "$BATS_FILE_TMPDIR/discovered_suites.stub_dir" ] || return 0
  rm -rf "$(cat "$BATS_FILE_TMPDIR/discovered_suites.stub_dir")"
}

@test "the stubbed discovery run records its sentinels in a scratch directory, not this repo's" {
  [ "$(cat "$BATS_FILE_TMPDIR/discovered_suites.status")" -eq 0 ]
  local stub_dir
  stub_dir="$(cat "$BATS_FILE_TMPDIR/discovered_suites.stub_dir")"
  [ -f "$stub_dir/gates/test-unit" ]
  [ -f "$stub_dir/gates/test-integration" ]
}

@test "every suite under tests/ is run by one of the test recipes" {
  # The regression this exists for: `make test` once hand-listed its suites and
  # five of them (21 tests) drifted off the list, including the memory-gate
  # cover. Nothing was red — they simply never ran.
  [ "$(cat "$BATS_FILE_TMPDIR/discovered_suites.status")" -eq 0 ]
  discovered="$(sort "$BATS_FILE_TMPDIR/discovered_suites.out")"
  [ "$discovered" = "$(all_suites)" ]
}

@test "no suite is run twice" {
  [ "$(cat "$BATS_FILE_TMPDIR/discovered_suites.status")" -eq 0 ]
  dupes="$(sort "$BATS_FILE_TMPDIR/discovered_suites.out" | uniq -d)"
  [ -z "$dupes" ]
}

@test "the test recipes discover by glob, never by a hand-written list" {
  # A list is what drifts. Any literal suite name in the justfile is one --
  # except two that name suites on purpose and cannot drift silently.
  # check-distribution gates a fixed set of assertions rather than a discovered
  # set, and `distribution_inputs` declares the same path, so
  # justfile_gate_inputs.bats fails the moment it stops existing.
  # `reads_all_suites` is an exception list no glob can produce; the
  # globs-siblings test below fails when a suite belongs on it and is missing,
  # and checks that every name on it is a suite that exists.
  literals="$(grep -n '[A-Za-z_]\.bats' "$PLUGIN_ROOT/justfile" || true)"
  stray="$(printf '%s\n' "$literals" \
    | grep -v 'tests/plugin_distribution\(_commands\)\?\.bats' \
    | grep -v '^[0-9]*:reads_all_suites :=' || true)"
  [ -z "$stray" ]
}

@test "the recipes release and precommit depend on still exist" {
  # `release` (vendored in plugin-dev/release.just) depends on `prerelease`, and
  # just rejects the whole justfile if a dependency names a missing recipe — but
  # `precommit` reaches check-version/lint/test through a shell line, which just
  # cannot check. Renaming one of those would only surface at gate time.
  run just_here --summary
  [ "$status" -eq 0 ]
  for recipe in precommit prerelease evals check-distribution check-version lint test test-unit test-integration release; do
    [[ " $output " == *" $recipe "* ]]
  done
}

@test "precommit depends on the distribution gate, and prerelease inherits it" {
  # The wiring the separate gate exists for. `precommit` reaches
  # check-version/lint/test through a shell line just cannot see, but a
  # dependency it can -- and `prerelease: precommit` is the link that carries
  # the distribution suite onto the release path. Dropping either edge would
  # restore the blind spot without failing anything else here.
  run just_here --dump --dump-format json
  [ "$status" -eq 0 ]
  dump="$output"
  run jq -r '.recipes.precommit.dependencies[].recipe' <<<"$dump"
  [ "$status" -eq 0 ]
  [[ "$output" == *"check-distribution"* ]]
  run jq -r '.recipes.prerelease.dependencies[].recipe' <<<"$dump"
  [ "$status" -eq 0 ]
  [[ "$output" == *"precommit"* ]]
}

@test "precommit depends on check-size" {
  # The size cap is enforced at the gate. Match whole recipe names, one per
  # line, so a recipe named check-sizes or check-size-x cannot satisfy it.
  run just_here --dump --dump-format json
  [ "$status" -eq 0 ]
  run jq -r '.recipes.precommit.dependencies[].recipe' <<<"$output"
  [ "$status" -eq 0 ]
  grep -qxF check-size <<<"$output"
}

@test "every gate names its sentinel after its own recipe" {
  # The sentinel file is keyed by the name `sentinel-guard` is handed, so a
  # recipe naming another's would report that one's pass as its own. Recipe
  # names are distinct by construction; the check is that the name matches.
  run just_here --dump --dump-format json
  [ "$status" -eq 0 ]
  run jq -r '
    .recipes | to_entries[] | .key as $r | .value.body[]?
    | .[0]
    | select(type == "string" and startswith("sentinel-guard "))
    | [$r, .] | @tsv
  ' <<<"$output"
  [ "$status" -eq 0 ]
  tsv_lines="$output"
  [ -n "$tsv_lines" ]

  recipe_names=()
  while IFS=$'\t' read -r recipe guard_line || [ -n "$recipe" ]; do
    read -r _ guard_name _ <<<"$guard_line"
    [ "$recipe" = "$guard_name" ]
    recipe_names+=("$recipe")
  done <<<"$tsv_lines"

  for gate in lint test-unit test-integration check-distribution evals; do
    found=0
    for r in "${recipe_names[@]}"; do
      [ "$r" = "$gate" ] && found=1
    done
    [ "$found" -eq 1 ]
  done
}

@test "precommit and the gate recipes reach their runners" {
  # The invocation-path check: a green suite means nothing if `precommit`
  # stopped calling the gates, or a gate stopped running its tool before
  # recording success. `test` reaches the two suites as dependencies, which
  # just can check; `precommit` reaches `lint test` through a shell line.
  run just_here --dump --dump-format json
  [ "$status" -eq 0 ]
  dump="$output"

  run jq -r '.recipes.precommit.body[] | .[0] | select(type == "string")' <<<"$dump"
  [ "$status" -eq 0 ]
  precommit_body="$output"
  for token in check-version lint test; do
    [[ "$precommit_body" == *" $token"* ]]
  done

  run jq -r '.recipes.test.dependencies[].recipe' <<<"$dump"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-unit"* ]]
  [[ "$output" == *"test-integration"* ]]

  for gate in lint test-unit test-integration; do
    case "$gate" in
      lint) runner="tools/lint-shell.sh" ;;
      # The two bats gates reach theirs through the prolog's `run-suites`.
      *) runner="run-suites" ;;
    esac
    run jq -r --arg r "$gate" '.recipes[$r].body[] | .[0] | select(type == "string")' <<<"$dump"
    [ "$status" -eq 0 ]
    body="$output"
    [[ "$body" == *"$runner"* ]]
    after_runner="${body#*"$runner"}"
    [[ "$after_runner" == *"record-sentinel"* ]]
  done

  # `run-suites` is prolog text, which the dump above does not hold.
  run just_here --evaluate bash_prolog
  [ "$status" -eq 0 ]
  [[ "$output" == *"tools/run-bats-cached.sh"* ]]
}

# A literal `*.bats` glob in a suite's code is what iterating over sibling
# suites looks like; sourcing a suite's own helpers through
# `BATS_TEST_DIRNAME` is not. `bsd_portability` is the one that matches and is
# declared; this is the tripwire for the next one added without being.
@test "a suite that globs sibling .bats files for their contents is declared --reads-all" {
  run just_here --evaluate reads_all_suites
  [ "$status" -eq 0 ]
  declared=" $output "
  # The list is hand-written, so a name that no longer resolves would silently
  # declare nothing. The recipes would still run, on a key covering one suite
  # fewer than the declaration claims.
  for name in $output; do
    [ -f "$PLUGIN_ROOT/$name" ] || {
      echo "reads_all_suites names $name, which is not a suite" >&2
      return 1
    }
  done
  while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    hits="$(grep -n '\*\.bats' "$PLUGIN_ROOT/$suite" | grep -v '^[0-9]*:[[:blank:]]*#' || true)"
    [ -z "$hits" ] || [[ "$declared" == *" $suite "* ]] || {
      echo "$suite globs sibling .bats files but is not in reads_all_suites: $hits" >&2
      return 1
    }
  done < <(all_suites)
}

@test "the Makefile is gone, so nothing can quietly still run make" {
  # Paired with the runner that replaced it: if the build entry point moves
  # again, the positive reds rather than this absence quietly staying true of a
  # repo with no build system at all.
  [ -f "$PLUGIN_ROOT/justfile" ]
  [ ! -e "$PLUGIN_ROOT/Makefile" ]
  [ ! -e "$PLUGIN_ROOT/GNUmakefile" ]
  [ ! -e "$PLUGIN_ROOT/makefile" ]
}
