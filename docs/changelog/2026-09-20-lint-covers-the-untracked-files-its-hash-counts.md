# 2026-09-20 — `lint` covers the untracked files its own hash counts, and the gates suite stops overwriting real sentinels

A gate's promise is that the pass it recorded vouches for the tree the hash
describes, and `lint` was not keeping it. `gate-inputs-hash` enumerates tracked
files *plus* untracked, non-ignored ones (`--others --exclude-standard`), so a
brand-new script moved the `lint` hash the moment it was written;
`lint-shell.sh` discovered with a plain `git ls-files`, tracked only, so it
never read that file. The recipe ran, passed, and recorded a pass over a file
shellcheck had not seen — and exactly on the commit introducing it, when a stale
green costs most.

Discovery now reads the same set as the hash, NUL-delimited. The first run over
the widened set found three SC2034 false positives in
`scripts/lib/continuation.sh`, whose globals `scripts/resolve.sh` reads back —
the kind of finding that only appears once a file is actually linted.

The second half is the same shape one level up. `tests/justfile_gates.bats`
drives the real `test-unit` and `test-integration` in this repository with
`bats` stubbed out to list what they would run, and every such run recorded a
stubbed pass over this repo's real sentinels — `test-integration` was never
cached after a unit run, because the suite had just overwritten its gate file
with a verdict from a run that executed no test. `GITLORE_GATE_DIR` names
another directory for the gate files, for exactly this caller: one that runs a
recipe without meaning its verdict. The suite points it at scratch.
