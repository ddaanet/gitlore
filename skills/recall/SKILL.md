---
name: recall
description: Fetch specific memory bodies into context on demand. Use when a tool result or a file surfaces a token the memory index has a line for — an error string, a flag, a git message, a symptom. Also use at a checkpoint another skill prescribes (after reading a task input, after exploring the code and before writing anything durable), and when the user asks to "recall", "check memory", or "what do we know about X". Not needed for facts already in this context.
---

# Active recall

Claude Code's own recall runs one classifier pass against the user's *prompt*,
returns at most five files, and is told not to re-select later in the
conversation. A fact whose trigger appears **mid-task** — a string in a tool
result, a flag in a file you just opened — therefore never arrives on its own.
This skill is how you go get it.

## 1. Decide from the index you already hold — no tool calls

`memory/MEMORY.md` loaded at session start and is in your context now. **Do not
Read it, do not grep it, do not run anything.** The one exception: if a
compaction has happened since it loaded, or it was edited this session, Read it
once first.

Each line is a routing entry — a title, a path, and the trigger keywords. You
decide from the line; the fact itself lives only in the file.

## 2. Select at most five

- Pick only entries you are **certain** will help with what you are doing right
  now, judged from the title and the hook text.
- **Unsure means no.** Be selective and discerning. Five is a ceiling, not a
  target — two precise entries beat five plausible ones.
- **Pick a trigger you have actually seen** — in a tool result, in a file, in the
  user's words — not an entry that merely sounds related to the topic.
- **Match on what the task is about, not on keyword overlap.** A project-state
  line describes an ongoing focus, not what every task is about: an entry
  mentioning "performance" is not relevant to a task that merely contains the
  word.
- **Do not re-select** a body already in this context, or one you pulled earlier
  in this conversation.
- **An empty selection is a real answer**, and a cheap one. Say so in a clause
  and carry on — the checkpoint exists to force a decision, not to manufacture a
  lookup.

## 3. Read them in one batch

Issue every Read in a **single message**, so the whole selection costs one round
trip. A path in the index is store-relative, so prefix it with `memory/`:
`- [T](ddaanet/foo.md)` is at `memory/ddaanet/foo.md`.

Then act on what you read.
