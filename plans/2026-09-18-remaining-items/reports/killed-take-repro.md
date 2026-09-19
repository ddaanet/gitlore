# Killed-take root drift — reproduction

## Verdict

The claim reproduces, on the real take shape (`gitlore_adopt_advanced_live`
starting from a clean tier on its pin with local `live` ahead of `HEAD`,
driven through the real `/gitlore:merge` entry point). The window between
`gitlore_compose_up` writing root's `MEMORY.md` and the take staging the pair
(`MEMORY.md` + the tier gitlink) is real. A kill inside it, followed by an
ordinary `SessionStart`, dirties the tier's own `MEMORY.md` with a bullet for
a file it does not have — silently, as far as that specific defect goes. A
later take does not heal it: it refuses, on dirt `SessionStart` itself
produced, with a remedy that does not fit what happened. An immediate retry
with no `SessionStart` in between is a pure no-op — it neither heals nor
worsens anything.

## The window: file:line

- `gitlore_adopt_tier_into_root` (`scripts/lib/resolve.sh:1974`) calls
  `composed=$(gitlore_compose_up "$mempath" "$tier")` at `resolve.sh:1980`.
- `gitlore_compose_up` (`scripts/lib/index-compose.sh:835`) writes root's
  `MEMORY.md` directly via `gitlore_compose_write "$root"`
  (`index-compose.sh:846`) — an ordinary uncommitted working-tree write, no
  staging.
- The pair is staged only later, in `gitlore_adopt_stage_pair_and_commit`
  (`resolve.sh:2164`), at the `git -C "$mempath" add -- MEMORY.md "$tier"`
  call (`resolve.sh:2170`), reached through `resolve.sh:1991` /
  `resolve.sh:2098` after `gitlore_compose_up` returns rc 0.

The window is `index-compose.sh:846` (root written) through `resolve.sh:2170`
(pair staged). A kill anywhere in that span leaves the state below.

## Reproduction

`tests/killed_take_repro.bats` (new file, two tests, both pass — run alone via
`bash scripts/run-bats.sh tests/killed_take_repro.bats`, `2 passed`).

The fixture is `strand_live_ahead_of_pin` from
`tests/helpers/tier-fixtures.bash`, the same one every
`gitlore_adopt_advanced_live` test in `tests/merge_memory.bats` uses: a tier
mounted, composed, committed, then advanced by one commit whose `HEAD` is
pushed to the tier's own local `live` and then walked back to the pin — a
clean tier on its pin with `live` one commit ahead. The take is driven through
its real entry point, `scripts/merge-memory.sh` — the same script
`/gitlore:merge` invokes.

The kill is induced deterministically, as suggested: a `git` shadowed onto
`PATH` that delegates every call to the real binary except the take's
pair-staging call (`add -- MEMORY.md ddaanet`), which it refuses — the on-disk
equivalent of a process kill landing there, without depending on timing.

### Step 2 — killed take: on-disk state

```
$ PATH="<killbin>:$PATH" bash scripts/merge-memory.sh
gitlore: memory — already holds everything its remote does.
gitlore: tier 'ddaanet' — its local 'live' held commits the memory store never recorded; adopted them at <short-sha-of-live>.
gitlore: composed memory/MEMORY.md
killed-take-stub: refusing the pair-staging add
gitlore: tier 'ddaanet' advanced, but its pointer could not be staged in the memory store. Run `git -C "<abs>/memory" add -- MEMORY.md "ddaanet"` before the next session, or the pointer will be reset to its previous commit.
gitlore: tier 'ddaanet' — already holds everything its remote does.
gitlore: the memory store has uncommitted changes. Anything this take staged rides the next memory commit (approved summary), and reaches the remote on the next /gitlore:push.
$ echo $?
0
```

**BENIGN**: the take script itself does not fail. `gitlore_adopt_stage_pair_and_commit`'s
staging is best-effort — a failed `add` is reported and the function falls
through — so the whole take exits 0 even though nothing was staged, and it
prints the exact hand-recovery command.

On-disk state confirmed by the test:
- Tier `HEAD` = tier `live` = the arrival's sha (the checkout-to-`live` step
  of `gitlore_adopt_advanced_live` ran; that part landed).
- Memory's index (`git -C memory rev-parse :ddaanet`) still names the **old
  pin** — the gitlink never moved, because the one call that would have
  staged it is the one refused. **DEFECT premise**: this is the claim's
  starting condition, confirmed real.
- `git -C memory status --porcelain` shows both `MEMORY.md` and `ddaanet`
  modified (root's up-projected write, and the tier pointer disagreeing with
  the index) — none of it staged (`git diff --cached --name-only` is empty).
- Root's `MEMORY.md` already carries
  `- [local](ddaanet/local.md) — committed here, never recorded` —
  `gitlore_compose_up`'s write, landed and uncommitted.

### Step 3 — the real `SessionStart` hook

```
$ echo '{}' | GITLORE_LAUNCHED=1 bash scripts/cc-hooks/session-start.sh
Submodule path 'ddaanet': checked out '<pin>'
{"systemMessage":"gitlore: memory ready (detached at live); uncommitted changes present, skipped live sync.

gitlore: the memory index points at 1 missing file. Nothing was rewritten or deleted — restore each file, or remove its line (removing a line deletes nothing).
memory/MEMORY.md: ddaanet/local.md names no file in the memory store", ...}
$ echo $?
0
```

- Tier `HEAD` is back on the pin. **BENIGN on its own**: `submodule update`
  (`scripts/cc-hooks/session-start.sh:289`) reads the gitlink from memory's
  index — still the unmoved pin — and resets the tier's worktree to it. That
  is the ordinary, correct "return an off-pin tier to its recorded commit"
  behavior; nothing here is specific to a killed take.
- The systemMessage **does** name `ddaanet/local.md` as a dangling root
  pointer. This is real coverage, but coincidental and for the wrong reason:
  it is `gitlore_compose_orphans`-style reporting on **root's own** index,
  traceable to `gitlore_compose_up`'s write alone (that line already named a
  file the memory store doesn't have, from the moment root was written in
  step 2) — not a report that the tier's own carrier is about to be rewritten.
- **DEFECT (the claim under test)**: `gitlore_compose_check_pins`
  (`scripts/lib/index-compose.sh:521`) now reads `HEAD == :ddaanet` (both the
  same unmoved pin), so it does not refuse. `SessionStart`'s own compose pass
  proceeds to the down projection (`gitlore_compose_down`,
  `index-compose.sh:704`), which prefers root's bullets for any path root has
  one for, unconditionally (`index-compose.sh:756`, the `[ "$o" = 1 ]`
  branch — no check against what the tier's own `HEAD:MEMORY.md` or working
  tree holds). Root still carries the `local.md` line the killed take wrote,
  so it lands in the tier's own `MEMORY.md`:
  ```
  $ cat memory/ddaanet/MEMORY.md   # bullets
  - [local](local.md) — committed here, never recorded
  $ git -C memory/ddaanet status --porcelain
   M MEMORY.md
  ```
  Nothing in the `SessionStart` output names the tier's *own* carrier as
  changed or dirty — only root's pre-existing dangling pointer is reported.
  This half of the defect is unreported.

### Step 4 — the real take, run again after `SessionStart`

```
$ PATH="<killbin>:$PATH" bash scripts/merge-memory.sh
gitlore: memory — already holds everything its remote does.
gitlore: tier 'ddaanet' — its local 'live' holds commits the memory store never recorded, but the tier has uncommitted changes, so nothing was adopted. Commit them (approved summary, then a memory commit) and run /gitlore:merge again.
$ echo $?
1
```

**DEFECT**: the take refuses — but on dirt `SessionStart`'s own
reset-and-recompose produced, not on any unapproved edit an agent made.
`gitlore_adopt_advanced_live`'s dirty-tier guard is what fires (the tier's
`live` is still ahead of `HEAD`, since `HEAD` sits back on the pin and `live`
still holds the arrival), and its printed remedy — commit the dirt, then
merge again — does not fit what actually happened here: following it would
commit the phantom `local.md` line straight into the tier's own history,
turning a working-tree artifact of the down projection into a real fact the
tier publishes.

### Step 5 — killed take, retried immediately, no `SessionStart` in between

```
$ bash scripts/merge-memory.sh   # real git, no SessionStart run first
gitlore: memory — already holds everything its remote does.
gitlore: tier 'ddaanet' — already holds everything its remote does.
gitlore: the memory store has uncommitted changes. Anything this take staged rides the next memory commit (approved summary), and reaches the remote on the next /gitlore:push.
$ echo $?
0
```

**BENIGN**: `merge-memory.sh` (`gitlore_merge_stores`) never calls
`gitlore_compose`/`gitlore_compose_check_pins` itself — only `SessionStart`
and the commit-path do. It only calls `gitlore_adopt_advanced_live`, which is
a no-op once `HEAD` already equals `live` (nothing left "ahead" to adopt,
since the checkout to `live` already landed in step 2). The retry is a pure
no-op: neither ref moves, neither store's dirt changes shape, and the
half-landed state just sits — exactly as the take's own printed remedy in
step 2 said it would, until `SessionStart` runs or a hand `git add` follows
the printed command.

## Is anything lost, or merely dirty?

Nothing is destroyed. The arrived fact is not lost — it still sits in the
tier's history at `live`/the old `HEAD`, and after `SessionStart`'s reset, at
`live` alone, exactly the "ahead of pin, live holds it" shape
`gitlore_adopt_advanced_live` exists to adopt. What's actually lost is a clean
path back to it: the tier is dirty on its pin (not off it), a shape no
existing guard is written for, and the printed refusal after `SessionStart`
misnames the fix.

## What currently recovers it, and what a user has to do by hand

Two working paths, both requiring a human to notice and act before
`SessionStart` runs again:

1. **Follow the take's own printed remedy verbatim**, before the next
   session: `git -C "<abs>/memory" add -- MEMORY.md "ddaanet"`, then land the
   usual parent commit (which drives memory's own FR11-gated commit). This
   stages exactly the pair the kill left unstaged and heals the store the way
   a landed take would have. Not verified end-to-end here (out of this
   reproduction's scope), but it is the mechanism `gitlore_adopt_stage_pair_and_commit`
   itself names.
2. **Retry the take before `SessionStart` runs** (step 5): confirmed harmless
   but also non-healing on its own — it buys time, not a fix, since
   `merge-memory.sh` never re-attempts the staging call once `HEAD` already
   equals `live`.

Once `SessionStart` has run (step 3) and a retried take has refused (step 4),
there is no tooling path forward: the printed remedy ("commit them, then
merge again") tells the user to commit the very dirt the down projection just
manufactured. Recovering by hand at that point means recognizing the stray
`local.md` line in the tier's `MEMORY.md` is spurious, discarding it
(`git -C memory/ddaanet checkout -- MEMORY.md`), and then following path 1
above against the tier's own `live` (still holding the real arrival) to
finish the adoption properly.

## Candidate recoveries (not a decision)

Re-judged against what step 4 actually shows: the failure mode is not "the
tier is dirty and the take should refuse" (that part of the guard is
correct behavior *in general* — a dirty tier really might hold unapproved
work) — it's that `SessionStart`'s own compose pass is what created the dirt
being refused on, and nothing distinguishes that from a session's own
uncommitted edit.

1. **Make the down projection pin-aware per line.** In `gitlore_compose_down`,
   don't unconditionally prefer root's bullet for a path merely because root
   has one (`index-compose.sh:756`); also require the path to exist in the
   carrier's own `HEAD:MEMORY.md` (or working tree) before trusting root's
   text for it. This would have stopped step 3's write outright — the tier
   would never have been dirtied, so step 4 would have nothing to refuse.
   Changes the down pass's contract for every tier, not just a killed take —
   needs the D36/D50 "root always wins" argument re-examined for what else
   relies on it, since the whole point of a pin is that root and the pinned
   commit are supposed to agree by construction; this proposes a second,
   independent check for the one case they provably don't (an unstaged
   gitlink).
2. **Make `gitlore_compose_check_pins` also refuse a dirty on-pin tier whose
   `MEMORY.md` differs from a rebuild of its own committed bullets**, ahead of
   the down projection running at all. Would turn step 3's silent write into
   a step-3 refusal instead of a step-4 one — closer to the pin guard's
   existing job (it already refuses on disagreement with the index; this
   extends "disagreement" to cover carrier content, not just `HEAD`). Costs a
   second read (rebuild-and-diff) on every compose pass, for a state that's
   rare outside a killed take.
3. **Close the window itself**: write root's new `MEMORY.md` and stage the
   pair as one atomic unit — e.g. write to a temp file and only rename/stage
   once both halves are ready, so a kill lands either before any change or
   after both are staged, never in between. Removes the window directly
   rather than compensating for its effects downstream (steps 3 and 4 both
   disappear), but is the largest change of the three: it touches
   `gitlore_compose_write`'s and `gitlore_adopt_stage_pair_and_commit`'s
   shared contract, and every other caller of `gitlore_compose_up`/
   `gitlore_compose_write` (in-session compose, `SessionStart`'s own compose)
   would need the same atomicity, or the fix would be take-only while those
   callers keep a version of the same class of window.
