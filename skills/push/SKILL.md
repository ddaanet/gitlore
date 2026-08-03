---
name: push
description: Publish committed gitlore memory and every mounted tier to their own remotes, without pushing the parent repo. Use when the user runs /gitlore:push, asks to push, publish, or share memory, or asks whether memory has reached its remote. Also use at the end of a session that committed memory but will make no parent push, so the facts do not stay local. Not for committing memory — that is the approved-summary path — and not a substitute for `git push` of project code.
allowed-tools: ["Bash", "Skill"]
---

# gitlore:push

You are publishing memory to its remote with no parent push.

Memory `live` advances locally on every memory commit, but nothing reaches the
memory remote until a `git push` of the parent runs its pre-push hook. A session
that commits memory and ends leaves every fact in the local clone only. This
skill closes that gap on its own.

There is no approval step here. FR11 gated this content when it was committed;
publishing an already-approved commit adds no disclosure decision.

## Publish

```bash
bash "$(git config gitlore.pushCommand)"
```

Exit codes:

- `0` — done. Relay the `gitlore:` lines verbatim: which stores moved, how many
  commits each published, any trailing notice about uncommitted changes, and —
  on a repo whose memory store is local-only — that memory has no remote of its
  own and stayed local while its tiers were published.
- Non-zero **with `gitlore: memory merge prepared` in the output** — a remote
  diverged. Go to **Diverged** below.
- Non-zero **without** it — surface the output verbatim and stop. It names the
  cause (a tier with no remote configured, unreachable host, a refusal git did
  not attribute to divergence) and the next action.

If the call is denied rather than failing, nothing has happened — no ref moved
and no merge was prepared. Hand the user the same command with a `!` prefix to
run themselves, and continue from its output.

## Diverged

Someone else published to this store since it was last fetched, so the push was
refused and a merge is already prepared. This is an ordinary outcome, not an
error, and it is the reason a push is not a fire-and-forget operation: resolving
it runs a sub-agent that synthesizes memory content and lands a merge commit.

1. Invoke the `gitlore:resolve` skill. The directive in the output above carries
   everything it needs — do not re-derive the store path or the state file.
2. When it finishes, **run the publish command again.** A remote-flavored merge
   publishes the store it merged, but a second store may still be unpublished:
   tiers push before memory, so memory can diverge after a tier has already
   landed, and resolve handles one store at a time.
3. Repeat until the command exits 0.

## Report

Say which stores are now published and to where. Name any store that is still
unpublished and why. If the run reported uncommitted changes, say plainly that
those facts are **not** on the remote and what would publish them — an approved
summary and a memory commit, then this skill again.

Do not run `git log`, `git status`, or `git -C memory rev-parse` to confirm the
outcome. The command's output is the authoritative report.
