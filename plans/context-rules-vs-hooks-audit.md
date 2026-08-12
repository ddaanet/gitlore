# Always-on rules vs. mechanical enforcement

An audit of every prohibition in gitlore's always-on context against what the
harness already enforces, classifying each as **already enforced** (delete the
prose), **convertible** (build a hook, then delete the prose), or **judgement**
(prose is the only possible carrier).

Prompted by a session where a one-line index edit drew three verification calls
before the edit. The caution was pattern-matched off the prohibition layer, not
reasoned from the task.

## Enforcement that already exists

| Layer | Scope |
| --- | --- |
| `scripts/git-hooks/memory-pre-commit` | Hard gate (FR11): blocks any memory commit without `GITLORE_MEMORY_COMMIT`. A naked `git -C <mempath> commit` cannot succeed. |
| `scripts/git-hooks/pre-commit` | Records, gates and pushes memory into the parent commit. |
| `scripts/git-hooks/pre-push` | Memory/parent lockstep. |
| gitmoji `commit-msg` | Rewrites conventional-commit prefixes to emoji. |
| `.claude/settings.json` → `plugin-dev/version-guard.sh` | PreToolUse `Write\|Edit`: refuses edits changing `plugin.json`'s `.version`. Manifest only — **not** the vendored subtree. |
| `hooks/hooks.json` | SessionStart (task frame, nudge-reset), PreCompact, PreToolUse `Write\|Edit\|Bash` (index-sync-pre), PostToolUse Bash + worktree drift, PostToolBatch ×5 (index sync, tier compose, memory commit, plugin upgrade), WorktreeRemove. |

All of it is memory/index/release machinery. **No hook currently guards a single
behavioural prohibition** — not branching, not `--no-verify`, not cross-repo
writes, not `AskUserQuestion`.

## Class A — already enforced, prose is redundant

**`CLAUDE.md`: "Never `git commit` inside `memory/` or a tier."** Stated three
times: this paragraph, the SessionStart hook injection ("NEVER commit inside the
memory submodule directly — do not run…"), and `memory-pre-commit`, which makes
it mechanically impossible. Two of the three are pure standing cost.

*Proposal:* keep the SessionStart injection (it also carries the positive path —
that committing the parent is all you need), delete the `CLAUDE.md` paragraph's
prohibition half, keep its lockstep and handoff sentences.

**`shared-claude.md`: "Commit `memory/` with the code, never `.gitignore` it."**
`pre-commit` does this unconditionally. Delete.

**`CLAUDE.md`: "Conventional-commit prefixes are required."** The commit-msg hook
is a hard gate, not merely a rewriter: a missing, malformed or unknown prefix
exits 1 with the expected grammar and the full list of valid prefixes on stderr.
Reduce to the exception the gate does not state.

### Executed

All three deleted. What survives is what no gate emits: `memory-pre-commit`
prints the summary format, the file to write it to and the approval protocol,
but says nothing about the prefix — so "a memory approval summary takes none"
stays, and carries the don't-prepare-it-in-advance rule with it.

## Class B — convertible: not gitlore's work

Seven rules are mechanically interceptable and become PreToolUse hooks in the
`prohibitions@ddaanet` plugin. **That repo owns the list, the matchers and the
deny/ask decisions** — see `/Users/david/code/prohibitions/brief-prohibitions-plugin-bootstrap.md`.
Deliberately not restated here: a second copy would rot the first time that repo
revises a decision, and nothing writes back.

Gitlore's only stake in Class B is the ordering constraint below — the prose
cannot come out of `shared-claude.md` until those hooks exist and are verified.

## Class C — judgement, prose only

Roughly two thirds of `shared-claude.md` has no mechanical trigger and must stay:
the whole of *Working with my human partner*, *Deciding and planning*, *Tests*,
*Code*, most of *Dispatch*, and *A brief's recommendation is input, not a
decision*. Same for `CLAUDE.md`'s design, writing and testing sections.

Notably **"don't prepare the memory approval summary in advance"** must stay
prose. It prohibits unprompted proactive work, and there is no tool call to
intercept — the failure is work the agent does *instead of* triggering the gate.

## What this actually buys

Class A + Class B removes on the order of 25–30 lines from `shared-claude.md` and
`CLAUDE.md` combined — real, but it will not transform the file, because Class C
is the bulk. The larger effect is qualitative: every remaining line becomes a
judgement rule rather than a tripwire, so the file stops reading as a minefield
and starts reading as guidance.

The governing principle is already in the tier — *a gate that emits its own
instructions is invoked, not pre-satisfied*. Its precondition is that the gate be
cheap, reversible and self-describing, which every Class B candidate satisfies:
the agent proposes, the hook blocks, the block teaches, the agent complies. One
call, paid only when the situation arises, instead of standing context paid by
every session in every ddaanet repo.

## Constraints on execution

- `shared-claude.md` is the shared tier: deletions land in every ddaanet repo.
  The hooks must exist and be verified **before** any prose comes out, or the
  window between removal and enforcement is unguarded across all of them.
- The hooks live in the **`prohibitions@ddaanet`** plugin, not in gitlore's
  `hooks/hooks.json` — gitlore ships to consumers of the gitlore plugin, which is
  not the same population as ddaanet tier mounters.
- **The plugin and the tier are independently installed, and nothing couples
  them.** The tier mounts through gitlore; the plugin installs through the
  marketplace. Once the prose leaves `shared-claude.md`, a repo that mounts the
  tier without enabling the plugin is not briefly unguarded but permanently so,
  with no visible symptom. Mitigate in gitlore's SessionStart: when the ddaanet
  tier is mounted and `prohibitions@ddaanet` is absent from `enabledPlugins`,
  warn. Keeping the prose as a fallback is the alternative, and forfeits the
  entire benefit.
- Per `guardrail-must-permit-real-commands`, each guard must be verified with a
  command the system genuinely issues, **expecting ALLOW** — the branching and
  `--no-verify` matchers are the ones most likely to over-match.
