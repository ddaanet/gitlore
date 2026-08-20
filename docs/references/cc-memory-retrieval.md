# Claude Code auto-memory retrieval mechanism

Background research for tiered memory (design.md's D17, detailed in
`references/tiered-memory.md`'s D26). Source of the empirical claims cited
there and in the 2026-07-14 changelog entry ("Designed tiered global/org
memory"). The conclusions below are restated as settled fact in
`references/tiered-memory.md` (D26, and design.md's "Skill, not a gate"
section around FR16); this file keeps the underlying evidence trail.

## Method

Grounded first in the reverse-engineered system prompts in
`~/code/claude-code-system-prompts/system-prompts/` (ccVersion
~2.1.147–2.1.198), then confirmed empirically via sentinel-introspection
probes: `claude --print --settings autoMemoryDirectory=<scratch>` against
throwaway fixtures, and a real interactive tmux-PTY session (ccVersion
~2.1.209) cross-checked against the session's transcript JSONL.

## Findings

- A **separate per-query classifier** (`agent-prompt-determine-which-memory-files-to-attach.md`)
  is handed a manifest of `filename + description` pairs plus the live
  user query, and returns ≤5 filenames it is *certain* are relevant. Told
  to be conservative — especially with `user`/`project` memories (match on
  what the question IS ABOUT, not keyword overlap) — and not to re-select
  within a conversation.
- Selected files' contents are injected as `Contents of <path>`
  system-reminders. A distinct reminder template exists for non-root
  paths, so subdir files are attachable.
- A native two-tier structure exists in the shipped prompts: a `team/`
  subdirectory plus a combined index pointing at both `file.md` and
  `team/file.md` — Anthropic's own shared-memory surface. No
  arbitrary-depth traversal or `[[link]]`-following at retrieval is
  evidenced.
- `autoMemoryDirectory` is a single path; no public
  `teamMemoryDirectory`/multi-root key. Default when unset:
  `~/.claude/projects/<hash>/memory/`, project-scoped only.

**Resolved empirically (2026-07-14, `--print` sentinel probes):**
- Per-file attachment fires under `--print` and the body is surfaced
  (positive control 4/4).
- **Both** the `MEMORY.md` one-liner and the per-file frontmatter
  `description:` feed the classifier manifest — either lever independently
  drives selection (2/2 each).
- `team/` is enumerated (indexed file attached 4/4); depth ≥2 and
  index-less pure-frontmatter enumeration also work, less reliably
  (unindexed `team/sub/` file attached 3/4).
- Nothing bulk-loads bodies. Always-loaded footprint = the `MEMORY.md`
  index blob only.
- Retrieval reliability tracks whether the file is indexed in `MEMORY.md`:
  indexed files surfaced 100% (4/4), an unindexed subdir file 75% (3/4).

**Correction (same-day tools-disabled follow-up):** the `--print`
mechanism is front-agent tool-read, not background injection. With file
tools hard-disabled (`--disallowedTools`), body presence collapsed from
~100% to ~0% across every probe — presence is gated almost entirely on
tool availability, so bodies are fetched via a tool-gated `Read`, not
pushed through a passive channel that bypasses tools.

**Interactive confirmation (tmux PTY, CC v2.1.209):** same mechanism,
now pinned to an exact shape via transcript inspection:
- Auto-recall fires interactively and shows as "Recalled 1 memory" in the
  UI. The transcript shows this is exactly one `Read` tool_use with an
  empty thinking block — an automatic recall step issues a `Read` on the
  agent's behalf; "Recalled 1 memory" is the UI label for that
  recall-Read, distinct from a normal model-decided `Read(path)`.
- It's tool-gated: with tools disabled, the body never enters context
  across two turns (zero `Read` calls in the transcript), and the agent
  reports the index carries only one line per memory, no content.
- Bodies arrive as tool_results, not passive system-reminders — there is
  no separate invisible injection channel.
- The reliability gap has a clean cause: an indexed file gives recall a
  direct pointer to `Read` (100%); an unindexed/frontmatter-only file must
  be discovered by `Grep`/`Glob` first, also tool-gated, hence less
  reliable (75%).

**Design implication (D17):** a `MEMORY.md` pointer is what makes recall
reliable, so composing global/tier files into the always-loaded index is
the correct and mode-independent lever. Only the index is ever
always-loaded; bodies are pulled on demand via a tool-gated `Read`.
