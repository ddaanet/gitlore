# Item 1.1 slice 3 — GREEN report

Test: `a repair beside a root problem lands in live and waits`
(`tests/merge_memory.bats`)

## Change

`scripts/lib/resolve.sh`:
- `gitlore_adopt_walk_back_tier` gains `<live_holds>` (`$6`, default
  `what arrived`), used in `its local 'live' keeps <live_holds>.`; `Args:`
  comment updated.
- `gitlore_adopt_report_refusal_and_walk_back` gains `<live_holds>` (`$7`),
  passed through to the walk-back call; `Args:` comment updated.
- The retry-refusal call in `gitlore_adopt_repair_arrival` (after
  `gitlore_compose_up` retry) now passes `""` (default remedy) and
  `"the repair"`.

## Checks

- `scripts/run-bats.sh tests/merge_memory.bats`: 37 passed, 0 failed.
- `grep -rln "keeps what arrived" tests/ docs/ skills/ agents/ scripts/`: only
  `tests/merge_memory.bats`, already covered by the run above.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats`: clean.
