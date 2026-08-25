# Automate post-mount memory triage on tier activation

## Problem

After mounting an existing tier with `/gitlore:add-tier`, the agent stops
without reconsidering the repo's existing memory. The user has to paste a manual
prompt:

> examine memory entries memory/*.md, decide for each one if it is
> project-specific (keep) or reusable across projects by a single user

Two coupled defects:

1. **No trigger.** Nothing prompts the triage; the user does it by hand every
   mount.
2. **Hardcoded scope dichotomy.** "project-specific vs reusable by a single
   user" bakes in *one tier's particular scope* as if it were the only axis.
   With a second tier mounted — or a tier whose scope is "shared with other
   people" or "one language's projects" — the binary is wrong. Triage is really
   N-way routing: each active tier self-describes a scope, and each local fact
   goes to the most-specific tier whose scope covers it, else stays local.

The scope data already exists and already travels: each tier carries its scope
in its `MEMORY.md` frontmatter `description:` (the routing guidance
`session-start.sh` advertises for active tiers). The gap is purely that nobody
tells the agent to sweep existing facts against it, and the manual prompt that
does assumes a two-scope world.

## Goals

- Fire the triage automatically at the moment a tier becomes usable, with no
  manual prompt.
- Generate the triage directive from the *live* active-tier scopes, never a
  fixed dichotomy — correct for two tiers, three, or a tier shared beyond one
  user, because the mechanism never assumes what the scopes are.
- Collapse the mount+activate round-trip from two agent turns to one.

## Non-goals

- **Re-routing facts already in a tier.** When a more-specific tier is added
  later, demoting/moving an already-promoted fact is a separate reconcile. No
  usage data motivates it; it is absent from this design until something asks
  for it. The sweep is local `memory/*.md` → up only.
- **Forcing the sweep.** The directive is a nudge (`additionalContext`); the
  agent runs the classification, a misfile self-corrects. Forcing an N-file
  classification on every mount is heavy-handed and off-pattern.
- **A new scope field.** Reuse the tier's frontmatter `description:`; it already
  means "what belongs here" and already travels to consumers.

## Design

Two changes, plus a helper refactor and the command doc.

### 1. Hook reorder — collapse mount+activate to one turn

`add-tier-batch.sh` currently runs **last** in the PostToolBatch chain, after
`index-compose.sh`:

```
index-sync-post → index-compose → memory-commit-batch → recall-batch → add-tier-batch
```

That ordering is why mount and activation cannot share a batch: if the agent
wrote the intent file **and** the manifest line in one turn, `index-compose`
would fire while the tier is still unmounted (`add-tier-batch` runs later) → it
sees a manifest entry for an absent module → refuses. The flow was forced into
"mount in turn 1, activate in turn 2."

Move `add-tier-batch` ahead of `index-compose`:

```
index-sync-post → add-tier-batch → index-compose → memory-commit-batch → recall-batch
```

Now one turn suffices: the agent writes the intent file **and** appends the tier
name to `.gitlore-tiers`; at end-of-batch `add-tier-batch` mounts, then
`index-compose` sees a now-mounted, now-listed tier and composes, then the
triage nudge (below) fires — all in one batch. The two-turn split was
incidental, not essential.

The reorder is safe for existing flows: hook position only matters when two
hooks fire in the *same* batch, which never happened for these two before. The
dormant-mount path still works — write the intent alone (no manifest line) to
mount without activating.

**Failure ergonomics shift (accepted).** A bad url / taken name in a one-turn
write leaves the manifest line pointing at an absent module, so `index-compose`
refuses (fail-safe, no clobber) in the same batch. The agent gets the
mount-failure *and* the compose-refusal together, fixes the intent, rewrites —
the stray manifest line is dormant and idempotent, and the retry heals it.
Two-turn surfaced the mount failure before the manifest was ever touched;
one-turn surfaces both at once. Recoverable, non-corrupting.

### 2. Triage nudge at the manifest-change trigger

`index-compose.sh` already keys on "did this batch touch the root index or the
manifest?" (a single `touched` flag, lines 29-36). Split it so the triage nudge
fires **only on a manifest change**, not on every memory-write recompose:

- Track `manifest_touched` separately from `index_touched`.
- After a successful compose (`compose_rc == 0`), if `manifest_touched` and
  there is at least one active tier with a resolvable scope, append a triage
  directive to the hook's `additionalContext` (`ctx`).

The directive enumerates each active tier and its self-described scope (via the
shared helper below) and instructs:

> For each fact in your local memory (bare-path `- [Title](file.md)` lines in
> the root `MEMORY.md`), judge which active tier's scope best covers it — using
> each tier's OWN scope, not a fixed rule. Route the best-fit ones up: `mv` the
> file into `memory/<tier>/`, and reprefix its root index line to
> `<tier>/<file>.md`. A fact no active tier's scope covers stays local. Do not
> move a fact already in a tier.

The triage moves land in a *subsequent* turn, which retriggers `index-sync`
(reprefixed line → frontmatter) and `index-compose` (mirror down). That turn
does not touch the manifest, so the triage nudge does not re-fire — no loop. The
moves ride the next FR11 commit.

**Why the manifest-change gate, not any compose:** `index-compose` fires on
every turn that writes memory. Gating triage on the manifest specifically means
it fires exactly when the active-tier set may have changed. Reorders (rare) also
trip it; a reorder-triggered sweep is a harmless no-op — the agent reads the
scopes, finds every local fact already correctly placed, moves nothing.
Detecting "added" vs "reordered" would need a manifest pre-image (a PreToolUse
capture); not worth it for a no-op case. Fire on any manifest touch.

### 3. Shared scope-resolution helper

`session-start.sh:242-261` already walks `gitlore_active_tiers`, guards
`[ -e "$tierpath/.git" ]`, reads `gitlore_get_frontmatter_description
"$tierpath/MEMORY.md"`, and builds a `- <path>/ — <desc>` list. Factor this into
a helper in `scripts/lib/` (e.g. `gitlore_active_tier_scopes MEMPATH` → the
enumerated lines). Have both `session-start.sh` and the triage path call it. One
definition of "active tiers and their scopes," tested once.

### 4. Command doc

`commands/add-tier.md` teaches a three-step two-turn flow (intent → activate →
report). Update to the one-turn default:

- To mount and use now: write the intent file **and** append the tier name to
  `memory/.gitlore-tiers` in the same turn.
- To mount dormant: write the intent alone; list it later.
- Note that a triage nudge follows activation, and the agent acts on it.

Remove the framing that treats activation as a mandatory separate turn; keep the
precedence/ordering guidance for the manifest edit.

## Components

| Unit | Change | Depends on |
|------|--------|-----------|
| `hooks/hooks.json` | move `add-tier-batch` before `index-compose` in PostToolBatch | — |
| `scripts/lib/*.sh` | new `gitlore_active_tier_scopes` helper | `gitlore_active_tiers`, `gitlore_get_frontmatter_description` |
| `scripts/cc-hooks/session-start.sh` | call the helper instead of the inline loop | the helper |
| `scripts/cc-hooks/index-compose.sh` | split `touched` → `manifest_touched`; emit triage directive on manifest change | the helper |
| `commands/add-tier.md` | one-turn flow + triage note | — |

## Testing

Encode in the bats suite (`tests/`), not hand-run:

- **Reorder invariant:** assert `add-tier-batch` precedes `index-compose` in
  `hooks/hooks.json` (a positional check, so a future edit can't silently
  reintroduce the two-turn bug).
- **Trigger gate:** a batch editing only the root index recomposes but emits
  **no** triage directive; a batch editing `.gitlore-tiers` emits one. (Break
  the manifest-gate and watch this go red — negative assertion must fail against
  the change it guards.)
- **Directive content:** with two active tiers of different scopes, the
  directive names **both** scopes and contains no hardcoded "project-specific /
  single user" dichotomy.
- **Helper:** `gitlore_active_tier_scopes` returns one line per active tier with
  its frontmatter description, skips dormant/unmounted tiers, and is
  whitespace-safe on a tier path containing a space.
- **One-turn happy path:** extend the `03-add-tier` eval (or add a sibling) so a
  single turn writes intent+manifest, the tier mounts and activates, and the
  triage directive surfaces — the invocation path, under the real hook chain.

## Open questions

None outstanding. Reorder-noise on a manifest reorder is accepted as a no-op;
re-routing existing tier facts is explicitly out of scope until usage motivates
it.
