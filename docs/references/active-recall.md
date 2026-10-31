# Active recall — decision D18

Why active recall is a skill the agent runs itself and not a hook that injects
the bodies: a fact whose trigger appears mid-task has no path into context under
the native classifier, and the two channels that could deliver it for the agent,
a hook's `additionalContext` and a denied write, each fail on a measured count.
Read it when changing `skills/recall/SKILL.md` or weighing a hook that would
serve memory bodies. The platform behaviours that make the agent's `Read` the
only route are measured here; the retrieval mechanism they sit against is in
[cc-memory-retrieval.md](cc-memory-retrieval.md).

- Recall — **D18** active recall is a skill the agent runs itself, with no hook
  and no state

---

**D18 — Active recall: a skill the agent runs itself, with no hook and no
state**

CC's native recall runs a per-query classifier against the **user prompt**,
returns at most five files it is certain about, and is instructed not to
re-select within a conversation. A fact whose trigger only appears *mid-task* —
a git rejection string, a `2>/dev/null` in a file just opened, an empty
`$TMPDIR` — therefore has no path into context. Closing that gap is FR16. At
2.1.258 the native path is additionally gated behind `tengu_moth_copse` or
`CLAUDE_MEMORY_STORES`, off by default, and delivers as a `relevant_memories`
attachment rather than a Read (`cc-memory-retrieval.md`); the gap is the same
either way.

**The whole mechanism is `skills/recall/SKILL.md`.** Three steps: decide from
the index already in context with **no tool calls**, select at most five
entries, then `Read` those bodies in a single batch. Nothing else — no request
file, no hook, no ledger, no reset. The skill is invoked by the user, by the
agent when it notices a trigger, or — the load-bearing case — by another skill
at a checkpoint it prescribes.

**Why the agent reads, rather than a hook reading for it.** No hook output field
can inject a `tool_use` or force a `Read` — verified against the shipped binary
(2.1.217), where `injectToolCall`/`requestTool`/`forceRead`/`forceToolUse` have
zero occurrences while `additionalContext` has 180. The choice is
hook-emits-*bytes* against hook-emits-a-*directive*, and bytes lose on two
measured counts. **Truncation:** a large `additionalContext` is not delivered
whole — at 15.6KB the harness wrote it to a
`tool-results/…-additionalContext.txt` file and inlined a ~2KB preview, while 57
of this store's 122 bodies exceed 2KB on their own (mean 3.2KB, largest 19KB),
so a five-entry fetch delivers a fraction of itself and leaves the agent chasing
a pointer. **Editability:** injected text does not register in the file-read
ledger, which is keyed off actual `Read` calls, so an `Edit` on a recalled
memory fails until the agent Reads it anyway — paying for the same body twice on
exactly the path that matters most, since a memory worth recalling mid-task is
often one about to be corrected. A `Read` costs a second round trip and has
neither problem.

**What that gives up: unconditional delivery.** Injected bytes arrived whether
the agent cooperated or not; a directive can be deferred, and mid-task — when
the agent is busy — is both when deferral is likely and the condition recall
exists for. **On non-compliance nothing arrives and nothing reports it.**
Accepted rather than mitigated: the machinery that bought unconditional delivery
(an IPC file, a validating resolver, a content-addressed ledger, two reset
events) was buying delivery of a truncated payload that still had to be re-read
before it could be edited. Detecting a skipped recall is a separate problem from
serving one, and gating the agent into the checkpoint is rejected below on its
own merits.

**Selection discipline is instruction, not enforcement.** The cap of five,
"unsure means no", "an empty selection is a real answer", and matching on what
the task is *about* rather than on keyword overlap are prose in the skill body,
adapted from the prompt CC gives its own memory-selection classifier — the same
judgement, over the same evidence, made by a subagent there and inline here. A
resolver could enforce the count and reject a bad path; it could never make the
selection good, which is the part that matters. No ledger either: the agent sees
its own context, and a body it already Read is visible in the transcript.

**Index as routing table.** The premise the skill rests on: an index line
carries the *trigger keywords* so read-or-skip can be decided from it, not the
fact itself. Always-on directives were moved out of `MEMORY.md` to `CLAUDE.md`
and path-scoped `.claude/rules/`, whose `paths:` frontmatter fires on reading a
matching file — native harness support for the same mid-task-trigger problem,
along the file-path dimension.

## Rejected alternatives

**Hook-side injection of the bodies**, from a request file the agent writes:
`.claude/gitlore-recall` listing up to five store-relative paths, a
`PostToolBatch` hook validating and resolving it, and a content-addressed ledger
so a body already in context was never sent twice. It delivers unconditionally,
which a directive cannot — but `additionalContext` spills past ~2KB into a
pointer file, and injected bytes never satisfy the `Read`-before-`Edit` ledger,
so the common case (recall a fact, then correct it) paid for the body twice and
the large case delivered a preview. The validation, the ledger and its two reset
events existed only to serve that channel; the selection judgement they
surrounded was always the agent's (D18).

**A `PreToolUse` deny on the first durable write of an episode,** forcing a
recall decision before the agent may write. Making a denial the *normal* control
flow spends a turn on every editing episode forever and trains the agent to read
denials as routine, corroding the channel that should mean stop. Arming it at
`UserPromptSubmit` is worse still: it duplicates the native classifier that
already fires there. The obligation lives in the calling skill's flow instead
(D18).
