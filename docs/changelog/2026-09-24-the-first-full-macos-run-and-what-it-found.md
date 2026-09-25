# 2026-09-24 — The first full macOS run, and the launcher shim that hung it

`scripts/test-macos.sh` had never met the whole unit suite. The first run that
did reported 95 failures out of 677 cases and then hung, and the hang is the
find worth recording: one defect in shipped code, with everything else in the
fixtures or in the narrowed `PATH`.

`scripts/install/launcher-shim` strips its own directory from `PATH` so
`command -v claude` resolves the real binary, and it compared raw spellings.
`$self` comes from `cd`+`pwd`, which collapses a `//` and drops a trailing `/`;
a `PATH` entry carrying either survives the strip, and the shim's `exec` then
re-enters the shim. That is not a failure, it is an infinite loop — the suite
did not report it, it stopped. macOS `$TMPDIR` ends in `/`, so every path the
fixtures build from it carries the `//` that triggers it, and any user whose
`PATH` spells the shim's directory a second way meets the same thing. Each entry
is now resolved to the physical form `$self` is already in, which covers the
symlink and `..` spellings too. A second physical *copy* of the shim, in a
directory of its own, is still uncovered: no sentinel distinguishes that
re-entry from an ordinary nested `claude` inside a session, so the bound is
stated in the script rather than half-enforced.

Two fixture defects and one tooling gap account for the rest. macOS `$TMPDIR` is
a symlinked `/var/folders/…` path while git and the scripts under test report
the physical `/private/var/…` one, so every `== *"$TMP_REPO"/…*` assertion was
comparing two spellings of one directory — about seventy cases, and they
reproduce on Linux under a symlinked `$TMPDIR`, which is how they were fixed and
verified. `setup_tmp_repo` resolves with `pwd -P`. The same comparison was in
shipped code: `install/run.sh` tested `$PWD` against git's toplevel, which git
reports with symlinks resolved, so a caller standing at the root of a symlinked
checkout was told to go to the directory it was already in. BSD `wc -l` pads its
count with leading blanks, which only shows where the caller compares with `=`
rather than `-eq`; `stat -c` is GNU-only, and no BSD stub reaches it because the
call sat in a test body rather than in a script a test execs. The `stat` class
now has a static lock-in in `tests/bsd_portability.bats`, since a Linux run
cannot fail on it.

The narrowed `PATH` is about the platform, not the toolchain, so `rumdl` joins
the borrowed tools and `python3` is borrowed on a capability rather than on
presence: a Mac has `/usr/bin/python3` and it carries no PyYAML, which the
hygiene gate and the `wire-*` scripts both need. Without one the header says so
— forty-odd failures with no stated cause is the outcome that made the probe
worth writing. Separately, bats honours `run --separate-stderr` only once a
suite declares `bats_require_minimum_version 1.5.0`; four suites used `run`
flags without it, which bats 1.11 tolerated and 1.14 does not, so `$stderr` came
back unbound on the Mac.

The run was interrupted at case 677 of 1016, so the suites after
`tests/launcher_shim.bats` are still unmeasured on a Mac.
