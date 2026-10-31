#!/usr/bin/env bats
# What each gate's declared input set covers, in this repo: the `*_inputs`
# variables and the pathspecs the recipes build from them. Split from
# justfile_gates.bats, which guards the recipes and their sentinels; these
# guard what those recipes are told to hash. A gate whose declaration drifts
# reports cached on a commit it never looked at, which no recipe-level
# assertion can see.

# `run` here takes flags (`!`), which bats honours only once the suite declares
# the version that introduced them.
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/justfile-gates

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
  [[ "$output" == *"tools/run-bats-cached.sh"* ]]

  run guard_input_files test-integration
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/integration_"* ]]

  run guard_input_files lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/integration_"* ]]
}

@test "each gate's inputs cover the files its suites read outside tests/" {
  # A file a suite reads but its gate does not hash leaves the gate cached on a
  # commit that changes only that file: plugin_bin.bats checks dist.include,
  # commit_skill_template.bats and evals/lib/setup.bats read the commit skill,
  # and plugin_distribution.bats compares .gitlore/bin/claude.
  run guard_input_files test-unit
  [ "$status" -eq 0 ]
  grep -qxF dist.include <<<"$output"
  grep -qxF skills/commit/SKILL.md <<<"$output"

  run guard_input_files test-integration
  [ "$status" -eq 0 ]
  grep -qxF skills/commit/SKILL.md <<<"$output"

  run guard_input_files check-distribution
  [ "$status" -eq 0 ]
  grep -qxF .gitlore/bin/claude <<<"$output"
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
  # The complement of the superset test above: the declaration is an allow-list, so a new
  # top-level directory holding scripts or fixtures is invisible to the hash
  # until someone names it here. Checked against the wider set — a path may be
  # deliberately absent from precommit's, but absent from both means no gate
  # sees it at all.
  run just_here --evaluate evals_inputs
  [ "$status" -eq 0 ]
  declared=" $output "
  # Excluded on purpose: no check reads them, and including them would re-run
  # the whole suite on a memory-only or prose-only commit. `docs`, `plans` and
  # the rumdl pin/config are read by `format-docs`, which has no sentinel;
  # `TASK.md` and `TODO.md` are the handoff task frame, like `.claude`; the
  # shell scripts under `plans` reach the `lint` gate by pathspec instead.
  excluded=" memory docs plans inbox README.md CLAUDE.md TASK.md TODO.md .claude .editorconfig .envrc pyproject.toml uv.lock .rumdl.toml "
  while IFS= read -r entry; do
    [[ "$declared" == *" $entry "* ]] || [[ "$excluded" == *" $entry "* ]] || {
      echo "top-level entry '$entry' is neither a declared gate input nor a deliberate exclusion" >&2
      return 1
    }
  done < <(git -C "$PLUGIN_ROOT" ls-files | sed 's#/.*##' | sort -u)
}

