# Codex native memory integration

Research brief, 2026-09-16. Recommendation for discussion, not an accepted
design decision or implementation plan. Local inspection: codex-cli 0.154.0.

Port gitlore as a shared memory store with a Codex adapter. Preserve native
Codex memory alongside it, and investigate a supported import bridge before
attempting tighter integration. A directory redirect equivalent to Claude's
`autoMemoryDirectory` is not established by the available evidence.

The requested CLAUDE.md, shared conventions, memory index, both design docs,
gitlore's decisions index, and relevant mechanism nodes informed this brief.

## The important difference

Claude's redirect makes the native authoring destination the gitlore store
([memory redirect](../docs/references/memory-redirect.md)). Codex documents
background generation from eligible idle chats into a local store under
`CODEX_HOME`. Its generated files are not the recommended editing surface. That
introduces a separate writer and a separate clock.
[Official memory documentation](https://learn.chatgpt.com/docs/customization/memories)

The configuration reference exposes generation and use controls, extraction and
consolidation models, and eligibility limits. It does not document an
independent memory-directory override. Changing `CODEX_HOME` would change the
home for more than memories, so it is not an equivalent project redirect.
[Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)

This session's actual native-memory instructions permit updates only after an
explicit user request, through append-only notes under
`extensions/ad_hoc/notes/`. They prohibit editing the generated memory files. A
plugin cannot override that instruction. Automatic learning capture into gitlore
therefore needs a host policy that permits it; packaging a skill does not supply
that permission. This research request makes no native-memory write.

## Mapping the five integration points

| Existing path | Proposed Codex integration | Fidelity |
| --- | --- | --- |
| In-session memory writes | A Codex memory-writing skill writes authorized durable facts into the existing gitlore store and runs its authoring checks. Explicit native-memory updates use the host's note interface. | Same gitlore outcome; different native authoring mechanism. |
| Handoff and precompact writes | Port the judgment skills and checkpoint contract. Complete authorized capture and the memory review gate before the requested transition. | Explicit boundaries are portable; automatic compaction is a separate case. |
| Harness recall from the user prompt | A prompt hook selects bounded candidates from the composed index and supplies paths or small excerpts. The agent reads the selected bodies. | Plugin-provided recall using native hooks; not proof of Codex's own selector reading gitlore. |
| Spontaneous agent search | Load a compact index and retrieval guidance at session start, then let the agent select and read bodies when a tool result exposes a trigger. | Closest match to the existing recall design. |
| Explicit recall skill | Publish a Codex recall skill using the same selection discipline and dynamically resolved store path. | Directly portable after removing Claude-specific assumptions. |

Codex supports explicit skill invocation through `$` mentions or `/skills`, and
implicit selection from skill descriptions. The recall body must not assert that
its index is already loaded unless the adapter ensured that.
[Skills documentation](https://learn.chatgpt.com/docs/build-skills)

## Proposed adapter

Keep the existing store, tier composition, approval policy and git entry points
authoritative. Extract host-specific invocation and messages behind adapters; do
not implement another memory commit/push engine. The public commit/push
discovery seam already exists in
[memory entry points](../docs/references/memory-entry-points.md).

Use `SessionStart` for initialization, bounded index loading and shared
conventions; `UserPromptSubmit` for prompt candidates; and `PostToolUse` for
change reconciliation. Codex supports these events and context injection.
`SessionStart(compact)` can restore context before an immediate continuation.
Hooks require trust. `apply_patch` has its own input shape despite accepting
Edit/Write matcher aliases. There is no documented `PostToolBatch` equivalent.
These are event adapters to implement and test, not a hooks.json rename.
[Hooks documentation](https://learn.chatgpt.com/docs/hooks)

For index reconciliation, prefer an idempotent operation over observed file
changes, serialized per store. If old/new snapshots remain necessary, key them
by the host's actual operation and agent identities; do not assume Claude's
batch boundaries. Retain the commit-path check as the final backstop.

Mandatory shared rules need an always-loaded surface. Materialize the small
applicable rules into AGENTS.md or inject their actual content at startup. Do
not assume Claude's `@file` imports work in AGENTS.md, and do not copy the whole
memory index into permanent instructions. Keep the memory-routing budget
separate from the conventions budget.

For prompt recall, start with deterministic candidate matching over existing
routing lines and let the agent make the semantic choice. That preserves the
no-model-in-the-hook approach, but sacrifices classifier-level semantic recall.
Evaluate that loss before adding a model selector with its extra latency and
failure modes. Preserve empty selections and avoid repeated body delivery. This
is a proposal; it does not change D18's current Claude implementation.

Keep native Codex recall enabled where desired. Prefer live repository evidence
for changing project facts, and current gitlore files for facts they own; native
memories remain useful discovery hints and historical evidence. Avoid
automatically copying every fact between stores: copies introduce conflicts,
deletion propagation and delayed reintroduction of obsolete facts.

## Compaction and handoff

Retain handoff's separation between durable learning and temporary task state.
Carry the current task, open decisions and remaining work through the
checkpoint, rather than turning every handoff into permanent memory.

`PreCompact` can stop compaction, but the documented contract does not give it a
foreground authoring turn; prompt/agent hook handlers are skipped. Do not
promise a last-second semantic flush on every automatic compaction. Use the
explicit precompact skill for that guarantee. Automatic boundaries can preserve
already-written state and reload a valid checkpoint; never reinject an old task
frame solely because a file exists.
[Hooks documentation](https://learn.chatgpt.com/docs/hooks)

For a client that owns the App Server connection, sequence checkpoint turn,
approval completion, `thread/compact/start`, completion events, then
continuation. App Server exposes compaction and its event lifecycle. This is an
optional client integration; a plugin inside an arbitrary stock client does not
thereby acquire control of that client's connection. Prefer this route to
porting tmux keystroke machinery when such control is available.
[App Server documentation](https://learn.chatgpt.com/docs/app-server)

## Deeper native integration: a concrete lead, not a dependency

The installed binary provides evidence of a possible import path:

- `codex features list` reports `external_agent_memory_import` as under
  development and disabled here; hooks, memories and plugins report stable.
- Its generated experimental App Server schema includes a `MEMORY` migration
  item and a `details.memory` string array in external-agent config imports.
- Embedded memory prompts describe the native memory workspace as a
  Codex-managed git repository, with extraction and consolidation stages.

These observations establish implementation surfaces, not a supported live mount
API. No import was invoked. The generated schema alone does not settle what its
strings identify, how imported facts are scoped, or how updates and deletions
propagate.

The next useful investigation is an isolated import conformance probe: discover
a synthetic gitlore source, import one uniquely identifiable fact, verify its
appearance in native recall, change it, and then delete it. Test two
repositories and a linked worktree. Establish whether detection honors the
redirect used by gitlore, including its launch-time-only configuration. Never
use the real native memory directory as this experiment's fixture.

If the interface supports repeatable imports and deletion, make a one-way,
explicitly authorized projection of selected gitlore facts into native memory.
Keep source identity and content hashes in adapter-owned metadata. If imports
are snapshots only, offer migration and describe the staleness boundary. Do not
advertise continuous synchronization.

For the reverse direction, native memories can supply candidates for a
deliberate gitlore curation pass. The agent checks evidence, chooses the tier,
and follows the existing authoring review gate. Do not commit the complete
personal native store into a project's remote.

## Recommendation and acceptance evidence

Ship the supported plugin integration first: shared store, Codex skills, native
lifecycle hooks, agentic recall, and explicit boundary capture. Keep native
background memory working independently. Investigate the import bridge as the
path toward tighter native participation, without making it necessary for
project memory correctness.

A full equivalent of FR14 remains unproven: Codex's own extraction and recall
would need a supported scoped external-store interface, or host changes that
route candidate writes through gitlore's approval and storage contract.

Before claiming parity, run real Codex sessions that prove each of the five
paths independently. In particular, test implicit recall without naming the
skill, a trigger visible only in tool output, explicit invocation, boundary
capture before a real compaction, changed/deleted facts after reload, hook trust
failures, and concurrent worktree isolation. Record actual reads and writes, not
only a plausible answer. The existing Claude-specific retrieval measurements
cannot establish Codex behavior.
