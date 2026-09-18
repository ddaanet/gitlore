## Brief: the SessionStart commit-protocol context cites a private id and names what it forbids

2026-09-17

Found while dogfooding `craft:directive-writing` in `ddaanet/craft`. Concerns
`protocol_ctx` in `scripts/cc-hooks/session-start.sh`.

Review-grade, not observed misbehaviour: the session that read it wrote no
memory, so nothing shows how an agent reacts to it. The design comment above the
string already settles the shape — prohibition plus one-line happy path, no
procedure — and these findings keep that shape.

### Findings

1. **`(FR11)` dangles in every consumer repo.** The context lands in repos that
   do not have gitlore's design doc, so the id resolves to nothing and reads as
   a citation the agent cannot follow. Drop it.
2. **The prohibition names the commands.** "do not run 'git -C <mempath>
   commit' or 'cd <mempath> && git commit'" spells out two command forms. A
   prohibition is warranted here — an agent reaches a submodule commit on its
   own — but it can forbid by role: "never commit inside the memory submodule".
   Naming forms also invites the agent to reason about the forms not named.
3. **Mechanism the agent cannot act on.** "guarded by a per-commit approval
   gate", "the submodule has a pre-commit hook that will block you", "records,
   gates, and pushes memory for you" describe the machinery. The acts are:
   don't commit in the submodule; write memory files as ordinary edits; commit
   the parent. "Committing the parent repo is all you need" is the reassurance
   worth keeping.
4. **Shouted emphasis.** `NEVER` and `PARENT` in capitals. The capitalised
   `PARENT` carries a distinction the sentence already makes; `NEVER` is fine as
   plain "never".

A possible cut: "gitlore: never commit inside the memory submodule. Writing a
memory file is an ordinary edit; committing this repo is all it needs."
