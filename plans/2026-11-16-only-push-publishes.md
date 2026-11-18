# Only push publishes

My human partner's rule, 2026-11-16: only `/gitlore:push` publishes. A parent
`git push` counts as push (its `pre-push` hook runs the same
`gitlore_push_stores`). `/gitlore:merge` publishes nothing, as today.
`/gitlore:resolve` stops publishing: it repairs and lands, locally.

Facts and line references come from a reading of the tree
(`/tmp/claude/gitlore-splits/resolve-no-publish-orientation.md`, scratch). Any
site list or count in it, or below, is a query: each slice's red author greps
the whole tree for the pattern the slice replaces before relying on it.

Steps are contracts; this plan carries no code. Only the strings under
Interfaces are verbatim.

## What changes for a user

- `/gitlore:resolve` on a store that is only ahead of its remote sends nothing
  and says to run `/gitlore:push`. Today it publishes silently.
- A merge that lands, whoever prepared it, moves local `live` and stops. Today a
  merge prepared by a push or by resolve also pushes the merged store.
- A push that met a divergence is finished by pushing again.
- A remote that moves again during a synthesis is met by the next push, which
  prepares the next merge; today the continuation's refused push prepares it one
  step earlier.

## Interfaces

Lines a skill or the merger agent routes on, so they cross slice boundaries:

- After any landing, on stderr, exit 0:
  `gitlore: merged without publishing. Run /gitlore:push to publish.` The stable
  fragment is `gitlore: merged without publishing`, which the skills already
  quote.
- From the default resolve run, per store that is only ahead, exit 0:
  `gitlore: <store> is ahead of its remote. Run /gitlore:push to publish it.`
  `<store>` is `memory` or `tier '<name>'`, as the other reports name stores.

The script names `/gitlore:push` in every case. No skill text chooses a command
by who invoked it: a push skill reruns itself by its own step, and a user whose
`git push` was refused repeats it.

## Decision record

Edits follow `craft:design-doc-writing`: an inverted decision's text is deleted,
ids are never renumbered, the commit says why.

- New **D86**: only push publishes; resolve lands locally. Rejected by name:
  "resolve publishes what it lands" and "a no-publish mark on the merge state".
- **D75**: the clause that a tier merged inside a push publishes on landing is
  rewritten in place: the landing is local and the rerun push publishes it. Its
  rejected alternative "keeping a tier merge landed inside the pre-push hook
  unpublished" is deleted, since it is now what happens.
- **D76**, D46, D20, D49 and the D17 ordering paragraph: wording follows; the
  ordering argument stays only where `gitlore_push_stores` carries it.

## Remotes

Decided by my human partner, 2026-11-16: a missing remote is created at install
or by hand with git. Push publishes every module that has a remote and creates
none; resolve creates none either. No message directs the reader to add one: a
store without a remote is a decision, not a defect.

## Slices

Each slice is red (author), red review (another agent), green (a third), one
`just precommit`, one commit, one `/code-review medium`. Agents run only the
test files they touch. Scripts run in bats fixtures only, never on this
checkout.

0. **Probe the premise.** In a fixture: prepare a divergence from a push (a
   tier, then memory), land each merge with the origin push disabled, rerun the
   push path. Postcondition: `gitlore_push_stores` alone publishes the tier and
   then memory, with no resolve run in between. A failure stops the plan and
   comes back to my human partner. A fixture cannot stand for a real remote, so
   the first real divergence after release is the dogfood run.
1. **The default resolve run detects without pushing.** Precondition: any state
   the run accepts today. Postcondition: diverged stores get a prepared merge as
   today; a store only ahead gets the Interfaces line; exit status otherwise
   unchanged. Invariant: no remote ref moves during any `resolve.sh` default
   run. The gate code that existed only to order the pushes goes with them. If
   the red exceeds one test file's cap, the ahead-only report splits off as its
   own slice.
2. **The continuation never pushes, and the publish mark goes in the same
   pass.** Postcondition: every landing, either flavor, memory or tier, ends
   after the local `HEAD:live` move with the Interfaces line. Removed whole,
   following `craft:removing-cleanly`: the mark's writers and readers,
   `GITLORE_MERGE_NO_PUBLISH`, the tier exemption at the merge-preparation site
   (the other readers of `GITLORE_TAKE_IN_PUSH` stay), the remedy choice in
   `scripts/resolve.sh` and `scripts/lib/session-memory.sh` (a merge that cannot
   land names `/gitlore:resolve`), and the tests that pin the mark, deleted
   rather than turned into absence checks. A state file written before this
   slice that still carries the field gets no handling. The sweep covers the
   whole tree, and any count in the docs that the deletions change is
   re-derived.
3. **No script but install creates a remote.** The default resolve run no longer
   calls `create-remote.sh`. A store with no remote is my human partner's
   choice, not a missing part: resolve and push leave it local and say only that
   it stays local, naming no command, following `craft:directive-writing`. A
   wired remote that has no `live` yet gets its first `live` from
   `/gitlore:push`. Install's own failure messages keep naming install, and the
   one about a failed first push names `/gitlore:push`. The sites are a query:
   grep the tree for every message that sends a reader to `/gitlore:resolve` for
   a remote.
4. **Skill and agent text**, following `plugin-craft:skill-authoring`. The
   resolve skill's Loop loses its `/gitlore:merge` exception and its route on
   the landing line, since the bare rerun is safe everywhere; the skill ends by
   relaying the script's line. `turn-2-routes.md`, `unlanded-outcomes.md`, the
   push and merge skills and `agents/memory-merger.md` follow; the merger
   agent's remedy that no script emits is removed.
5. **Design docs.** D86, the D75 rewrite and the node edits above.
   `merge-and-resolve.md` is near its cap: if its edit does not shrink it, a
   verbatim split lands first as its own commit. `TODO.md` drops the no-publish
   residue and the tier notice lines.

Between 1 and 2 the system is consistent: resolve's own run publishes nothing,
and a merge prepared by a push still publishes on landing until 2.
