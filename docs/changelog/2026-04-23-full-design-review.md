# 2026-04-23

Full design review. Added FRs for install-time disclosure, per-commit review
gate, coexistence, and recovery. Added NFRs for graceful degradation and
overrides. Removed `gitlore.memoryPath` in favour of `.gitmodules` as canonical
path source. Corrected commit-message file path to use
`git rev-parse --git-path`. Rewrote Branch Model to specify parent-branch-name
rule, detached-HEAD mirror, rename handling, and collision with reserved `live`.
Agent-driven commit flow replaces user-driven. `/gitlore:resolve` now covers
both branch-vs-live and local-vs-remote divergence, with sub-agent synthesis
under `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Added D9 for the sub-agent
decision. Install is git-atomic (non-empty initial commit). Hook wrappers
gracefully degrade when `gitlore.hooksDir` is unset. Hook stderr branches on
`$CLAUDECODE` for agent vs user targeting. Remote creation inherits parent
visibility. Expanded Rejected Alternatives with new entries discovered during
review.
