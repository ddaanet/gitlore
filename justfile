import 'plugin-dev/release.just'

# `evals` is opt-in: the 5-round grid drives the real claude CLI, costing time
# and money, so it stays out of the release gate. Run it when a change touches
# eval-covered behavior.
#
# `just release` depends on `prerelease`, which the vendored
# plugin-dev/release.just requires every consumer to define.

# Bash tracing (set -x) for every shebang recipe: `just trace=true precommit`.
trace := "false"

# Each gate's inputs, and nothing else.
#
# `memory/`, `docs/` and `plans/` are deliberately out: nothing the sentinel
# guards reads them, and memory is a gitlink, so including it re-ran the suite
# on every memory commit. The doc, memory and formatting checks run ahead of
# the sentinel instead, uncached. `.gitignore` is in: it decides which
# not-yet-added files the hash enumerates.
#
# Naming paths, rather than inferring the tree, also keeps the sandbox's
# phantom home dotfiles out of the hash.
#
# An allow-list narrows silently — `git ls-files` says nothing about a pathspec
# matching nothing, and a new top-level directory is never enumerated. The
# `justfile_gates` suite guards both: every declared path must exist, and every
# top-level entry must be declared here or in that suite's exclusion list.
#
# No path contains whitespace, so word-splitting the interpolation is intended.
precommit_inputs := ".claude-plugin .gitignore .gitlore .gitmodules hooks justfile plugin-dev reference scripts tests"

# The evals reach agents, commands and skills through the installed plugin.
# Those stay out of `precommit_inputs` because the full bats suite is 7m30s
# and a skill-prose edit must not pay it; `check-distribution` covers them in
# ~2s on the commit path, and so on the release path.
evals_inputs := precommit_inputs + " agents commands skills"

# Everything the distribution suite reads, so the gate is a pure function of
# its own inputs. The overlap with `precommit_inputs` (hooks/scripts/tests)
# costs a redundant 2s run and buys independence: narrowing `precommit_inputs`
# later cannot silently uncover this suite's assertions.
distribution_inputs := ".gitmodules agents commands hooks scripts skills tests/helpers tests/plugin_distribution.bats"

# Fast, frequent.
precommit: format-docs check-distribution
    #!{{ bash_prolog }}
    # Uncached, ahead of the sentinel: the checker's largest input is
    # `memory/`, a gitlink here, so `git ls-files` yields one path and nothing
    # to `cat` — no input hash can see a fact change, and a cached pass would
    # skip exactly the commit that edits a memory file. 0.4s, nothing to cache.
    scripts/check-memory-hygiene.py
    # Same placement, because `docs/` is out of `precommit_inputs`: a docs-only
    # commit moves no hash, and a cached pass would skip the graph check on
    # precisely the commit that rewires the graph.
    scripts/check-docs-links.py
    if check-sentinel precommit {{ precommit_inputs }}; then
        echo "precommit: cached (inputs unchanged)"
        exit 0
    fi
    just check-version lint test
    record-sentinel

# The shipped surface: that Claude Code can discover and dispatch what the
# plugin distributes. Its own gate and sentinel, because it reads the paths
# `precommit_inputs` leaves out — a skills/commands/agents-only edit moves no
# hash there, so `precommit` would report cached and never run these
# assertions. Cheap enough to hang off `precommit`, and so off `prerelease`:
# 10 tests, ~2s, no fixture repos.
#
# A separate recipe, not a block inside `precommit`: `check-sentinel` sets
# `sentinel` and `gate_inputs` for `record-sentinel`, so two gates in one
# shebang body would clobber each other's state.
check-distribution:
    #!{{ bash_prolog }}
    if check-sentinel distribution {{ distribution_inputs }}; then
        echo "check-distribution: cached (inputs unchanged)"
        exit 0
    fi
    scripts/run-bats.sh tests/plugin_distribution.bats
    record-sentinel

# Hard-wraps prose in docs/ and plans/ so a line count means something. No
# sentinel: a full pass is ~0.4s, less than the bookkeeping would cost. rumdl
# comes from uv.lock via `uv sync`, on PATH through `.envrc`; the pin check
# turns a stale `.venv` into a message instead of a differently wrapped tree.
format-docs:
    #!{{ bash_prolog }}
    have=$({{ rumdl }} --version) || { echo "format-docs: rumdl not on PATH — run 'uv sync' and let direnv load .envrc" >&2; exit 1; }
    want=$(sed -n 's/.*"rumdl==\([0-9.]*\)".*/\1/p' pyproject.toml)
    [ "$have" = "rumdl $want" ] || { echo "format-docs: $have on PATH, pyproject.toml pins $want — run 'uv sync'" >&2; exit 1; }
    {{ rumdl }} fmt --no-cache docs plans

# Overridable so a test can stand in a stub: `just rumdl=/path/to/stub format-docs`.
rumdl := "rumdl"

# Slow and paid: drives the real claude CLI. Run explicitly, never as a gate.
evals:
    #!{{ bash_prolog }}
    if check-sentinel evals {{ evals_inputs }}; then
        echo "evals: cached (inputs unchanged)"
        exit 0
    fi
    tests/evals/run-evals.sh
    record-sentinel

# Its own name so it can widen beyond precommit.
prerelease: precommit

# shellcheck over every tracked shell file, discovered by extension or shebang.
lint:
    scripts/lint-shell.sh

test: test-unit test-integration

test-unit:
    #!{{ bash_prolog }}
    # A glob, never a hand list: a list drifted once and orphaned five suites,
    # including the memory gate's.
    shopt -s nullglob
    suites=()
    for suite in tests/*.bats; do
        case "$suite" in tests/integration_*.bats) continue ;; esac
        suites+=("$suite")
    done
    [ "${#suites[@]}" -gt 0 ] || { echo "test-unit: no suites matched tests/*.bats" >&2; exit 1; }
    scripts/run-bats.sh --jobs "${GITLORE_TEST_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}" "${suites[@]}"

test-integration:
    #!{{ bash_prolog }}
    shopt -s nullglob
    suites=(tests/integration_*.bats tests/evals/lib/*.bats)
    [ "${#suites[@]}" -gt 0 ] || { echo "test-integration: no suites matched" >&2; exit 1; }
    scripts/run-bats.sh --jobs "${GITLORE_TEST_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}" "${suites[@]}"

# A gate is a pure function of its declared inputs, so re-running it over an
# untouched tree only reprints the last verdict — which makes `precommit`
# cheap to invoke repeatedly while working through a change.
[private]
bash_prolog := "/usr/bin/env bash\n" + \
    ( if trace == "true" { "set -xeuo pipefail" } \
    else { "set -euo pipefail" } ) + "\n" + '''
# Gate name, then input pathspecs. Sets `sentinel` and `gate_inputs` for
# `record-sentinel`.
#
# The sentinel lives under the gitdir, not the working tree: bookkeeping that
# showed up in `git status` — or in its own input hash — would invalidate the
# gate on every run.
check-sentinel () {
    sentinel_dir=$(git rev-parse --git-path gitlore/gates)
    mkdir -p "$sentinel_dir"
    sentinel="$sentinel_dir/$1"; shift
    gate_inputs=("$@")
    [ -z "${GITLORE_GATE_FORCE:-}" ] || return 1
    [ -f "$sentinel" ] || return 1
    recorded=$(cat "$sentinel")
    current=$(gate-inputs-hash) || return 1
    [ "$recorded" = "$current" ]
}

# Run after the checks, never before. A hash
# that cannot be computed leaves no sentinel: a partial hash would match itself
# on the next run if the failure is deterministic, skipping a tree nothing
# checked. Say so loudly; a cache that quietly stopped caching is the failure
# nobody hears about.
record-sentinel () {
    if hash=$(gate-inputs-hash); then
        printf '%s\n' "$hash" > "$sentinel"
    else
        rm -f "$sentinel"
        echo "gate: could not hash inputs; the pass was NOT recorded" >&2
    fi
}

# Names as well as contents, so a rename or deletion counts; tool versions
# because this repo does not pin them; `--others --exclude-standard` so a
# brand-new suite is hashed before it is added — when a stale pass hurts most —
# while ignored files stay out.
#
# Every component fails explicitly rather than leaning on errexit: this runs in
# a command substitution inside a condition, where bash suspends errexit, so an
# unguarded `bats --version` that died would drop out of the stream and the
# gate would keep caching against a hash that no longer covers it.
gate-inputs-hash () {
    {
        # The group heads a pipeline, so it is a subshell: `exit` fails the
        # pipeline and pipefail carries that to the caller.
        bats --version || exit 1
        shellcheck --version || exit 1
        jq --version || exit 1
        # For `scripts/hook-manager/wire-*.sh`, whose python3/PyYAML probe
        # decides what the hook-manager wiring suite asserts under the cached
        # `test` gate; with `.venv/bin` on PATH this is the venv's python.
        # The hygiene checker runs uncached and needs no entry.
        python3 --version || exit 1
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
