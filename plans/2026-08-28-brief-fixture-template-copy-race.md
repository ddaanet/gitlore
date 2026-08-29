## Brief: an intermittent fixture-template failure in the integration suite

2026-08-28 — target: `gitlore` · observed during a `ddaa:preflight` run

### Observation

The first `just test-integration` of the preflight run failed one test; an
immediate re-run of the same recipe passed 72/72, and the file run alone passed
2/2. Nothing in the tree changed between the two runs.

```
not ok 7 a naked 'git -C memory commit' is blocked by the gate
# (from function `make_parent_with_memory' in file tests/helpers/fixtures.bash, line 42,
#  in test file tests/integration_memory_gate.bats, line 25)
#   `make_parent_with_memory' failed
# fatal: cannot change to 'memory': No such file or directory
# make_parent_with_memory: template copy broke the memory submodule's HEAD
```

### What the failure establishes

- The fixture reached its **second** guard, not its first. `git submodule
  status` succeeded and only `git -C memory rev-parse HEAD` failed
  (`tests/helpers/fixtures.bash:38-42`). `submodule status` reads the gitlink
  from the index, so it passes whether or not the working directory exists —
  the tree that `cp -a "$template/." "$TMP_REPO/"` produced was missing
  `memory/` while its index entry was intact.
- The suite runs parallel: `test-integration` passes
  `--jobs $(nproc)` to `scripts/run-bats.sh` (`justfile:133`). The isolated
  re-run used neither `--jobs` nor a second file, so it could not have
  reproduced a cross-file race even if one exists.
- The template is built once per `bats` invocation under `BATS_RUN_TMPDIR`,
  behind an atomic `mkdir` lock plus a `.ready` marker
  (`_gitlore_ensure_parent_with_memory_template`), and every caller copies it
  with `cp -a`.

### Leads, in no particular order

- **Copy-vs-build ordering.** `.ready` is touched only after
  `_gitlore_build_parent_with_memory` returns 0, which appears to close the
  partial-copy window. Confirm that it does, rather than assuming it: the
  builder's first act is `rm -rf "$repo"`, so any path that reaches it while
  another job is mid-`cp -a` deletes the source under the reader.
- **The failed-build path.** When the build fails, `.ready` is never created,
  the lock is released and the loop `break`s, so the caller returns 1 with no
  message of its own. That is a different symptom from the one observed (which
  carried a message), but it is a silent failure mode worth closing while here.
- **Sandbox artifacts.** `cp -a` of a `.git` directory under an agent sandbox
  is the documented home of phantom dotfiles and transient `Device or resource
  busy` errors. The run happened inside a Claude Code Bash sandbox; a bare
  terminal run is a cheap discriminator.
- **`cp -a` error handling.** The copy's exit status is not checked. Whatever
  the root cause, a partial copy currently surfaces as a confusing assertion
  two lines later rather than as the copy failing.

### Reproduction

Loop `just test-integration` (parallel, full file set) rather than the single
file; the failure did not appear in ~1 of 2 full runs, so expect to need
several. `GITLORE_TEST_JOBS` raises or lowers the job count if the race is
contention-sensitive.

### Scope note

This is a defect in the test fixture, not in shipped behaviour: the assertion
that failed is a guard the fixture makes about its own setup, and the gate it
was about to exercise was never reached. It does not block a release; it does
mean a red integration run on the release path is not automatically a real
regression, which is its own cost.
