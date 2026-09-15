# Phase 3 corrector guard — mutation red

Closes tdd-audit F3 for `af79f3f`'s guard "a tier merge whose incoming side
welds a line is refused, and the split synthesis publishes"
(`tests/resolve_compose.bats`), run by the orchestrator on HEAD `ce3c23b` after
the final `just precommit` passed.

Mutation: in `scripts/resolve.sh` `compose_merged_indexes`, the merged-index
gate's `exit 1` became `: exit 1`, so a failing merged carrier lands.

    not ok 1 a tier merge whose incoming side welds a line is refused, and the split synthesis publishes
    # (in test file tests/resolve_compose.bats, line 275)
    #   `[ "$status" -eq 1 ]' failed

Restored from a saved copy (`cmp` identical, `git diff --quiet` clean); the test
then passed (`bats: 1 passed, 0 failed`).
