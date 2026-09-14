# Classification: unadoptable tier arrival

Composite job (explicit bundling from the task brief). Requirements source: the
brief in `.claude/handoff-task.md`, agreed through `/ddaa:proof` on the
deliverable review of `plans/index-edit-propagation`.

## Item 1 — downstream repair merge (review Major 1, option C)

- **Classification:** Complex
- **Implementation certainty:** Low — the repair's git shape and its approval
  model are open forks
- **Requirement stability:** Moderate
- **Behavioral code check:** Yes — a new take branch, a repair preparation,
  continuation changes
- **Work type:** Production
- **Artifact destination:** production (`scripts/`), plus agentic-prose
  (`agents/memory-merger.md`, `skills/resolve`)
- **Evidence:** D6, D43, D49, D50; `gitlore-tier-merge-direction`; the take and
  continuation code

## Item 2 — commit-path prevention

- **Classification:** Moderate
- **Implementation certainty:** High
- **Requirement stability:** High
- **Behavioral code check:** Yes — a new branch in the compose rc 1 arm
- **Work type:** Production
- **Artifact destination:** production
- **Evidence:** D50 (the two refusals), the rc 2 arm as the shape to follow

## Item 3 — minor-pass-2 code m4

- **Classification:** Moderate
- **Implementation certainty:** Moderate
- **Requirement stability:** High
- **Behavioral code check:** Yes — a new `push_or_report` status and changed
  exit paths
- **Work type:** Production
- **Artifact destination:** production
- **Evidence:** `plans/index-edit-propagation/reports/minor-pass-2.md` code m4
