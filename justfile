import 'plugin-dev/release.just'

# `evals` is a separate, opt-in recipe: the 5-round eval grid drives the real
# claude CLI, so it costs real time and money and doesn't belong in the
# default release gate. Run it explicitly when a change touches eval-covered
# behavior.
#
# `just release` depends on `prerelease` (that dependency lives in the vendored
# plugin-dev/release.just, which requires every consumer to define the recipe).

# Enable bash tracing (set -x) for every shebang recipe. Usage:
# just trace=true precommit
trace := "false"

# What a gate outcome depends on, and nothing else. Two sets, because the two
# gates read different things.
#
# `memory/` and `docs/` are out of both, deliberately: no check reads either,
# and memory is staged as a gitlink, so including it re-ran the whole suite on
# every memory commit. `.gitignore` is in, since it decides which not-yet-added
# files the hash enumerates at all.
#
# Naming paths rather than inferring the tree is also what keeps the phantom
# home dotfiles the sandbox surfaces in the working directory out of the hash.
#
# The declaration is an allow-list, so it narrows silently in two ways — a
# pathspec matching nothing draws no complaint from `git ls-files`, and a new
# top-level directory is simply never enumerated. The `justfile_gates` suite
# guards both directions: every declared path must exist, and every top-level
# entry must be declared here or named in that suite's exclusion list.
#
# The paths contain no whitespace, so the shell's word splitting of these
# interpolations is the intended reading.
precommit_inputs := ".claude-plugin .gitignore .gitlore .gitmodules hooks justfile plugin-dev scripts tests"

# The evals drive the real CLI against the installed plugin, so they also
# depend on what the plugin ships: its agents, commands and skills. The bats
# suites read those directories too (`plugin_distribution` asserts on all
# three; `cc_hook_recall` on skills, `cc_hook_add_tier` on commands), so
# leaving them out of the precommit set is a deliberate trade — an
# agents/commands/skills-only edit keeps a green precommit green, and the
# distribution guard covering it does not re-run until the evals do.
evals_inputs := precommit_inputs + " agents commands skills"

# Fast, frequent. Version drift, shellcheck, then the full bats suite.
precommit:
    #!{{ bash_prolog }}
    if check-sentinel precommit {{ precommit_inputs }}; then
        echo "precommit: cached (inputs unchanged)"
        exit 0
    fi
    just check-version lint test
    record-sentinel

# Slow, rare. Drives the real claude CLI, so it costs time and money. Run
# explicitly, not part of the default release gate.
evals:
    #!{{ bash_prolog }}
    if check-sentinel evals {{ evals_inputs }}; then
        echo "evals: cached (inputs unchanged)"
        exit 0
    fi
    tests/evals/run-evals.sh
    record-sentinel

# The pre-release gate. Same as precommit; kept as its own name for
# `release`'s dependency and for the option to widen it later.
prerelease: precommit

# shellcheck over every tracked shell file, discovered by extension or shebang.
lint:
    scripts/lint-shell.sh

test: test-unit test-integration

# The suites are discovered by glob, never hand-listed: an explicit list drifted
# once and orphaned five suites, including the one covering the memory gate.
test-unit:
    #!{{ bash_prolog }}
    shopt -s nullglob
    suites=()
    for suite in tests/*.bats; do
        case "$suite" in tests/integration_*.bats) continue ;; esac
        suites+=("$suite")
    done
    [ "${#suites[@]}" -gt 0 ] || { echo "test-unit: no suites matched tests/*.bats" >&2; exit 1; }
    bats "${suites[@]}"

test-integration:
    #!{{ bash_prolog }}
    shopt -s nullglob
    suites=(tests/integration_*.bats tests/evals/lib/*.bats)
    [ "${#suites[@]}" -gt 0 ] || { echo "test-integration: no suites matched" >&2; exit 1; }
    bats "${suites[@]}"

# Bash prolog: the shebang line every recipe above uses, plus the gate-sentinel
# helpers. A gate is a pure function of its declared inputs, so re-running it
# over an untouched tree can only reprint the verdict it printed last time —
# and `precommit` is cheap to invoke twice while working through a change.
[private]
bash_prolog := "/usr/bin/env bash\n" + \
    ( if trace == "true" { "set -xeuo pipefail" } \
    else { "set -euo pipefail" } ) + "\n" + '''
# Decide whether a gated recipe can skip its work, and say where it should
# record having passed. Takes the gate name then its input pathspecs; sets
# `sentinel` and `gate_inputs` for `record-sentinel`, and returns 0 only when
# the hash recorded on the last pass still matches.
#
# The sentinel lives under the gitdir, never in the working tree: a gate whose
# own bookkeeping showed up in `git status` — or in its own input hash — would
# invalidate itself on every run.
check-sentinel () {
    sentinel_dir=$(git rev-parse --git-path gitlore/gates)
    mkdir -p "$sentinel_dir"
    sentinel="$sentinel_dir/$1"; shift
    gate_inputs=("$@")
    # Escape hatch for forcing a run over an unchanged tree.
    [ -z "${GITLORE_GATE_FORCE:-}" ] || return 1
    [ -f "$sentinel" ] || return 1
    recorded=$(cat "$sentinel")
    current=$(gate-inputs-hash) || return 1
    [ "$recorded" = "$current" ]
}

# Record a pass, and only a pass — callers run this after the checks, never
# before. A hash that cannot be computed leaves no sentinel at all: a partial
# one is a hash of a partial input set, and if the failure is deterministic the
# next run matches it and skips a tree nothing ever checked. Say so out loud;
# a cache that has quietly stopped caching is exactly the failure nobody is
# told about.
record-sentinel () {
    if hash=$(gate-inputs-hash); then
        printf '%s\n' "$hash" > "$sentinel"
    else
        rm -f "$sentinel"
        echo "gate: could not hash inputs; the pass was NOT recorded" >&2
    fi
}

# Everything a gate outcome can depend on: the versions of the tools this repo
# does not pin, and the declared inputs' names alongside their contents — names
# too, so a rename or a deletion counts as a change. `--others
# --exclude-standard` picks up files not yet added to git, since a brand-new
# test suite is exactly when a stale cached pass would hurt most, while still
# leaving ignored files out.
#
# Every component fails the hash explicitly rather than leaning on errexit:
# this runs inside a command substitution in a condition, where bash suspends
# errexit outright, so an unguarded `bats --version` that died would simply
# drop out of the stream and the gate would go on caching against a hash that
# no longer covers it.
gate-inputs-hash () {
    {
        # The group is a subshell (it heads a pipeline), so `exit` here fails
        # the pipeline, and pipefail carries that out to the caller.
        bats --version || exit 1
        shellcheck --version || exit 1
        jq --version || exit 1
        git ls-files -z --cached --others --exclude-standard -- "${gate_inputs[@]}" \
            | sort -z \
            | while IFS= read -r -d '' file; do
                  printf '%s\n' "$file"
                  # `if`, not `&&`: a non-regular path would otherwise make the
                  # loop body — and so the whole pipeline — report failure.
                  if [ -f "$file" ]; then cat -- "$file"; fi
              done || exit 1
    } | cksum
}
'''
