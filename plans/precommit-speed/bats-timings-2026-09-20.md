# Bats timings — 2026-09-20

One `bats --timing --jobs 2` pass per half, on the 2-vCPU dev box, with the
recipes' suite sets. Times are summed per-test durations, so wall time is about
half of each total. Both halves green.

| half | tests | summed test time |
|---|---|---|
| unit | 984 | 1136 s |
| integration | 72 | 77 s |

## Shape

The cost is spread, not concentrated. The fifteen heaviest unit suites hold 41%
of the time, and the heaviest single one, `tests/commit_memory_retry.bats`,
holds 7% (87 s over 8 tests, four of which carry a `sleep 1`).

Per test: p10 108 ms, p25 245 ms, median 637 ms, p75 1.4 s, p90 2.6 s. The 83
tests over 3 s hold 428 s (38%); the 194 under 200 ms hold 21 s.

## Heaviest unit suites

| summed | tests | avg | suite |
|---|---|---|---|
| 87.1 s | 8 | 10.9 s | `tests/commit_memory_retry.bats` |
| 39.6 s | 11 | 3.6 s | `tests/resolve_compose.bats` |
| 38.0 s | 12 | 3.2 s | `tests/cc_hook_index_compose_relay.bats` |
| 32.9 s | 27 | 1.2 s | `tests/tier_discovery.bats` |
| 29.5 s | 7 | 4.2 s | `tests/resolve_compose_continuation.bats` |
| 28.0 s | 6 | 4.7 s | `tests/git_hook_pre_commit_index.bats` |
| 26.1 s | 8 | 3.3 s | `tests/tier_divergence_continuation.bats` |
| 24.5 s | 7 | 3.5 s | `tests/commit_memory_reports.bats` |
| 24.4 s | 7 | 3.5 s | `tests/merge_memory_repair_arrivals.bats` |
| 24.4 s | 12 | 2.0 s | `tests/tier_divergence.bats` |

Integration: `tests/evals/lib/asserts.bats` is 39.7 s of the 77 s, and
`tests/integration_replay_guard.bats` 17.0 s.

## What it says about the two options

No suite is hot enough for a targeted `setup_file` rewrite to move the total:
rewriting the single heaviest saves at most 7%. The fixture every suite shares,
`setup_tmp_repo`, measures ~45 ms per test against 6 ms for a bare test — about
44 s of the 1136 s, 4%. The heavier store-and-tier fixtures are per-suite and
were not measured apart from the product work they set up: multi-store commits,
submodule mounts, merges. Per-suite gate sentinels attack the whole 1136 s at
once, for every edit that does not touch `scripts/`, `hooks/` or
`tests/helpers/`.

## Where a heavy test's time goes

Three suites run serially under `GIT_TRACE2_EVENT`. "Leaf git" is the time of
git processes that spawned nothing, so it holds no hook or shell time — the
floor no rewrite of the scripts removes.

| suite | wall | git processes | leaf git |
|---|---|---|---|
| `tests/resolve_compose.bats` | 44.5 s | 2502 | 10.6 s (24%) |
| `tests/tier_discovery.bats` | 30.3 s | 1917 | 6.8 s (22%) |
| `tests/commit_memory_reports.bats` | 12.9 s | 605 | 2.6 s (20%) |

About 230 git processes per test in the first, 865 of them `rev-parse` at 4.3 ms
each. What is not leaf git is shell: bash startup and library sourcing, `jq`,
`sed`, subshells, and bats' own per-test overhead; the split between those was
not measured.

The store fixture, `make_parent_with_memory`, is already built once per bats
run: a template under the run's temp directory, behind a build lock, copied per
test. The copy path measures ~0.4 s and has 373 call sites across 53 suites. By
phase: template lookup 37 ms, `cp -a` 18 ms, four path rewrites through
`_gitlore_sed_replace_path` 105 ms, the `git submodule status` sanity check 101
ms, `rev-parse` 14 ms. One `sed` process for the rewrites and dropping the
`submodule status` check — the `rev-parse HEAD` in the submodule beside it
already proves the gitdir link — would save ~170 ms a call, ~60 s of the 1136 s.
Fixture reuse has no larger headroom than that here.

The same phases put a fork at roughly 6 ms on this box (twelve `sed` forks and
four `mv` in 105 ms), which is what makes fork count, not git work, the dominant
cost.

## Inside the scripts

Startup on this box: `/bin/true` ~4 ms, `git --version` ~9 ms, `bash -c :` ~12
ms, bash sourcing `scripts/lib/util.sh` 14 ms, bash sourcing every
`scripts/lib/*.sh` ~136 ms, `python3` with `subprocess`/`json`/`re` imported
~147 ms. No entry script sources the whole library — five `source` lines at most
— so library loading is not a cost worth attacking, and a Python entry point
starts an order of magnitude slower than the bash one it would replace.

`tests/resolve_compose.bats`, every bash invocation logged: 11 tests, 54 s, of
which the product's scripts are ~34 s — `pre-commit` 12 calls at 1.2 s,
`pre-push` 9 at 1.2 s, `resolve.sh` 18 at 0.5 s — and the test bodies' own
fixture and divergence construction the other ~20 s.

One `pre-commit` run traced line by line (625 ms under xtrace, 800 lines): the
largest single item is the real work, `git push . HEAD:live` at 106 ms over
three calls. After it the time is diffuse — 23 `rev-parse` 144 ms, 16 `stat` 67
ms, 7 `rm` 29 ms, 17 `source` 21 ms, the rest builtins. There is no hot
function; the cost is a few hundred ~5 ms forks per script run.

## Fixture copy path, trimmed

`make_parent_with_memory`'s copy path, ten calls in one test after a warm-up:
380 ms a call before, 144 ms after — the path escapes computed once in bash
parameter expansion instead of two `sed` per file, no rewrite of a file that
does not carry the template path, and `git submodule status` replaced by a
`[ -s "$subpath/.git" ]` test. 236 ms over 373 call sites is ~88 s of the 1136 s
summed unit time, about 8%.

`git submodule status` exits 0 for a clean, an out-of-sync and an uninitialized
submodule alike, so it verified nothing; and `git -C "$subpath" rev-parse HEAD`
on a present-but-empty `$subpath` resolves the parent's HEAD. The gitlink test
catches both the missing and the empty case. `tests/fixture_template.bats` holds
the cover, each test shown to go red under a mutation of the behaviour it names.

## Batching `rev-parse`: measured, not worth it

A dispatched pass over `pre-commit` and `pre-push` found one batchable group:
the four `--git-path` replay markers in `scripts/git-hooks/pre-commit`, which
one `git rev-parse --git-path … --git-path …` answers. That takes a traced run
from 19 git processes to 16, ~15–25 ms, and moves no suite's wall time out of
run-to-run noise (2–4 s between two runs of unchanged code). The patch is kept
beside this file as `pre-commit-batched-markers.patch` and is not applied: a
positional array and a process substitution in place of a six-line loop, in a
hook that runs in users' commits, for a gain nothing can measure.

Nothing else qualified. The remaining `rev-parse` calls differ by store or name
a commit, and a same-process cache cannot work where it would matter:
`gitlore_commit_msg_file` and its siblings are called through command
substitution, so a value cached inside one is lost with its subshell. `pre-push`
has no hot-path `rev-parse` beyond `--local-env-vars`.

What the pass leaves behind is `tests/git_hook_pre_commit_replay.bats`: one test
per replay marker and one under a path holding a space, 1.5 s in all, each red
under a mutation that disables the replay stand-down.
