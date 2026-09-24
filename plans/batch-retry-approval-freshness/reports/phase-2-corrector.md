# Phase 2 checkpoint — corrector report

Item 2.1's docs commit `4b27cda`, five files. Three findings fixed in place, one
readability fix applied. Nothing committed.

Files changed by this pass:

- `docs/references/commit-gate.md`
- `docs/changelog/2026-09-24-the-batch-retry-is-judged-by-the-approval-freshness.md`

## Findings fixed

### 1. MAJOR — the freshness-`yes` paragraph asserted the behaviour D56 removes

`commit-gate.md` ended its `yes` arm with "The retry is silent on that arm and
lands once the fix is made." That is the defect, not the fix. The D50 abort arm
restamps `$msgfile` (`resolve-sync-memory.sh:181`), the agent's index edit lands
after that restamp, and `gitlore_commit_msg_freshness` therefore reads `no` on
the next batch: the sync refuses at `resolve-sync-memory.sh:51-54` and the hook
takes its re-approval arm. `tests/cc_hook_memory_commit_batch.bats:215` ("a fix
after an aborting index does not commit under the old approval") asserts exactly
that — `HEAD` unchanged, both IPC files kept, `no longer covers` in the agent
message — and a reader acting on the old sentence would have concluded the suite
was wrong.

Rewritten to state where the fix lands the next batch:

> The retry is silent on that arm; making the fix is itself a write to the
> store, so the batch that follows it reads freshness `no` and asks for the
> summary again.

That also makes the paragraph's own `no` clause ("the agent's own fix") and this
one agree, which they did not.

### 2. MAJOR — "Both IPC files are removed only on a complete commit" is false
for the message file

The bolded lead of the IPC paragraph. `resolve-sync-memory.sh:245` removes
`$msgfile` immediately after the blessed commit and **before** the `HEAD:live`
fast-forward whose three `return 1` arms (`:267`, `:275`, `:285`) are the only
way to reach the consumed state. The trigger is what survives to the end of a
complete run — `rm -f "$trigger"` sits in the hook's success branch alone. So
the lead contradicted the consumed arm documented two paragraphs below it, and
`memory-entry-points.md`'s own shared-body sequence (`commit -F <msgfile>` →
`rm <msgfile>` → `push . HEAD:live`) already spelled the ordering out.

Lead replaced with **Nothing is consumed before the commit it approves**, which
is what the paragraph actually argues, and the ordering stated at the end:

> The blessed commit consumes the message file; the trigger goes only once the
> whole run succeeds, the `HEAD:live` fast-forward included.

The "on any failure before the commit, both stay put" sentence is unchanged and
is true: no arm deletes `$msgfile`, the restamp arms only `touch` it.

### 3. MAJOR — the changelog misplaced the consumed-approval mis-routing

The entry said the checkpoint review found that state "taking … to the
stale-summary arm", dropping the prepared-merge directive. That was the
`16abc35` state, and the slice-2 review had already closed it at `6790195` by
routing the consumed case to the deferred arm to recover `$out`. What the
checkpoint (`9188da5`) actually found was that *deferred* arm: three of its four
claims false after a commit that landed (per `reports/phase-1-corrector.md`
finding 2). As written, the entry credited the wrong pass with the wrong defect
— in the one document that is the audit trail for how this shape was reached.

Rewritten as "The third failure state took two passes to place", carrying both
steps: the stale-arm routing and its dropped directive, then the deferred-arm
routing and its false wording, then the checkpoint's own arm tested first.

### 4. MINOR — garden-path opening to the D56 argument

"`commit-memory.sh` handed the message file as its own `-F` operand rewrites
that file …" parses only on a second pass. Reordered to "Handed the message file
as its own `-F` operand, `commit-memory.sh` rewrites that file …". No claim
changed.

## Checked, sound

- **The three failure arms and their test order.** Doc order consumed → `no` →
  `yes` matches `memory-commit-batch.sh:125/137/146`. The consumed arm's claims
  hold: nothing waits on approval (`$msgfile` gone), and no batch repeats the
  step — the commit landed, so the next batch meets the clean-memory branch at
  `:76`, which clears the trigger. Its "the script's reason is the whole
  message — on divergence, the prepared-merge directive" matches
  `gitlore_yield_merge` at `:275`.
- **The blank-summary predicate on both entry points.**
  `[ ! -s "$msgfile" ] || ! grep -q '[^[:space:]]' "$msgfile"` byte-identical in
  `memory-commit-batch.sh:84` and `commit-memory.sh:70`. The node's "each screens
  it with one predicate ahead of the run" is true of the sync run on both paths,
  and D56's own paragraph states the `commit-memory.sh` screen sits after its
  `-m`/`-F` write, which is where the arg path gets covered.
- **What `-m`/`-F`/bare do.** `commit-memory.sh:60-63` writes only under
  `have_summary = 1`; bare leaves the file untouched and falls through to
  `gitlore_sync_memory_to_live`. `memory-entry-points.md`'s "dirty with the
  approval absent or blank → exit 1 …; dirty with a stale one → the sync's own
  refusal" matches the two refusal sites (`commit-memory.sh:71` and
  `resolve-sync-memory.sh:51`).
- **Which failures keep both IPC files.** Every pre-commit `return 1` leaves
  `$msgfile` on disk; the restamp arms `touch` it, the stale-merge guard arms
  (`:18`, `:46`, `:91`) do not (D53). The freshness-`no` arm removes neither
  file, so "both files stay, and the stale file is the text to re-present" holds,
  and `tests/…:258` compares the bytes.
- **The D53 cross-reference.** `git-hooks.md:285-293` refuses a per-arm return
  code from `gitlore_guard_stale_merge_state` on the asymmetry of what each
  mistake costs — "a misclassified arm marks an approval fresh over content no
  summary covers … the FR11 boundary breached silently" — plus the
  future-arm-defaults argument. D56's two renderings (the argument paragraph and
  the rejected entry) both state it as that, not as a general dislike of exit
  codes.
- **Present tense, current truth.** `grep -nE '\b(now|no longer|previously|used
  to|formerly|earlier version)\b'` over the two nodes and the decisions index
  returns two hits, both pre-existing and both legitimate uses of "now"
  (`commit-gate.md:211`, `memory-entry-points.md:64`). The narrative lives in the
  changelog entry alone, where before→after phrasing belongs. D56's opening
  paragraph describes the superseded `-F <msgfile>` shape in present tense as a
  decision rationale, which is the write-time record the style rules preserve.
- **Living-doc form.** D56 carries a `**D56 — <title>**` heading, bolded lead-ins
  per argument, and prose rather than a table, as D4/D12/D19/D22 do. The node's
  opening bullet, its `## Decisions — D4, D12, D19, D22, D56` heading and the
  section's framing sentence all gained D56 together, which is what keeps
  `enumeration-drift` and `delegation-drift` at 0. The five rejected alternatives
  are bold-led and `(D56)`-tagged, matching `git-hooks.md`'s `(D50)`/`(D46)`
  convention.
- **`docs/decisions.md`.** One conclusion line for D56 under "The commit gate",
  and the five rejected alternatives appended by name to that group's
  `*Rejected:*` line — no rationale duplicated from the node.
- **The changelog entry.** Names what moved (the bare invocation, the three
  states read off the store and the IPC file), the reasoning available (D53 one
  layer out, D16 for the arg path), both refusal loops, and both flagged-unfixed
  defects. It cites D56 rather than restating the argument. `docs/changelog.md`'s
  index line matches the siblings' shape — link text is the H1 without the
  `(D56)`, id at the end of the summary.
- **The two flagged-unfixed defects, as described.** The prepared-merge one
  reproduces from the code: after the landed-then-failed merge arm the store is
  dirty again (the merge preparation writes the worktree) with `$msgfile` gone,
  so the hook's screen at `:84` fires ahead of the run and the stale-merge guard
  at `:18` is never reached. The clean-memory overstatement is at `:80`.

## Gates

- `python3 scripts/check-docs-links.py` — `56 decisions, 136 files scanned`, 0 in
  every category.
- `python3 scripts/check-memory-hygiene.py` — `67 facts, 162 files scanned`, 0 in
  every BLOCK category; `deictic 15` and `dangling-wikilink 6` are the
  pre-existing warn-level counts over `memory/`, untouched here.
- `just format-docs` — ran twice; the second run reports `Found 44 issues` with
  no `Fixed` line and leaves `docs/` byte-identical, so the tree is at the
  formatter's fixed point. The 44 are the MD013 residue rumdl reprints and cannot
  rewrap.
- `wc -l` — `commit-gate.md` 359, `memory-entry-points.md` 245, `decisions.md`
  192, `changelog.md` 269, the new entry 49. All under 400; `oversized-file` is 0.

`just precommit` was not run, per the dispatch. The changed files are `docs/`
only, outside every cached recipe's declared inputs.
