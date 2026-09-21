#!/usr/bin/env bats
# Guards on this repo's own `justfile`, which is the only place the gates are
# defined now that the Makefile is gone. Like plugin_distribution.bats, these
# inspect gitlore's real files rather than a fixture: the failure they exist to
# catch is a suite that no longer runs, and a fixture cannot show that.

load helpers/setup
load helpers/justfile-gates

# A gate's `sentinel-guard` line as its shell receives it, rebuilt from just's
# own dump so the assertion reads the shipped recipe rather than a copy of it.
# Body segments come back as literal strings and as interpolations naming a
# variable; `just --evaluate` supplies the latter. No segment here spans a
# newline, which is what lets the two kinds travel as one line each.
guard_line() {
  local segments seg rendered=""
  segments=$(
    just_here --dump --dump-format json | jq -r --arg r "$1" '
      .recipes[$r].body[]
      | select((.[0] | type) == "string" and (.[0] | startswith("sentinel-guard ")))
      | .[]
      | if type == "string" then "L" + .
        # An interpolation is `["variable", name]` up to just 1.45 and
        # `[["variable", name]]` from 1.46.
        elif (.[0] | type) == "array" then "V" + .[0][1]
        else "V" + .[1] end
    '
  ) || return 1
  while IFS= read -r seg || [ -n "$seg" ]; do
    case "$seg" in
      L*) rendered="$rendered${seg#L}" ;;
      # A name that does not evaluate would render as nothing, and a guard line
      # with no pathspec enumerates the whole tree — every assertion on it
      # would then pass or fail for the wrong reason.
      V*) rendered="$rendered$(just_here --evaluate "${seg#V}")" || return 1 ;;
    esac
  done <<< "$segments"
  printf '%s\n' "$rendered"
}

# The paths a gate's declared inputs actually enumerate, in this repo.
guard_input_files() {
  local line
  line=$(guard_line "$1") || return 1
  # The recipe's own quoting decides the word boundaries, so the shell that
  # splits them has to be the shell — the gate's arguments carry an exclude
  # pathspec whose parentheses and glob are protected by quotes in the justfile.
  eval "set -- $line"
  shift 2
  git -C "$PLUGIN_ROOT" ls-files --cached --others --exclude-standard -- "$@"
}

# Every .bats file the repo has, tracked or merely written — the same set the
# recipes' globs see, so a brand-new suite counts before it is added.
all_suites() {
  git -C "$PLUGIN_ROOT" ls-files --cached --others --exclude-standard -- tests \
    | grep '\.bats$' \
    | sort
}

# What `just test` would hand to bats, with bats stubbed out. Filtered to
# *.bats lines: the recipes also pass `--jobs <n>`, which the stub echoes
# like any other arg but which isn't a suite. Forced, because the runners are
# gates: a recorded pass would skip discovery and hand back nothing. The
# sentinels go to a scratch directory: this runs the real recipes in the real
# repo, and a stubbed pass recorded there would overwrite the verdicts of the
# very gate this suite is running under. `2>&1` ahead of the filter: the stub
# writes no junit report, `run-bats-cached.sh` says so on stderr, and bats'
# `run` would fold that line into `$output` beside the suite names.
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
printf '%s\n' "$@"
EOF
  chmod +x "$stub_dir/bats"
  printf '%s\n' "$stub_dir" > "$BATS_FILE_TMPDIR/discovered_suites.stub_dir"

  if ( cd "$PLUGIN_ROOT" && PATH="$stub_dir:$PATH" GITLORE_GATE_FORCE=1 GITLORE_GATE_DIR="$stub_dir/gates" just test-unit test-integration ) \
      > "$BATS_FILE_TMPDIR/discovered_suites.raw" 2>&1
  then status=0
  else status=$?
  fi
  printf '%s\n' "$status" > "$BATS_FILE_TMPDIR/discovered_suites.status"
  grep '\.bats$' "$BATS_FILE_TMPDIR/discovered_suites.raw" > "$BATS_FILE_TMPDIR/discovered_suites.out" || true
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

@test "GITLORE_GATE_DIR moves the sentinel out of the gitdir" {
  setup_gate_repo
  run in_gate_repo "export GITLORE_GATE_DIR='$GATE_REPO/elsewhere'; check-sentinel g src || true; record-sentinel"
  [ "$status" -eq 0 ]
  [ -f "$GATE_REPO/elsewhere/g" ]
  [ ! -e "$GATE_REPO/.git/gitlore/gates/g" ]

  run in_gate_repo "export GITLORE_GATE_DIR='$GATE_REPO/elsewhere'; sentinel-guard g src; echo ran"
  [ "$status" -eq 0 ]
  [ "$output" = "g: cached (inputs unchanged)" ]
}

@test "every suite under tests/ is run by one of the test recipes" {
  # The regression this exists for: `make test` once hand-listed its suites and
  # five of them (21 tests) drifted off the list, including the FR11 memory-gate
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
  # except check-distribution's, which names one suite on purpose: it gates a
  # fixed set of assertions rather than a discovered set. That name cannot
  # drift silently, because `distribution_inputs` declares the same path and
  # the declared-inputs test below fails the moment it stops existing.
  literals="$(grep -n '[A-Za-z_]\.bats' "$PLUGIN_ROOT/justfile" || true)"
  stray="$(printf '%s\n' "$literals" | grep -v 'tests/plugin_distribution\.bats' || true)"
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

@test "sentinel-guard skips only when the gate's inputs are unchanged, and GITLORE_GATE_FORCE overrides it" {
  setup_gate_repo
  run in_gate_repo "sentinel-guard g src; echo ran"
  [ "$status" -eq 0 ]
  [ "$output" = ran ]

  gate_record src
  run in_gate_repo "sentinel-guard g src; echo ran"
  [ "$status" -eq 0 ]
  [ "$output" = "g: cached (inputs unchanged)" ]

  run env GITLORE_GATE_FORCE=1 bash -c \
    "cd '$GATE_REPO' && . '$PROLOG' && sentinel-guard g src; echo ran"
  [ "$status" -eq 0 ]
  [ "$output" = ran ]
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
      lint) runner="scripts/lint-shell.sh" ;;
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
  [[ "$output" == *"scripts/run-bats-cached.sh"* ]]
}

# A literal `*.bats` glob in a suite's code is what iterating over sibling
# suites looks like; sourcing a suite's own helpers through
# `BATS_TEST_DIRNAME` is not. No suite matches, so `reads_all_suites` is empty
# and this is a tripwire for one added without being declared.
@test "a suite that globs sibling .bats files for their contents is declared --reads-all" {
  run just_here --evaluate reads_all_suites
  [ "$status" -eq 0 ]
  declared=" $output "
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

@test "every declared gate input exists in the repo" {
  # An input path that no longer exists contributes nothing to the hash and says
  # nothing about it: `git ls-files` does not complain about a pathspec that
  # matches nothing, so a stale entry here silently narrows what the gate covers.
  for var in precommit_inputs evals_inputs distribution_inputs; do
    run just_here --evaluate "$var"
    [ "$status" -eq 0 ]
    for path in $output; do
      [ -e "$PLUGIN_ROOT/$path" ]
    done
  done
}

@test "the unit gate's inputs leave the integration suites out, the integration gate's keep them" {
  # The two halves share `precommit_inputs`, so without the narrowing an edit to
  # an integration suite re-runs the unit half for nothing. Asserted on the
  # files the declared inputs enumerate, not on the declaration's text: a
  # pathspec that stopped excluding would still read correctly.
  run guard_input_files test-unit
  [ "$status" -eq 0 ]
  [[ "$output" != *"tests/integration_"* ]]
  # The narrowing must take only the integration suites with it.
  [[ "$output" == *"tests/justfile_gates.bats"* ]]
  [[ "$output" == *"scripts/run-bats.sh"* ]]

  run guard_input_files test-integration
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/integration_"* ]]

  run guard_input_files lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/integration_"* ]]
}

@test "the lint gate's inputs cover the shell scripts under plans/, and only those" {
  # `lint-shell.sh` discovers every tracked shell file, `plans/` included, but a
  # gate whose hash leaves them out reports cached on the commit that edits one.
  # The plans' prose stays out: a plan edit must not cost a lint run, and the
  # bats gates read nothing under `plans/` at all.
  run guard_input_files lint
  [ "$status" -eq 0 ]
  lint_files="$output"
  planned=$(git -C "$PLUGIN_ROOT" ls-files -- 'plans/*.sh' 'plans/*.bash')
  [ -n "$planned" ]
  while IFS= read -r f; do
    grep -Fxq -- "$f" <<< "$lint_files"
  done <<< "$planned"
  run ! grep -E '^plans/.*\.md$' <<< "$lint_files"

  run guard_input_files test-unit
  [ "$status" -eq 0 ]
  run ! grep '^plans/' <<< "$output"
}

@test "the evals input set is a superset of precommit's, and adds the shipped plugin content" {
  # The two sets exist because the evals drive the real CLI against the
  # installed plugin: an edit to what the plugin ships must invalidate them.
  # Nothing the precommit gate reads may be missing from the wider set, or a
  # green evals run would be resting on a tree its own checks never saw.
  run just_here --evaluate precommit_inputs
  [ "$status" -eq 0 ]
  narrow="$output"
  run just_here --evaluate evals_inputs
  [ "$status" -eq 0 ]
  wide=" $output "
  for path in $narrow; do
    [[ "$wide" == *" $path "* ]]
  done
  for path in agents commands skills; do
    [[ "$wide" == *" $path "* ]]
    [[ " $narrow " != *" $path "* ]]
  done
}

@test "every top-level entry is either a gate input or a deliberate exclusion" {
  # The complement of the test above: the declaration is an allow-list, so a new
  # top-level directory holding scripts or fixtures is invisible to the hash
  # until someone names it here. Checked against the wider set — a path may be
  # deliberately absent from precommit's, but absent from both means no gate
  # sees it at all.
  run just_here --evaluate evals_inputs
  [ "$status" -eq 0 ]
  declared=" $output "
  # Excluded on purpose: no check reads them, and including them would re-run
  # the whole suite on a memory-only or prose-only commit. `docs`, `plans` and
  # the rumdl pin/config are read by `format-docs`, which has no sentinel; the
  # shell scripts under `plans` reach the `lint` gate by pathspec instead.
  excluded=" memory docs plans inbox README.md CLAUDE.md .claude .editorconfig .envrc pyproject.toml uv.lock .rumdl.toml "
  while IFS= read -r entry; do
    [[ "$declared" == *" $entry "* ]] || [[ "$excluded" == *" $entry "* ]] || {
      echo "top-level entry '$entry' is neither a declared gate input nor a deliberate exclusion" >&2
      return 1
    }
  done < <(git -C "$PLUGIN_ROOT" ls-files | sed 's#/.*##' | sort -u)
}

