# 2026-09-25 — The macOS tail, a venv python behind a symlink, and a floor under bats

The run interrupted at case 677 went the rest of the way: 1016 cases, 50
failures, three causes. None is in shipped code. Two are in the macOS harness
itself and the third is a class of test that was green here for the wrong
reason.

`borrow_python` linked a venv interpreter and got a base one. It probed
`"$found" -c 'import yaml'` on the absolute path, where the import works, then
`ln -s`'d that path into the borrowed-tools directory. A venv interpreter
locates its `pyvenv.cfg`, and through it its site-packages, beside the path it
was invoked as; reached through a link in another directory it resolves to the
base interpreter and the venv's packages are nowhere on `sys.path`. Forty-two
cases failed on it — the whole hygiene suite, which `import yaml`s and so
tracebacked, and the `wire-*` cases, which say outright that they need a python3
with PyYAML. It is written as an `exec` wrapper now, and the probe runs through
the shim rather than past it. The probe and the use disagreeing is the general
shape: a check that does not exercise the artifact it is checking reports on
something else, and here it reported a successful borrow the suites could not
use.

The suite's own macOS check handed back bash 3.2 as the modern bash.
`tests/test_macos.bats` captured `real_bash="$(command -v bash)"` after
`setup_tmp_repo`, whose `use_test_bash` has by then put the stand-in for
`/bin/bash` first on `PATH` — so under the harness the lookup named the 3.2 the
harness exists to exercise, and the nested run refused it as older than 4.4. It
reads `$BASH`, the interpreter already running the test body, which no `PATH`
order can change.

The third is the one worth the floor. From 1.13 bats unsets `$stderr` on a
merged `run`; before it, the variable keeps whatever an earlier
`run --separate-stderr` captured. Three cases asserted on `$stderr` after an
intervening merged `run` — a `run jq`, a `run ! grep` — and so read stale text
under Debian's packaged 1.11 and an unbound variable under Homebrew's 1.14. They
hold the capture in a local now, which needs neither behaviour.

That class is invisible to a Linux run that happens to have the older bats, so
the fix is a floor rather than three repairs. Pinning bats was the alternative
and was rejected: `gate-inputs-hash` folds `bats --version`,
`shellcheck --version`, `jq --version` and `python3 --version` into every gate
hash precisely because this repo pins no tool versions, and pinning one would
make its own entry there dead weight. The declared floor rises from 1.10 to 1.13
instead, and `require_bats_version` in `tests/helpers/setup.bash` enforces it at
load, beside the bash floor.

Verifying that guard found that the guard beside it was not one.
`require_assertion_bash` refused by returning non-zero, and bats 1.11 does not
act on what a `load`ed file returns: the refusal printed its remedy to stderr
and every test in the suite still reported `ok`, with the run exiting 0. From
1.13 bats does act on it, so the defect was confined to the versions the new
floor excludes — but a guard that enforces a floor cannot be enforceable only
above it. Both guards `exit` now, which fails the load on every bats, and
`tests/bsd_portability.bats` pins the refusal end-to-end through a real bats
load rather than by calling the function.

All three fixes are verified on Linux only. The macOS side of each is unverified
by construction, and a re-run of `scripts/test-macos.sh` is the check.
