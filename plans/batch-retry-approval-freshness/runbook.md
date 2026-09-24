# Runbook — batch-retry approval freshness

Design: `design.md` in this directory. Recall: `recall-artifact.md`.

| Requirement | Phase | Items | Notes |
|---|---|---|---|
| FR11 — approval covers what is committed, on the batch path | 1 | 1.1 | the defect |
| D16 — arg-driven entry point keeps `-m`/`-F` | 1 | 1.1/1 | bare mode is additive |
| docs current truth | 2 | 2.1 | prose, opus |

## Phase 1: the mtime gate on the batch path (type: tdd)

- Item 1.1: `scripts/commit-memory.sh`,
  `scripts/cc-hooks/memory-commit-batch.sh` — bare invocation commits on the
  approval on disk judged by freshness; the hook invokes it bare and picks its
  failure message by freshness. Requirements: FR11, D16. Slices:
  1. `tests/commit_memory.bats` — bare mode.
     `bare invocation commits on a fresh approval file and consumes it`: dirty
     memory, approval file written after the memory edit, `bash "$CMD"` with no
     operand exits 0, memory HEAD advances, `live` equals HEAD, the approval
     file is gone.
     `bare invocation refuses a stale approval file and leaves it`: dirty
     memory, approval file backdated with `touch -t 200001010000` (BSD-portable;
     mtime is second-granular and the compare is `>=`, so backdating is what
     makes it strictly older), exit 1, output+stderr contains
     `no approved commit summary` (the sync's refusal) and does not contain `-m`
     (the usage-era refusal — the discriminating negative), memory still dirty,
     HEAD unchanged, the approval file still present with its content unchanged.
     The existing `refuses dirty memory with no summary` test stays.
  2. `tests/cc_hook_memory_commit_batch.bats` — the hook.
     `a fix after an aborting index does not commit under the old approval`:
     welded line in root `MEMORY.md`, approval + trigger, first batch aborts (as
     the existing fix-needed test); then the test repairs the welded line by
     rewriting `MEMORY.md` (a write into the store, strictly newer: backdate the
     approval file first with `touch -t 200001010000` as the abort's restamp put
     it at now); second batch: exit 0, memory HEAD unchanged, both IPC files
     present, additionalContext contains `no longer covers` and the clause's
     `**<Kind>` template marker, and does not contain `retries by itself` (the
     deferred branch's own phrase — not `deferred`, which the new systemMessage
     also carries; slice 1's review found the same shape in its `-m` negative);
     systemMessage is
     `gitlore: memory commit deferred — the approved summary no longer covers the store, approval needed again`
     (exact); the test then rewrites the approval file and a third batch
     commits: HEAD advanced, both files gone. The existing locked-repo test
     (`a locked repo keeps both IPC files`) and fix-needed test stay green
     unchanged — they are the positive pairing: freshness `yes`, the `deferred`
     wording.
  Interfaces:
  - `commit-memory.sh` (no operand) — dirty memory: refuses with the existing
    "needs an approved summary" message when no approval file exists; otherwise
    leaves the file untouched and returns `gitlore_sync_memory_to_live`'s status
    (fresh commits, stale refuses).
  - `memory-commit-batch.sh` — runs
    `bash "$PLUGIN_ROOT/scripts/commit-memory.sh"` with no operand; on failure
    branches on `gitlore_commit_msg_freshness "$mempath"`: `yes` → the existing
    deferred pair with the reason; otherwise the re-approval pair from design.md
    §Design point 3, clause last, trigger unnamed.

## Phase 2: docs (type: general)

- Item 2.1: `docs/references/commit-gate.md` (the "Both IPC files are removed
  only on a complete commit" paragraph: the retry is judged by freshness, an
  agent write after the approval asks for it again),
  `docs/references/memory-entry-points.md` (D16: the bare mode and what it
  judges by), `docs/decisions.md` (one D56 line under the commit gate, the
  rejected list from design.md §Rejected appended to that group's *Rejected:*
  line), `docs/changelog/` entry named like its siblings, and the changelog
  index if siblings are indexed. Present tense, no narrative of the defect
  outside the changelog. `scripts/check-docs-links.py` must pass: every D56
  mention in decisions.md needs its argument in the node. Requirements: docs.
  Depends on: Item 1.1 Model: opus
