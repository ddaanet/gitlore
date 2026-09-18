---
name: merge
description: Take the memory facts other repos have published — each mounted tier's remote, then memory's own — without publishing anything of this repo's. Use when the user runs /gitlore:merge, asks to take, pull, sync or catch up on shared memory, or when a session start reported that a tier has upstream facts waiting. Not for publishing — that is /gitlore:push — and not a substitute for `git pull` of project code.
allowed-tools: ["Bash", "Skill"]
---

# gitlore:merge

You are taking published memory in, and sending nothing out.

A tier is checked out at the commit the memory tree records for it and nothing
advances it on its own, so facts another repo published sit on the tier's remote
until this runs. `/gitlore:push` also takes them, but only on its way to
publishing this repo's; this skill is the half that discloses nothing.

## Reconcile

```bash
bash "$(git config gitlore.mergeCommand)"
```

Exit codes:

- `0` — done. Relay the `gitlore:` lines verbatim: which stores moved and to
  what, which already held everything, and any trailing notice about
  uncommitted changes.
- Non-zero **with `gitlore: memory merge prepared` in the output** — a store
  diverged. Go to **Diverged** below.
- Non-zero **without** it — surface the output verbatim and stop. It names the
  cause (a tier with no remote configured, an unreachable host, uncommitted
  changes in a store) and the next action.

If the call is denied rather than failing, nothing has happened — no ref moved
and no merge was prepared. Hand the user the same command with a `!` prefix to
run themselves, and continue from its output.

## Diverged

This store and its remote each hold commits the other lacks, so taking the
remote is not a fast-forward and a merge is already prepared. This is an
ordinary outcome: resolving it runs a sub-agent that synthesizes memory content
and lands a merge commit.

1. Invoke the `gitlore:resolve` skill. The directive in the output above carries
   everything it needs — do not re-derive the store path or the state file.
2. When it finishes, **run the reconcile command again.** It handles one store
   at a time, and a second may still be behind. The *same* store returning the
   *same* prepared block is not a fresh divergence: a synthesized, staged merge
   is indistinguishable from an untouched one while `MERGE_HEAD` is set, so the
   merge is unlanded and gets continued again — never discarded.
3. Repeat until the command exits 0.

The landed merge is **not** published: the continuation stops after the local
fast-forward, which is what makes this different from `/gitlore:push`.

## Report

Say which stores took what. A tier take records its own bookkeeping commit —
the moved tier pointer and the recomposed root index — and leaves the memory
store clean; the run says so when it happens, and says when the pair was only
staged instead because the store held uncommitted work. Say plainly that
nothing was published, and that `/gitlore:push` is what puts this repo's own
facts on their remotes.

A tier whose arrival broke the index structure — a duplicate pointer, a welded
line, a non-bullet line inside the pointer block — is repaired by the take
itself: a commit on top of the arrival that restructures and adds no text. Relay
every `gitlore: repaired <tier>'s arrival:` line verbatim, each dropped line
included, then report the outcome the run names:

- The output ends that tier's line `; /gitlore:push publishes it.` — the repair
  is adopted. Say it is committed in the tier's local `live` and that
  `/gitlore:push` publishes it. Say that only when that line is there.
- The take rests because this repo's own index has problems. Relay the problems
  adoption waits on: they are this repo's to fix, nothing is published until
  they are, and `/gitlore:push` publishes the repair once they are fixed — the
  next take adopts it without repairing again.
- The repair cannot fix the arrival. Relay its problem lines and the remedy the
  run prints: `Once the index is fixed where it was published, run
  /gitlore:merge again.`, or, when the refusal also names this repo's own
  indexes, `Fix the problems listed above in this repo; once the index is fixed
  where it was published, run /gitlore:merge again.`

A repair that fails on its scratch directory, a read, the rewrite, the commit
build, the `live` advance or the checkout that follows it prints the refusal and
`Run /gitlore:merge again.` Relay that: the failure is transient and the next
take repairs from scratch.

## Correcting what arrived

Adopting a merged tier index into the root index is the run's work. Never
rebuild the root index's block for a tier from the tier's `MEMORY.md` by hand;
what a take leaves behind — a dirty memory store, the moved tier pointer and the
recomposed root index — rides the next memory commit.

Land upstream's lines first and author any correction to them as a later change
of this repo's own. A take that also rewords what it took is indistinguishable
from reverting what upstream just sent. Later is the next step, not permission
to skip it: taking upstream's version of an index settles the merge, not the
merits of every line in it, so a defect verified in an arrived line is a
follow-up change to make, not one to defer to a pass that may never come.

Dropping an arrived pointer can take two edits rather than one. The composition
drops a tier line from the carrier only when the root index carried that path at
`HEAD`; a path absent there reads as one nobody authored in root, so it stays in
the carrier and is reported. Whether an arrived path is at `HEAD` depends on
whether a commit has recorded the recomposed root index yet — a take on a clean
store commits its own bookkeeping, while a take on a dirty store and a landed
merge both leave that write for the next memory commit. So run
`git -C memory show HEAD:MEMORY.md` and look for the line before assuming one
pass suffices: present there, removing it from the root index is enough; absent
there, remove it from the tier's own `MEMORY.md` in the same change.
