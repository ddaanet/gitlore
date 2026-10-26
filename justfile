import 'plugin-dev/release.just'
import 'plugin-dev/gates.just'

# `evals` is opt-in: the 5-round grid drives the real claude CLI, costing time
# and money, so it stays out of the release gate. Run it when a change touches
# eval-covered behavior.
#
# `just release` depends on `prerelease`, which the vendored
# plugin-dev/release.just requires every consumer to define.

# Bash tracing (set -x) for every shebang recipe: `just trace=true precommit`.
trace := "false"

# Tool versions folded into every gate's hash, because this repo does not pin
# them. `python3` is for `scripts/hook-manager/wire-*.sh`, whose python3/PyYAML
# probe decides what the hook-manager wiring suite asserts under the cached
# `test` gate; with `.venv/bin` on PATH this is the venv's python. The hygiene
# checker runs uncached and needs no entry.
export PLUGIN_DEV_GATE_TOOLS := "bats --version\nshellcheck --version\njq --version\npython3 --version"

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
precommit_inputs := ".claude-plugin .gitignore .gitlore .gitmodules hooks justfile plugin-dev reference scripts tests tools"

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

# Suites that read other suites' contents — one that greps or sources a
# sibling `.bats` file, rather than merely listing names. Its per-suite key in
# `run-bats-cached.sh` has to cover every suite, not only itself, so a cached
# pass is not held across an edit it would have caught. `bsd_portability`
# sweeps the tree for GNU-only `stat` spellings, which live in test bodies as
# readily as in scripts. The `justfile_gates` suite fails when a suite starts
# globbing siblings without being named here.
reads_all_suites := "tests/bsd_portability.bats"

# Fast, frequent. `lint`, `test-unit` and `test-integration` each guard their
# own sentinel, so a red integration run does not un-cache a green lint;
# `check-version` stays uncached beside the two doc checks below — cheap, and
# it reads the version files fresh every time.
precommit: format-docs check-distribution check-refs
    #!{{ bash_prolog }}
    # Uncached, ahead of the gates: the checker's largest input is
    # `memory/`, a gitlink here, so `git ls-files` yields one path and nothing
    # to `cat` — no input hash can see a fact change, and a cached pass would
    # skip exactly the commit that edits a memory file. 0.4s, nothing to cache.
    tools/check-memory-hygiene.py
    # Same placement, because `docs/` is out of `precommit_inputs`: a docs-only
    # commit moves no hash, and a cached pass would skip the graph check on
    # precisely the commit that rewires the graph.
    tools/check-docs-links.py
    just check-version lint test

# The shipped surface: that Claude Code can discover and dispatch what the
# plugin distributes. Its own gate and sentinel, because it reads the paths
# `precommit_inputs` leaves out — a skills/commands/agents-only edit moves no
# hash there, so `precommit` would report cached and never run these
# assertions. Cheap enough to hang off `precommit`, and so off `prerelease`:
# 10 tests, ~2s, no fixture repos.
#
# A separate recipe, not a block inside `precommit`: `check-sentinel` sets
# `sentinel` and `gate_inputs` for `record-sentinel`, so two gates in one
# shebang body would clobber each other's state, and the prolog refuses it.
check-distribution:
    #!{{ bash_prolog }}
    sentinel-guard check-distribution {{ distribution_inputs }}
    plugin-dev/run-bats.sh tests/plugin_distribution.bats
    record-sentinel

# Hard-wraps prose in docs/ and plans/ so a line count means something. No
# sentinel: a full pass is ~0.4s, less than the bookkeeping would cost. rumdl
# comes from uv.lock via `uv sync`, on PATH through `.envrc`; the pin check
# turns a stale `.venv` into a message instead of a differently wrapped tree.
#
# `plans/*/reports/` is out: a report is a record of a run that has finished,
# so wrapping it rewrites a file its author is no longer there to read, and it
# escapes no check by staying unwrapped — the line cap `check-docs-links.py`
# enforces covers `docs/` only.
format-docs:
    #!{{ bash_prolog }}
    have=$({{ rumdl }} --version) || { echo "format-docs: rumdl not on PATH — run 'uv sync' and let direnv load .envrc" >&2; exit 1; }
    want=$(sed -n 's/.*"rumdl==\([0-9.]*\)".*/\1/p' pyproject.toml)
    [ "$have" = "rumdl $want" ] || { echo "format-docs: $have on PATH, pyproject.toml pins $want — run 'uv sync'" >&2; exit 1; }
    # rumdl reprints every line it could not rewrap — MD013 residue in
    # agent-written reports, ~70 lines identical on every run, drowning the
    # rest of `precommit`. Only its own summary line survives a clean exit; a
    # real failure (rc 2 — bad path, bad config) still prints in full, so
    # nothing that would change the outcome is filtered.
    out=$({{ rumdl }} fmt --no-cache --exclude 'plans/*/reports' docs plans 2>&1) && rc=0 || rc=$?
    if [ "$rc" -ne 0 ]; then
        [ -n "$out" ] && printf '%s\n' "$out" >&2
        exit "$rc"
    fi
    [ -n "$out" ] && printf '%s\n' "$out" | tail -n 1
    exit 0

# Overridable so a test can stand in a stub: `just rumdl=/path/to/stub format-docs`.
rumdl := "rumdl"

# Slow and paid: drives the real claude CLI. Run explicitly, never as a gate.
evals:
    #!{{ bash_prolog }}
    sentinel-guard evals {{ evals_inputs }}
    tests/evals/run-evals.sh
    record-sentinel

# Its own name so it can widen beyond precommit.
prerelease: precommit

# The three runners below are gates: each guards its own sentinel over
# `precommit_inputs` and records its own pass, so `precommit` reports them
# independently and a cached one costs nothing. `PLUGIN_DEV_GATE_FORCE=1` runs
# one regardless. Never two guards in one shebang body: `check-sentinel` sets
# the shell variables `sentinel` and `gate_inputs` that `record-sentinel`
# reads back, so the prolog refuses a second gate in the same script.
#
# All three start from `precommit_inputs`: `tools/lint-shell.sh` discovers
# every shell file under them, and both bats halves source `scripts/` and
# `hooks/`. `test-unit` narrows from there, since it runs none of the
# integration suites.

# shellcheck over every shell file the gate hash counts — tracked, or untracked
# and not ignored — discovered by extension or shebang.
#
# `lint-shell.sh` walks the whole tree, so the hash widens to the shell files
# under `plans/`: left out, the commit that edits one reports a cached pass.
# By extension only — a plan's prose must not cost a lint run, so an
# extensionless script under `plans/` is linted but never moves the hash.
# `.sh` only, because the guard refuses a pathspec that matches no file and no
# plan carries a `.bash` or `.bats` file; the first one added wants its
# extension named here.
lint:
    #!{{ bash_prolog }}
    sentinel-guard lint {{ precommit_inputs }} 'plans/*.sh'
    tools/lint-shell.sh
    record-sentinel

test: test-unit test-integration

test-unit:
    #!{{ bash_prolog }}
    # The integration suites are subtracted from the shared set: this recipe
    # never runs one, so editing one must not send the unit half through a
    # re-run. A git exclude pathspec, quoted — the interpolation beside it is
    # word-split on purpose, and an unquoted pathspec would reach the shell's
    # own globbing on the way past.
    sentinel-guard test-unit {{ precommit_inputs }} ':(exclude)tests/integration_*'
    # A glob, never a hand list: a list drifted once and orphaned five suites,
    # including the memory gate's.
    shopt -s nullglob
    suites=()
    for suite in tests/*.bats; do
        case "$suite" in tests/integration_*.bats) continue ;; esac
        suites+=("$suite")
    done
    [ "${#suites[@]}" -gt 0 ] || { echo "test-unit: no suites matched tests/*.bats" >&2; exit 1; }
    run-suites test-unit {{ reads_all_suites }} -- "${suites[@]}"
    record-sentinel

test-integration:
    #!{{ bash_prolog }}
    sentinel-guard test-integration {{ precommit_inputs }}
    shopt -s nullglob
    suites=(tests/integration_*.bats tests/evals/lib/*.bats)
    [ "${#suites[@]}" -gt 0 ] || { echo "test-integration: no suites matched" >&2; exit 1; }
    run-suites test-integration {{ reads_all_suites }} -- "${suites[@]}"
    record-sentinel

# A gate is a pure function of its declared inputs, so re-running it over an
# untouched tree only reprints the last verdict — which makes `precommit`
# cheap to invoke repeatedly while working through a change.
#
# The sentinel functions — `sentinel-guard`, `check-sentinel`,
# `record-sentinel`, `gate-inputs-hash` — are the toolkit's, from
# `plugin-dev/gates.just`; `run-suites` below is gitlore's own, layered on
# them. The toolkit's prolog opens with its own `set -euo pipefail`, so
# `trace=true` only adds `set -x`.
[private]
bash_prolog := plugin_dev_gate_prolog + \
    ( if trace == "true" { "set -x\n" } else { "" } ) + '''
# Gate name, the suites that read other suites' contents, `--`, the suites.
# Between a gate's guard and its record: the whole-tree sentinel skips an
# untouched tree, and beneath it `run-bats-cached.sh` keeps one key per suite,
# so an edit under `tests/` reruns the suites it touched. The shared hash it is
# handed leaves the suite files out — each is its own suite's key component —
# and is taken in a subshell, so `gate_inputs` stays what `check-sentinel` set
# for `record-sentinel`. Empty means unhashable: everything runs, and no suite
# is recorded.
run-suites () {
    local gate="$1" shared_hash reads_all=()
    shift
    while [ "$1" != "--" ]; do
        reads_all+=(--reads-all "$1")
        shift
    done
    shift
    shared_hash=$(gate_inputs=("${gate_inputs[@]}" ':(exclude)tests/*.bats' ':(exclude)tests/evals/lib/*.bats'); gate-inputs-hash) || shared_hash=""
    # `${a[@]+…}`: an empty array is unbound to `set -u` before bash 4.4.
    tools/run-bats-cached.sh "$sentinel_dir/$gate.suites" "$shared_hash" \
        ${reads_all[@]+"${reads_all[@]}"} \
        -- --jobs "${GITLORE_TEST_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}" "$@"
}

'''
