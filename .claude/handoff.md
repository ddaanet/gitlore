# Handoff — 2026-05-23 10:41:30 +0000

Session: `9df0bd20-256d-4cbe-b942-fddde0f211b9`

## Current task

Verify the gitlore two-turn approval handshake via a live `/gitlore:resolve` dogfood, then execute Plan 04 Steps 4–7 (push `ddaanet/gitlore`, add marketplace entry, outer-loop dogfood, document install pathway).

## Open decisions

- How to verify the two-turn handshake before pushing: run a live `/gitlore:resolve` dogfood now against a manufactured divergence (this session already has the committed `gitlore:memory-merger` loaded, so it's verifiable here) vs. defer to the Step 6 outer-loop dogfood after pushing. User leaned "re-dogfood first, then push." The handshake is prompt-only and not bats-testable — a real-skill run is the only faithful check.
- Whether to commit the now-complete `docs/references/evals-best-practices.md` (uncommitted) before resuming Plan 04, or fold it into a later commit.
- GitHub-side cleanup of leftover dogfood remotes (`ddaanet/gitlore-dogfood-*`): fold into the Plan-02 leftover cleanup or leave to the user.

## Files touched
- `/Users/david/.claude/projects/-Users-david-code-gitlore/memory/feedback_no_handrun_tests.md`
- `/Users/david/code/gitlore/docs/references/evals-best-practices.md`
- `/Users/david/.claude/projects/-Users-david-code-gitlore/memory/feedback_verify_delegated_citations.md`
- `/Users/david/.claude/projects/-Users-david-code-gitlore/memory/MEMORY.md`
- `/Users/david/code/gitlore/.claude/handoff-task.md`

## Last user prompts

**after The handshake is a structural approval gate between three actors: the **user** (runs `/gitlore:resolve`), the **parent a**

> Delegate a sonnet agent to read up on "evals" best practices, and write a sourced reference document.

**after This is a self-contained research-and-write task — a good fit to delegate. I'll dispatch a Sonnet agent with web access **

> continue

**after Done. The reference doc is at `docs/references/evals-best-practices.md` — 9 sections (the agent/multi-turn section §6 is**

> I read that, it seems thin on operational material.

**after Dispatched to the same agent (it kept its sourcing context) with a prescriptive spec for eight concrete artifacts: a run**

> <task-notification>
> <task-id>a5774ac8396ba6ecf</task-id>
> <tool-use-id>toolu_01E8fXAddDsedLyNwH4LouBb</tool-use-id>
> <output-file>/tmp/claude-1000/-Users-david-code-gitlore/c236ff29-4849-43b1-b788-fff52f7ea482/tasks/a5774ac8396ba6ecf.output</output-file>
> <status>completed</status>
> <summary>Agent "Research evals, write sourced reference" completed</summary>
> <result>All artifacts validate. Revision complete.
>
> ## What I added
>
> **§5 (LLM-as-Judge)** — two ready-to-use judge prompt templates: (a) pointwise binary pass/fail with rubric, reason-then-discard, and JSON output; (b) pairwise A/B with a position-swap wrapper (`pairwise_judge`) that only declares a winner if it wins both orderings.
>
> **§6 (Agents)** —
> - Tool-call assertion code: `assert_tool_schema` (jsonschema), `assert_tool_selection` (exact-match), `tool_call_f1`.
> - Outcome assertion vs. trajectory assertion side-by-side, showing how each catches what the other misses.
> - A worked transition-failure-matrix (200 traces, real-looking numbers, with the read-off conclusion).
> - pass@k unbiased estimator + pass^k code, and `judge_quality` for judge precision/recall vs. human labels.
>
> **§7 (Operationalizing)** — a real GitHub Actions `evals.yml` (runs on PRs, uploads scores artifact) plus the `gate.py` script that fails the job if any metric drops &gt;2 pts vs. a committed `baseline.json`.
>
> **§10 (new Operational Cookbook)** —
> - 10.1 Dataset schema: 4-row JSONL with code-graded and judge-graded cases.
> - 10.2 ~55-line eval harness skeleton (grader registry, N-trial loop, pass^k aggregation, CLI).
> - 10.3 Error-analysis workflow with a concrete 6-tag failure taxonomy and saturation rule.
> - 10.4 Worked end-to-end multi-turn approval-gate example: adversarial dataset (no/ambiguous/rejected approval), the `grade_approval_gate` trajectory assertion that catches premature action, the pass^k≥5 reliability requirement, and a separate synthesis-quality judge rubric.
>
> **Correctness rules honored**
> - Did not touch the Sources section's existing entries or any inline citation/author names.
> - One new factual claim (pass@k unbiased estimator) is cited to the Codex paper, which I fetched and verified (title + Mark Chen et al. + repeated-sampling pass@k); added as Source #20.
> - Verified all Python logic (pass@k/pass^k, approval detection) and JSONL parsing runs correctly.
>
> **Length:** grew from ~332 to **688 lines**. Conceptual sections §1–§4 and §8 are unchanged.</result>
> <usage><total_tokens>93526</total_tokens><tool_uses>15</tool_uses><duration_ms>182250</duration_ms></usage>
> </task-notification>

**after Doc is now ~691 lines, substantially operational. Summary:**

> add word boundary and escape to approval
