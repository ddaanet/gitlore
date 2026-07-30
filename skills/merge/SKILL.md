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
  cause (no remote configured, an unreachable host, uncommitted changes in a
  store) and the next action.

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
   at a time, and a second may still be behind.
3. Repeat until the command exits 0.

The landed merge is **not** published: the continuation stops after the local
fast-forward, which is what makes this different from `/gitlore:push`.

## Report

Say which stores took what. A tier fast-forward leaves the memory store dirty —
the moved tier pointer and the recomposed root index — and that is expected:
those ride the next memory commit. Say plainly that nothing was published, and
that `/gitlore:push` is what puts this repo's own facts on their remotes.
