# Testing — the two tiers and the gate's cost

The detail behind `design.md`'s NFR9 and NFR10: what each test tier can see,
which is what decides where a case goes, and what the commit gate costs today.
No decision is argued here; the eval harness's own practice is in the four
`evals-*.md` nodes.

---

## Two tiers, split by what each can see (NFR9)

The bats suites (`tests/*.bats`) own the edge cases and every script's contract,
called the way production calls it. The eval harness (`tests/evals/`) owns the
**happy paths**, driven through the real agent, because the seam between the
agent and the shell is invisible to bats: no assertion can drive "a session
starts, the agent edits memory, the user approves, the commit lands," and a
prompt has no assertion-level test at all. Scenarios stay in the `pass^k` shape
the harness already uses, so an agent-side flake stays distinguishable from a
regression. Edge cases do not go in an eval; an eval's value is proving the
whole chain fits together.

The bats tier assumes bash >= 4.1, where a failing `[[ ]]` anywhere in a test
body fails the test; under the bash 3.2 macOS ships, only the final command's
status is read and every non-final assertion passes silently. A macOS run
therefore drives bats with a modern bash, and the BSD behaviour the system tools
would have contributed comes from the stubs `tests/bsd_portability.bats`
installs instead.

## The gate's cost (NFR10)

`just precommit` — `format-docs`, `check-distribution`, then `check-version`,
`lint`, `test-unit` and `test-integration`, each of the last three behind its
own sentinel — runs 530 s over 620 cases (measured 2026-07-29 on the 2-vCPU dev
droplet, `--jobs 2`; `check-distribution` adds ~2 s and carries its own
sentinel, so a change confined to `agents/`, `commands/` or `skills/` pays only
that). `user + sys` came to 566 s against 530 s wall, so the suite is barely
parallel and more cores would not divide the number. Making it faster is open
work, and cutting per-case work is the lever, not raising `--jobs`. `bats -T`
reports per-test timings, so the breakdown that would direct that work comes
free on the next full run. The input-hash sentinel caches a green result, so the
full cost is paid precisely when a change is in flight.

`format-docs` hard-wraps `docs/` and `plans/` apart from `plans/*/reports/`. A
report records a run that has finished, so wrapping it rewrites a file its
author is no longer there to read, and nothing is lost by leaving it: the
`oversized-file` cap `check-docs-links.py` enforces covers `docs/` only.

## What a sentinel vouches for

`lint`, `test-unit`, `test-integration` and `check-distribution` each write one
file under `git rev-parse --git-path gitlore/gates`, which resolves per
worktree, so a linked worktree keeps verdicts of its own. The file holds a
`cksum` over that recipe's declared inputs — each path's name and contents, plus
the versions of the unpinned tools the run leans on — and a gate is valid
exactly when re-hashing those inputs reproduces it. No timestamp is consulted,
so a commit that leaves the tree unchanged leaves a pass standing.

The hash is taken before the checks start and again before the pass is recorded.
A recipe that finds the two different says so and exits non-zero instead of
recording: a peer session editing an input during a nine-minute run would
otherwise seal in a pass for a tree nothing checked.

`test-unit` subtracts `tests/integration_*` from the set it shares with `lint`
and `test-integration`, so editing an integration suite leaves the unit verdict
standing.

`format-docs`, `check-memory-hygiene.py`, `check-docs-links.py` and
`check-version` run uncached and write no gate file, so four fresh gates are not
the same thing as a green `precommit`. `GITLORE_GATE_FORCE=1` runs a gate
whatever its sentinel says.

`scripts/lint-shell.sh` discovers from the set the hash enumerates — tracked
files plus untracked, non-ignored ones — so a brand-new script that moves the
`lint` hash is a script the recorded pass linted.

`GITLORE_GATE_DIR` names another directory for the gate files. It is for a
caller that runs a recipe without meaning its verdict:
`tests/justfile_gates.bats` drives the real `test-unit` and `test-integration`
in this repository with `bats` stubbed out to list what they would run, and
points the variable at a scratch directory so that stubbed pass never replaces a
real one.

## Proving a test discriminates

A test written against code that already behaves gets its evidence from a
mutation: break the behaviour it names, and the test must go red. Hand-running
that is where the accidents live — a run read as a mutant result when the edit
never landed, mutants stacked on each other, a backup written to `/` because
`$TMPDIR` was unset. `scripts/mutate-and-run.sh` does the whole cycle:

```sh
scripts/mutate-and-run.sh <file> <sed-script> <bats-file> [<filter>]
```

The mutation is a sed script, so a report can quote it as the mutation's name; a
script matching nothing is refused rather than run, which is what keeps an
unmutated run from reading as a verdict. The subject must be tracked and clean,
the backup lives under `git rev-parse --git-path gitlore/mutate`, and the
subject is restored on every exit path and then checked against the index. A
backup still sitting there is a crashed run: the next invocation refuses and
prints the command that puts the subject back.

Exit codes: **0** the mutant was KILLED, the suite went red and the `not ok`
lines are in the output; **1** it SURVIVED, so nothing pins the behaviour; **2**
refused or broken — dirty or untracked subject, empty mutation, a filter that
selected no test, or a restore that did not come back byte for byte.

It is a developer tool. The one thing it cannot be pointed at is itself: the
outer run holds the file open while bash is still reading it.
