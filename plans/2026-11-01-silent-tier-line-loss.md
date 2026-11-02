# Compose only where the edit happens — plan

Status: done. Base: `dev`. Supersedes the restore-or-report choice: restore,
with a message.

## The defect this started from

A line deleted from a tier's carrier only, while root has it and root at `HEAD`
carries it, stays deleted, and no report fires. Reproduced in a scratch store:
`gitlore_order_merge` reads it as a clean three-way deletion, against the
comment at `scripts/lib/index-compose-project.sh:165` ("every line root carries
is emitted"). The commit-path compose then publishes it, and each consumer's
adoption drops the line from root. The real `ddaanet` tier has no such line.

## Design

1. **`PostToolBatch` composes, and reports what it wrote.** Its stamp watches
   each active tier's carrier as well as root and the manifest. A carrier-only
   deletion is restored at batch end, with `additionalContext` naming the line
   and saying a removal starts in root.
2. **`gitlore_compose_down` restores.** Drop from `head.paths`, before the order
   merge, any path root has and the carrier lacks, so it reads as root's
   insertion at root's offset.
3. **`SessionStart` does not compose.** Remove `session-start.sh:230`. It
   reports position: in sync; behind (suggest `/gitlore:merge`: fast-forward, a
   canned commit, no push required); diverged (suggest `/gitlore:push`).
4. **The commit path does not compose.** `scripts/commit-memory.sh:127` and
   `scripts/lib/resolve-sync-memory.sh:162` become a read-only check that aborts
   when a pass would change an index.
5. **Mount is unchanged.**

## Contract

- Pre: as above; `SessionStart`'s and the commit path's composes are the only
  down-projecting passes besides `PostToolBatch` and the mount.
- Post: no `gitlore_compose` write outside `PostToolBatch` and the mount. A
  commit with a pending compose aborts, naming the index and the remedy.
  `(b=1, o=1, t=0)` emits root's line; every other `(b, o, t)` gives its present
  output.
- Invariant: compose never changes a line's text. The up-only passes (take,
  merge continuation) and `gitlore_compose_check`'s rules are untouched.
- Tests: the `(b, o, t)` state table is the red case for the restore; red cases
  for the carrier stamp, the commit abort and each position report. Tests
  pinning the removed passes are rewritten as what `SessionStart` now does with
  that store, not deleted: `tests/tier_discovery.bats:278,295`,
  `tests/tier_divergence.bats:216`, and `tests/killed_take_repro.bats`, whose
  defect the removal fixes, so it becomes the regression guard (carrier clean
  after the reset, the later take succeeds).
- Docs: D31 (four triggers become two), D50 (its rejected "a refusal that
  instructs the agent to run compose" and "composing a clean store" are inverted
  by this decision; "`SessionStart` repairs it" goes), D36's deletion paragraph,
  D66's recipe, and D74 in `docs/decisions.md`.
- Gate: `just precommit`.

## Commits

1. Restore, carrier stamp, the `PostToolBatch` message; D36, D66.
2. Commit-path check, `bin/gitlore-compose`; D50.
3. `SessionStart`: no compose, position reports, rewritten tests; D31, D74.

## Mechanics

- `gitlore_compose_stamp` (`scripts/lib/index-sync.sh:150`) takes two files, and
  `scripts/add-tier.sh:75,358` calls it. Carriers make it N per active tier,
  keyed by tier; the batch stamp comparison in
  `scripts/cc-hooks/index-compose.sh` follows.
- `gitlore_detect_stale_merge_state` (`scripts/lib/resolve.sh:92`) says a tier
  holds a prepared merge.
- `gitlore_compose_write` needs a read-only form for the commit check.
- The dangling report in `session-start.sh` sits in compose's `else` arm; it
  runs unconditionally once compose goes.

## Position reports

| State | Today | Becomes |
|---|---|---|
| In sync | `gitlore: memory ready…` | unchanged |
| Memory behind remote | `gitlore: N upstream memory commits — run /gitlore:merge.` | `… — run /gitlore:merge: it fast-forwards, may record a canned commit, and needs no push.` |
| Memory diverged from remote | `… — run /gitlore:merge to reconcile it.` | `… — run /gitlore:push to reconcile and publish it.` |
| Tier behind remote | `… Run /gitlore:merge to take them, or /gitlore:push to take them and publish.` | `… Run /gitlore:merge to take them; it needs no push.` |
| Tier diverged from remote | `… Run /gitlore:merge to reconcile them, or /gitlore:push to reconcile and publish.` | `… Run /gitlore:push to reconcile and publish.` |

Unchanged: local `HEAD` behind `live` (`/gitlore:merge`), local `HEAD` diverged
from `live` (`/gitlore:resolve`; no push reconciles it), the rewrite-crossing
arms, the fetch failures and the uncommitted line.

## What follows from it

- **D66's recipe inverts.** It says "carrier first, since a carrier edit
  triggers no compose". A carrier edit now does, and restores the line. Root
  goes first, or both edits share one batch; a tier's last root line needs one
  batch, because root alone is adopted back.
- **A prepared merge has to stay quiet.** The merger edits the carrier, the
  stamp moves, and the pin rule would refuse on every batch. A tier with a
  prepared merge is left out of the carrier stamp.
- **A lost batch surfaces at commit.** An edit made outside a session (a human
  in an editor, a dead hook, a manifest edit in a terminal) has no compose until
  the next one, so the commit abort is its only catch. `bin/gitlore-compose` is
  its remedy.

## Settled

1. `bin/gitlore-compose` clears a pending compose when no batch will, and the
   commit abort names it.
2. `SessionStart` reports store diagnostics and writes no index: the rule
   problems (an unmounted manifest tier among them), a pending compose naming
   `gitlore-compose`, and dangling pointers. The diagnostics move nothing, so
   the pin check's put-back stays out of them. A mid-merge tier gets the pin
   loop's notice alone. A tier whose local `live` is ahead of its pin takes
   `/gitlore:merge`, not `gitlore-compose`: composing first dirties the tier and
   the take refuses.
3. Ahead of the remote stays silent.
