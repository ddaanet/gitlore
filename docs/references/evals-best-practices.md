# LLM Application and Agent Evaluation: Best Practices Reference

*Last updated: 2026-05-23. Sources fetched and verified during research.*

The reference spans four files. This one holds sections 1–4 (what evals are,
their types, datasets, metrics), section 8 (pitfalls) and section 9 (sources).
The rest:

- [LLM-as-judge](evals-llm-as-judge.md) — section 5.
- [Agents and multi-turn workflows](evals-agents.md) — section 6.
- [Operationalizing evals and the cookbook](evals-operations.md) — sections 7
  and 10.

Section numbers are stable across all four, so a citation by `§` resolves
without knowing which file holds it.

---

## 1. What Evals Are and Why They Matter

**Evals are structured, repeatable tests that measure whether an LLM system
meets defined success criteria.** They differ from traditional unit tests in two
important ways: (1) LLM outputs are probabilistic and often open-ended, so there
is rarely a single "correct" answer to compare against; (2) the failure surface
is effectively infinite, and failures are often subtle degradations in quality
rather than binary crashes.

Traditional software tests verify deterministic logic. An LLM application can
pass every rule-based test while silently regressing on tone, factual accuracy,
or instruction following. Evals bridge this gap by combining code-based
assertions, model-graded rubrics, and human review into a repeatable quality
gate.

According to
[Anthropic's agent eval guide](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents),
"evals make problems and behavioral changes visible before they affect users,
and their value compounds over the lifecycle of an agent."
[Hamel Husain](https://hamel.dev/blog/posts/evals/) frames it as an iteration
flywheel: "If you streamline your evaluation process, all other activities
become easy." [Eugene Yan](https://eugeneyan.com/writing/eval-process/) argues
that the discipline of eval-driven development—defining success criteria before
building—is the differentiator between teams that ship reliable AI products and
those that iterate by intuition.

---

## 2. Types of Evals

### Offline vs. Online

| Mode | When | Purpose |
|------|------|---------|
| **Offline** | During development, in CI | Catch regressions before deployment; run on curated datasets |
| **Online** | In production, async on sampled traffic | Detect drift, novel failure modes, real-world distribution shift |

Offline evaluation functions like unit and integration tests. Online evaluation
catches what offline misses: gradual quality drift, schema contract drift in
tool outputs, and distribution shift as user behavior evolves. Both are
necessary; neither alone is sufficient. The
[Braintrust evaluation guide](https://www.braintrust.dev/articles/llm-evaluation-guide)
notes: "A system that scored 0.82 in March may be scoring 0.71 in June—and
nobody knows, because nobody is measuring it continuously."

### Grader Categories

[Anthropic](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
defines three grader types:

- **Code-based:** String matching, regex, schema validation, binary assertions,
  unit test execution. Fast, cheap, fully reproducible. Brittle to valid output
  variations and insufficient for nuanced quality.
- **Model-based (LLM-as-judge):** Rubric scoring, pairwise ranking, binary
  pass/fail by a judge LLM. Flexible and scalable, but non-deterministic,
  potentially biased, and requires calibration against human labels.
- **Human:** Subject-matter expert review, crowdsourcing, A/B testing. Gold
  standard quality, but expensive and slow. Reserve for calibration and
  high-stakes decisions.

[Anthropic's develop-tests docs](https://platform.claude.com/docs/en/docs/test-and-evaluate/develop-tests)
recommend preferring automation: "More questions with slightly lower signal
automated grading is better than fewer questions with high-quality human
hand-graded evals."

### Production A/B and Monitoring

After sufficient offline confidence, A/B testing exposes two system variants to
real users and measures downstream business metrics (task completion, user
satisfaction, retention). This is the highest-fidelity signal but also the
highest-cost and latest-stage check. Use it to validate, not discover,
improvements. [Hamel Husain](https://hamel.dev/blog/posts/evals/) notes A/B
testing is appropriate only "after sufficient confidence in product maturity."

---

## 3. Building Eval Datasets

**Build datasets from real failures first, not hypothetical ones.** The most
durable eval sets are grounded in actual production traces.

### Golden / Reference Sets

A golden set is a curated collection of (input, expected-output) pairs used as a
stable regression baseline.
[Braintrust](https://www.braintrust.dev/articles/llm-evaluation-guide)
recommends starting with 25–50 cases covering core functionality, then
expanding. Cases should represent:

- Happy-path scenarios
- Edge cases and adversarial inputs
- Off-topic or malformed requests
- Known past failures (add every production failure immediately after fixing it)

[Anthropic](https://platform.claude.com/docs/en/docs/test-and-evaluate/develop-tests)
suggests using Claude itself to generate additional test cases from a baseline
set to scale coverage cheaply.

### Sourcing from Real Traffic

Real user queries reveal patterns synthetic data misses. Log traces
comprehensively ([LangSmith](https://smith.langchain.com/) and similar tools
auto-log these). Then apply error analysis: review 100+ traces per cycle,
categorize failures using open coding → axial coding → taxonomy refinement, and
stop when ~20 new traces reveal no new failure mode
([Hamel Husain / Shreya Shankar FAQ](https://hamel.dev/blog/posts/evals-faq/)).

### Dataset Sizing

- **Minimum viable CI gate:** 100+ examples covering core features and known
  edge cases.
- **Error analysis target:** 100 traces per review cycle (every 2–4 weeks in
  active development).
- **Ongoing monitoring:** 10–20 traces weekly between major analyses.
- **Stop criterion:** Theoretical saturation—no new failure categories in ~20
  consecutive traces.

### Avoiding Leakage and Contamination

Benchmark contamination—eval data appearing in training corpora—inflates scores
and destroys the validity of comparisons.
[Research on benchmark contamination](https://arxiv.org/abs/2502.00678) shows
estimated contamination rates of 1–45% across popular public benchmarks.
Mitigations:

- Keep held-out test sets private; publish only validation splits.
- Track whether your eval data was ever included in fine-tuning datasets.
- For product evals, this is usually controllable: never fine-tune on raw eval
  examples.
- Version eval datasets alongside code so dataset changes are auditable.

### Criteria Drift

[Shankar et al. (UIST 2024)](https://arxiv.org/abs/2404.12272) document a
"criteria drift" phenomenon: evaluation criteria cannot be fully predetermined
because the act of grading outputs reveals what quality actually means in
practice. Their EvalGen system addresses this through mixed-initiative human–LLM
collaboration, where humans grade a sample and the system selects automated
evaluator implementations that best match those judgments. The implication:
treat your eval rubrics as living artifacts requiring iterative refinement, not
one-time specifications.

---

## 4. Metrics

**Match the metric to the task.** Generic metrics (accuracy, BLEU) are rarely
the right choice for production LLM systems.

### Task-Specific Correctness

| Task | Recommended Metrics |
|------|---------------------|
| Classification / extraction | Recall and precision *separately* (not combined F1 blindly); ROC-AUC / PR-AUC for probability outputs |
| Summarization | NLI-based factual consistency (finetune on task data with 1,000+ samples); reward models for relevance; direct length validation |
| Translation | chrF (language-independent, no tokenization); COMET / BLEURT (learned); reference-free COMETKiwi |
| Code generation | Test pass rate (unit tests); sandboxed execution correctness |
| Instruction following | Exact match on constrained outputs; binary compliance checks |

Source:
[Eugene Yan, "Task-Specific LLM Evals that Do & Don't Work"](https://eugeneyan.com/writing/evals/).

BLEU and ROUGE rank poorly in recent WMT workshops
([Yan](https://eugeneyan.com/writing/evals/)). BERTScore shows "unreliable
distribution separation" for summarization tasks. Use them only when you lack
task-specific data.

### Faithfulness / Groundedness

For RAG systems, the core failure mode is hallucination—generating claims not
supported by retrieved context.
[RAGAS](https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/)
defines:

- **Faithfulness:** Does the response contain only claims supported by the
  retrieved context?
- **Context Precision:** Of retrieved documents, how many are relevant?
- **Context Recall:** Of all relevant documents in the knowledge base, how many
  were retrieved?
- **Response Relevancy:** Does the answer address the query?

Retrieval metrics (Context Precision/Recall) use standard information retrieval
metrics. Faithfulness requires claim-level decomposition followed by NLI
verification against source passages.
[Eugene Yan](https://eugeneyan.com/writing/evals/) notes a "typical factual
inconsistency rate of 5–10% even after RAG grounding," setting a realistic
baseline.

### When Accuracy Is the Wrong Metric

Accuracy collapses important distinctions. A classifier with 95% accuracy on an
imbalanced dataset (5% positives) can be wrong on every positive. Track recall
and precision separately. When the cost of false negatives differs from false
positives (e.g., safety violations vs. over-refusals), calibrate thresholds
explicitly rather than optimizing a single aggregate score.

For user-facing quality (tone, helpfulness), accuracy over a binary rubric is
insufficient—use distributions, confidence intervals, and human calibration
samples.

---

## 8. Common Pitfalls and Anti-Patterns

| Anti-pattern | Why it fails | Remedy |
|--------------|-------------|--------|
| **Grading only the final answer for agents** | Multi-step regressions hide in intermediate steps | Add trajectory/span-level graders; use transition failure matrices |
| **100% pass rate on evals** | Evals are not challenging enough; system is overfitted to the test set | A 70–80% pass rate on meaningful evals is healthier than 100% on trivial ones ([Hamel Husain](https://hamel.dev/blog/posts/evals-faq/)) |
| **Generic off-the-shelf metrics (BLEU, ROUGE, BERTScore)** | Poor distribution separation; don't correlate with real quality for most tasks | Use task-specific metrics; finetune NLI models on task data |
| **Evaluating failures you imagined, not failures you observed** | Wastes effort on metrics that don't reflect actual failure modes | Start with error analysis on 100+ real traces; write evaluators only for discovered failures |
| **Skipping human calibration** | LLM judges without ground truth will drift unpredictably | Maintain a calibration set of 100+ human-labeled examples; recalibrate whenever rubric or model changes |
| **Criteria drift: treating rubrics as fixed** | Quality criteria evolve as the system and user expectations mature; stale rubrics measure the wrong thing | Treat eval rubrics as living artifacts; re-validate against fresh human labels periodically |
| **Shared state between eval trials** | Correlated failures mask real pass rates | Isolate trials; reset environments between tasks |
| **Using the same model for generation and judging** | Self-preference bias inflates scores | Use a different model family as judge; validate against human labels |
| **Outsourcing error analysis to external annotators** | Loss of domain context leads to superficial labeling; breaks the feedback loop between observation and product improvement | Build internal annotation capability; use custom tools over generic platforms |
| **Eval data leakage into training** | Contaminates benchmark validity | Never fine-tune on raw eval examples; version datasets separately |
| **Optimizing a single aggregate score** | Trade-offs between precision/recall, safety/helpfulness are obscured | Track multiple metrics; examine distributions, not just means |
| **No online eval** | Offline evals miss distribution shift and drift | Run async production evaluation on sampled traffic; alert on threshold crossings |

---

## 9. Sources

1. [Anthropic — Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
   — Anthropic Engineering, 2024
2. [Anthropic — Define Success Criteria and Build Evaluations](https://platform.claude.com/docs/en/docs/test-and-evaluate/develop-tests)
   — Anthropic API Docs
3. [Anthropic — Building Effective AI Agents](https://www.anthropic.com/research/building-effective-agents)
   — Anthropic Research, Dec 2024
4. [Hamel Husain — Your AI Product Needs Evals](https://hamel.dev/blog/posts/evals/)
   — Hamel Husain's blog
5. [Hamel Husain — Using LLM-as-a-Judge For Evaluation: A Complete Guide](https://hamel.dev/blog/posts/llm-judge/)
   — Hamel Husain's blog
6. [Hamel Husain & Shreya Shankar — LLM Evals: Everything You Need to Know](https://hamel.dev/blog/posts/evals-faq/)
   — Hamel Husain's blog, Jan 2026
7. [Eugene Yan — Task-Specific LLM Evals that Do & Don't Work](https://eugeneyan.com/writing/evals/)
   — Eugene Yan's blog
8. [Eugene Yan — An LLM-as-Judge Won't Save The Product—Fixing Your Process Will](https://eugeneyan.com/writing/eval-process/)
   — Eugene Yan's blog
9. [Shreya Shankar et al. — Who Validates the Validators? Aligning LLM-Assisted Evaluation of LLM Outputs with Human Preferences](https://arxiv.org/abs/2404.12272)
   — UIST 2024
10. [OpenAI — Evaluation Best Practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices)
    — OpenAI API Docs
11. [Braintrust — What Is LLM Evaluation? A Practical Guide](https://www.braintrust.dev/articles/llm-evaluation-guide)
    — Braintrust
12. [RAGAS — Available Metrics](https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/)
    — Ragas Docs
13. [Hong et al. — RULERS: Locked Rubrics and Evidence-Anchored Scoring for Robust LLM Evaluation](https://arxiv.org/abs/2601.08654)
    — arXiv, Jan 2026
14. [Wataoka et al. — Self-Preference Bias in LLM-as-a-Judge](https://arxiv.org/abs/2410.21819)
    — arXiv, 2024
15. [Xu et al. — Am I More Pointwise or Pairwise? Revealing Position Bias in Rubric-Based LLM-as-a-Judge](https://arxiv.org/abs/2602.02219)
    — arXiv, Feb 2026
16. [Siro et al. — Learning to Judge: LLMs Designing and Applying Evaluation Rubrics](https://arxiv.org/abs/2602.08672)
    — arXiv, Feb 2026 (EACL 2026 Findings)
17. [Chuang et al. — Toward Scalable Verifiable Reward: Proxy State-Based Evaluation for Multi-turn Tool-Calling LLM Agents](https://arxiv.org/abs/2602.16246)
    — arXiv, Feb 2026
18. [Kim et al. — Beyond the Final Answer: Evaluating the Reasoning Trajectories of Tool-Augmented Agents (TRACE)](https://arxiv.org/abs/2510.02837)
    — arXiv, Oct 2025
19. [How Contaminated Is Your Benchmark? Quantifying Dataset Leakage in LLMs with Kernel Divergence](https://arxiv.org/abs/2502.00678)
    — arXiv, Feb 2025
20. [Chen et al. — Evaluating Large Language Models Trained on Code (Codex; source of the pass@k unbiased estimator)](https://arxiv.org/abs/2107.03374)
    — arXiv, Jul 2021
