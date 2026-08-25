# 2026-07-14 — Designed tiered global/org memory (FR15 + D17)

Grounded in a retrieval-instrumentation study of CC auto-memory
(sentinel-introspection probes in both `--print` and a real interactive tmux-PTY
session against a scratch `autoMemoryDirectory`; captured in
`reference_cc_memory_retrieval_agentic`): only the root `MEMORY.md` is
always-loaded (a nested `team/MEMORY.md` is not); bodies are recalled on-demand
via a **tool-gated `Read`** steered by the root index; index-listed files recall
reliably (~100%) vs. unindexed (~75%). Design: shared tiers (`memory/lore`,
`memory/ddaanet`, …) are **nested submodules** reusing the existing framework;
routing is the **agent picking the directory** (guided by SessionStart
`additionalContext`, no content classifier); a **`PostToolUse(Write|Edit)`**
hook derives one-liner descriptions from frontmatter and recomposes the root
index (prefix-keyed blocks, global-first, disjoint from CC's project lines);
propagation via SessionStart ff of the nested submodule (leaving `memory/` dirty
— expected, rides the next parent commit); shared-index conflicts resolved by
`**/MEMORY.md merge=union` + recompose-dedup. Design only — not yet implemented
or planned. Added FR15 (capability) + D17 (mechanism), three Rejected
Alternatives (flat merge, content-classifier routing, append-only constraint).
No code change.
