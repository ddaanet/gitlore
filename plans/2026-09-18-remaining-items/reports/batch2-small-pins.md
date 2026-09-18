# Batch 2 — small code and test pins

Four independent items, all landed uncommitted in the working tree. Nothing
outside the files listed below was touched; no branch, commit, push or
`--no-verify`.

## Item 1 — the behind arm's retry push routing (pin)

**Files changed:** `tests/push_behind_vs_diverged.bats` only. No production
change: the behaviour is what `scripts/lib/resolve.sh:1406-1409` already does.

The pin: the behind arm's in-arm retry push — the one that publishes what the
take repaired — reports a refusal through `gitlore_report_tier_push_failure`, so
a refusal naming a non-fast-forward gets that reporter's divergence-shaped
branch ("was refused as a non-fast-forward, but its local 'live' already
contains the remote's. The remote moved during the push, or the fetch before it
failed.").

New test:
`a behind arm's retry push refused as a non-fast-forward is worded as a moved remote, not as a non-divergence failure`.
It reuses this suite's own `git`-stub-on-PATH idiom: the tier is behind with a
duplicated arrival, the real remote refuses its first push, the arm takes and
repairs, and the stub refuses the *second* push naming the tier. The push ledger
is asserted first (`ddaanet ddaanet`), so the refused push can only be the arm's
own retry and not the post-loop pass.

**Judgement asked for:** the divergence wording is *correct* for this case, not
merely pinned. After the take, `live` is a repair commit sitting on top of the
fetched `origin/live`, so "its local 'live' already contains the remote's" is
literally true and "the remote moved during the push" is the only remaining
explanation for a non-fast-forward refusal. Nothing to change.

**Red evidence (mutation).** The intended mutation — deleting the
`gitlore_report_tier_push_failure` call at the retry site — was refused by the
permission classifier as logging tampering. Substituted an argument mutation at
the same site, which routes the reporter into its other branch:

- mutation: `gitlore_report_tier_push_failure "$tier" "$tier_err"` →
  `gitlore_report_tier_push_failure "$tier" "declined by policy"`
  (`scripts/lib/resolve.sh`, behind-arm retry site)
- red:
  `not ok 15 a behind arm's retry push refused as a non-fast-forward is worded as a moved remote, not as a non-divergence failure`,
  failing at `tests/push_behind_vs_diverged.bats` line 454 —
  `[[ "$output$stderr" == *"pushing tier 'ddaanet' was refused as a non-fast-forward"* ]]`
- inverted by hand; `git diff scripts/lib/resolve.sh` is empty.

**Suites run (foreground):** `tests/push_behind_vs_diverged.bats` — 21 passed, 0
failed (green before the mutation, 20/1 under it, 21/0 after inverting).

## Item 2 — `_gitlore_nudge_reset`'s sweep is best-effort

**Files changed:** `scripts/lib/index-sync.sh` (the `find … -mtime +7 -delete`
in `_gitlore_nudge_reset` now ends `|| true`, with the same degrade-don't-abort
rationale `gitlore_relay_sweep` carries), `tests/cc_hook_plugin_upgrade.bats`.

Test written first:
`a failing sweep does not stop the reset from clearing this session's markers`.
It seeds both this session's markers, puts a `find` stub on `PATH` that fails
every call carrying `-delete` (the sweep and nothing else on that path) and
passes everything else through to the real `find`, then drives `nudge-reset.sh`.

**Red evidence:**
`not ok 8 a failing sweep does not stop the reset from clearing this session's markers`,
failing at `tests/cc_hook_plugin_upgrade.bats` line 200 — `[ "$status" -eq 0 ]`.
Under errexit the budget reset aborted the hook, so the upgrade reset never ran
either; both marker assertions were unreachable. Green after the guard.

**Suites run (foreground):** `tests/cc_hook_plugin_upgrade.bats` 12/0,
`tests/index_sync.bats` 89/0, `tests/cc_hook_session_start.bats` 25/0,
`tests/cc_hook_index_compose.bats` 28/0, `tests/cc_hook_add_tier.bats` 12/0,
`tests/commit_memory.bats` 36/0, `tests/index_compose.bats` 84/0,
`tests/index_merge.bats` 20/0, `tests/plugin_distribution.bats` 15/0 — the
suites that exercise `scripts/lib/index-sync.sh`.

## Item 3 — omit `additionalContext` when the context half is empty

**Files changed:** `scripts/cc-hooks/relay-drain.sh`,
`scripts/cc-hooks/index-compose.sh` (both now use the
`+ (if $c == "" then {} else {hookSpecificOutput: …} end)` form
`index-sync-post.sh` already uses), `tests/cc_hook_index_compose.bats`.

**Worth flagging: the empty-context state is not reachable from real inputs
today.** `gitlore_compose_and_report` sets both channels or neither in every
branch, and `gitlore_relay_drain` frames a `--- gitlore-relay agent <A> ---`
block per marker on *both* channels, so a non-empty sysmsg implies a non-empty
ctx in both producers. The change is defensive uniformity, and a test driven
through today's producers could not red it.

So the tests drive the hooks through a seam: `shim_plugin_root` builds a plugin
root whose `scripts/lib/*.sh` are one-line shims sourcing the real libraries,
with a redefinition of the producer appended to the last library the hook
sources. The hook script under test is the real one, invoked by its real path;
only `CLAUDE_PLUGIN_ROOT` is redirected. Three tests: one per hook asserting
`jq -e 'has("hookSpecificOutput")'` exits non-zero on an empty context half, and
a paired positive asserting both hooks carry the key and the right
`hookEventName` when the context half is not empty — without which the two
absences could pass on a hook that never emits the block at all.

**Red evidence:**

- `not ok 6 index-compose.sh omits additionalContext when the context half is empty`,
  line 194 — `[ "$status" -eq 1 ]`
- `not ok 7 relay-drain.sh omits additionalContext when the context half is empty`,
  line 205 — `[ "$status" -eq 1 ]`
- the paired positive passed in the same run, so the seam itself was already
  proven to reach the hooks.

**Suites run (foreground):** `tests/cc_hook_index_compose.bats` — 26/2 red, 28/0
green after the change. Plus `tests/plugin_distribution.bats` 15/0 and
`tests/lint_shell.bats` 3/0 (shellcheck over the edited hooks).

## Item 4 — the index budget reads as ambient, not as a goal

**Files changed:** `scripts/cc-hooks/index-sync-post.sh`,
`tests/index_sync.bats`, `docs/references/index-authoring-sync.md`.

`scripts/cc-hooks/index-sync-post.sh` is the only place the percentage or the
budget is reported — `grep` over `scripts/`, `skills/` and `commands/` finds
`gitlore_index_budget_pct` used nowhere else, and everything else is comments,
the two tunables, or `commands/index-audit.md`'s account of Claude Code's own
loader cap (left alone: the audit *is* the deliberate goal-directed pass).

New wording, both channels:

- user:
  `gitlore: MEMORY.md is at N% of the B-byte always-loaded budget — a size notice, nothing to act on`
- model: the percentage, then "This is ambient information about the store, not
  a task: the fact just written stands, and nothing here asks for curation now
  or says any particular line should go.", then the loader-truncation fact as
  *what the number is for*, then that curation is the `/gitlore:index-audit`
  pass, run when it is asked for.

Test updates: `tests/index_sync.bats` holds the two exact-equality assertions on
those blocks; both updated. The test was also renamed from "post: warns past the
byte threshold…" to "post: notes the size past the byte threshold…" since
"warns" is the framing being removed. The other budget tests assert only the
presence or absence of the word "budget" and were left alone.

Doc: the D39 paragraph in `docs/references/index-authoring-sync.md` gained a
paragraph stating the ambient-not-a-goal rule and where deciding-what-goes
belongs. `just format-docs` run afterwards (it reflowed that paragraph and
touched nothing else); `scripts/check-docs-links.py` clean, and the node is 381
lines, under the 400 cap.

**Also fixed in the same sentence, and worth a second pair of eyes:** the doc
claimed the pass "names the percentage *and the five largest lines*". It does
not — the hook reports the percentage only. `gitlore_index_largest` has
**no production caller anywhere** (`scripts/`, `commands/`, `skills/`); it is
exercised only by two direct unit tests in `tests/index_sync.bats`. I corrected
the doc to state what the pass does and left the function in place — deleting it
is outside this batch and removes something.

**Suites run (foreground):** `tests/index_sync.bats` 89/0,
`tests/check_docs_links.bats` 43/0.

## Not done

- `just precommit`, `just test-unit`, `just test-integration` were not run, per
  the brief; every suite above was run individually in the foreground through
  `scripts/run-bats.sh`. Integration suites (`tests/integration_*.bats`) were
  not run at all.
