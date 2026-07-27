## Current task

Landed judge.sh's 3-state exit (0 pass / 1 fail / 2 invalid-or-unparseable)
after determining the real failure mode was a hedged verdict ("FAIL, but
wait... PASS"), not judge unavailability. Updated both assert call sites
(memory-commit.sh, tier-write.sh), added bats coverage, documented the
decision in docs/design.md's changelog, and dogfooded via a single-trial
(EVAL_K=1) full eval run — 5/5 scenarios passed, including 03-add-tier and
04-tier-write which exercise the changed judge path.

## Open decisions

- Push gitlore's `main` to `origin`, or hold — several commits ahead of
  `origin/main`, most pre-existing from before this session.
