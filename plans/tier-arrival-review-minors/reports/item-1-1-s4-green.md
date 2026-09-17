# Item 1.1 / slice 4 — GREEN report

**Test:** `a repair whose checkout follow fails walks back and keeps the repair`
(`tests/merge_memory.bats`).

**Change:** in `gitlore_adopt_repair_arrival`'s checkout-follow arm
(`scripts/lib/resolve.sh`), replaced the bare
`gitlore_adopt_walk_back_tier "$mempath" "$tier" "$old_gitlink" "$label"` with
`gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." "the repair"`,
keeping the existing `|| :` / `return 1` idiom and the arm's own
`could not follow` line unchanged.

**Verification:**
- `scripts/run-bats.sh tests/merge_memory.bats --filter 'checkout follow fails'`
  — 1 passed, 0 failed.
- `scripts/run-bats.sh tests/merge_memory.bats` — 38 passed, 0 failed.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats` — clean.

**Commit:**
`♻️ Item 1.1/4 — a failed checkout follow reports the refusal and keeps the repair`,
staging
`tests/merge_memory.bats scripts/lib/resolve.sh plans/tier-arrival-review-minors/reports/item-1-1-s4-red.md plans/tier-arrival-review-minors/reports/item-1-1-s4-test-review.md plans/tier-arrival-review-minors/reports/item-1-1-s4-green.md`.
