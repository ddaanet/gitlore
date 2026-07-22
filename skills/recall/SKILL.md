---
name: recall
description: Fetch specific memory bodies into context on demand. Use when a tool result surfaces something you half-recognise but cannot act on — an unfamiliar error string, a flag, a git message, a symptom — and the memory index has a line that looks like it covers it. Also use at a checkpoint another skill prescribes (after reading a task input, after exploring the code and before writing anything durable), and when the user asks to "recall", "check memory", or "what do we know about X". Not needed for facts already in this context.
---

# Active recall

Claude Code's own recall runs once, against the user's prompt, and does not
re-select later in the conversation. So anything whose trigger appears
*mid-task* — a string in a tool result, a flag in a file you just opened — never
arrives on its own. This skill is how you go get it.

The index in `memory/MEMORY.md` is already in your context. It is a routing
table: each line carries the trigger keywords, not the fact. You decide from the
line; this skill fetches the body.

## Procedure

1. **Scan the index you already have.** Do not re-read `memory/MEMORY.md` — it
   was loaded at session start. Re-read it only if a compaction has happened
   since, or it was edited this session.

2. **Pick at most 5 entries** whose trigger you have actually *seen* — in a tool
   result, in a file, in the user's words. Not entries that merely sound
   related to the topic. Five is a ceiling, not a target; two precise entries
   beat five plausible ones.

3. **Write `.claude/gitlore-recall`** with one path per line, relative to the
   memory store:

   ```
   feedback_whitespace_safety.md
   ddaanet/reference_bats_bang_no_fail.md
   ```

   `memory/feedback_whitespace_safety.md` is accepted too.

   If nothing matches, write exactly:

   ```
   no match
   ```

   `no match` is a real answer and a cheap one. The point of the checkpoint is
   to force a decision, not to produce a lookup.

4. **Continue working.** A hook reads the files and puts their contents in your
   context before your next turn. **Do not Read the files yourself** — that
   duplicates the fetch and spends the context twice.

## If the request is refused

Nothing is read and the reason comes back. Fix and re-request:

- **Over 5 entries** — the list is not a selection. Reassess against what you
  have actually seen and retry with a shorter, more specific list. It is not
  truncated for you, because keeping the first five would hide that the
  selection was never made.
- **No such memory file** — check the path against the index; tier entries carry
  their directory prefix.
- **Mixed `no match` and paths** — it is one or the other.

## What you will get back

The bodies, inline, marked with their paths. Entries already in this context are
skipped and named — the hook tracks what has been read, including what Claude
Code's own recall pulled, so you never pay twice for the same body in one
session. That ledger is cleared at session start and before a compaction.
