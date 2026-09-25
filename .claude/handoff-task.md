## Current task

Nothing is in flight. The first full macOS run of the unit suite is patched — the launcher shim's exec loop, the symlinked-`$TMPDIR` fixture class, the BSD `wc`/GNU `stat` spellings, the bats version declarations, and the `python3`/`rumdl` borrows in `scripts/test-macos.sh` — and the gate is green on Linux. The run it came from stopped at case 677 of 1016, so the suites after `tests/launcher_shim.bats` have still never executed on a Mac.
