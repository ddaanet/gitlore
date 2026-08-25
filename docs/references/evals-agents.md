# Evaluating agents

Section 6 of the [evaluation best-practices reference](evals-best-practices.md).

---

## 6. Evaluating Agents and Multi-Turn / Tool-Use Workflows

**This is the hardest eval problem and the most important one. Standard
single-turn evals miss the majority of agent failure modes.**

### Why Single-Turn Evals Fall Short

Agents accumulate errors across steps. A correct intermediate tool call can
still represent bad planning; a wrong tool call can be recovered from.
Final-answer evals obscure *how* the agent succeeded or failed, making it
impossible to debug regressions.
[Yan](https://eugeneyan.com/writing/eval-process/) and
[Husain/Shankar](https://hamel.dev/blog/posts/evals-faq/) both emphasize that
outcome-only grading "masks recurrent inefficiencies and prevents understanding
of whether success came from systematic reasoning or by chance."

### Core Vocabulary (Anthropic)

[Anthropic](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
defines:

- **Task:** A single test with defined inputs and success criteria.
- **Trial:** One attempt at a task; run multiple trials per task due to
  non-determinism.
- **Transcript/Trace:** Complete record of all turns, tool calls, and
  intermediate reasoning.
- **Outcome:** Terminal environmental state (e.g., database row written, file
  created)—distinct from the agent's final user-facing message.
- **Grader:** Logic that scores performance; a task may have multiple graders.
- **Harness:** Infrastructure that runs tasks concurrently, records transcripts,
  grades, and aggregates.

### Trajectory vs. Outcome Evals

Both matter; use them together:

| Approach | What it catches | Limitation |
|----------|----------------|------------|
| **Outcome / state-based** | Whether the user's goal was ultimately met | Cannot distinguish lucky success from systematic reasoning; does not diagnose *why* failures occur |
| **Trajectory / step-level** | Wrong tool selection, bad parameter extraction, inefficient paths, hallucinated intermediate facts | More brittle; valid alternative paths may differ from the reference |

[Proxy State-Based Evaluation (arxiv 2602.16246)](https://arxiv.org/abs/2602.16246)
demonstrates a practical middle ground: an LLM infers a structured proxy state
from the full trace, then an LLM judge verifies goal completion against a
scenario specification—achieving >90% human agreement without requiring a
deterministic backend database.

The [TRACE framework (arxiv 2510.02837)](https://arxiv.org/abs/2510.02837)
introduces reference-free multi-dimensional trajectory evaluation using an
evidence bank built across sequential steps—applicable even when all valid
trajectories cannot be enumerated in advance.

### Evaluating Tool Calls

Deterministic assertions are the right tool where applicable:

- **Schema validation:** Did the agent call the tool with the correct argument
  types and required fields?
- **Parameter correctness:** Can you match extracted parameters against ground
  truth (e.g., extracted date vs. reference date)?
- **Tool selection accuracy:** Did the agent choose the right tool from the
  available set? Use exact-match on tool name; RAGAS provides
  [Tool Call Accuracy and Tool Call F1](https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/)
  metrics.

LLM judges are needed for cases where multiple valid tool-call sequences exist
or where argument quality is subjective.

[Anthropic](https://www.anthropic.com/research/building-effective-agents)
recommends testing tool call patterns exhaustively: "Run many example inputs in
our workbench to see what mistakes the model makes, and iterate." This mirrors
traditional API contract testing.

A tool call here is a dict like
`{"name": "send_email", "arguments": {"to": "...", "subject": "..."}}` extracted
from the transcript. Concrete assertions:

```python
from jsonschema import validate, ValidationError

def assert_tool_schema(call, schema):
    # Schema/parameter assertion: arguments conform to the tool's JSON schema.
    try:
        validate(instance=call["arguments"], schema=schema)
        return 1.0, "schema ok"
    except ValidationError as e:
        return 0.0, f"bad arguments: {e.message}"

def assert_tool_selection(transcript, expected_tool):
    # Tool-selection exact-match: was the expected tool called at all?
    called = [c["name"] for c in transcript["tool_calls"]]
    ok = expected_tool in called
    return float(ok), f"called={called} expected={expected_tool}"

def tool_call_f1(predicted_calls, gold_calls):
    # Set-based F1 over (name, frozenset(args.items())) tuples.
    def key(c): return (c["name"], frozenset(c["arguments"].items()))
    pred, gold = {key(c) for c in predicted_calls}, {key(c) for c in gold_calls}
    tp = len(pred & gold)
    precision = tp / len(pred) if pred else 0.0
    recall = tp / len(gold) if gold else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
    return f1
```

**Outcome assertion vs. trajectory assertion** — the difference matters:

```python
def outcome_assertion(env):
    # Grades terminal STATE. Path-agnostic: any sequence that ends correctly passes.
    row = env.db.query("SELECT status FROM orders WHERE id = 42")
    return float(row and row["status"] == "shipped"), "final state check"

def trajectory_assertion(transcript):
    # Grades the PATH. Catches process errors an outcome check would miss —
    # e.g. the agent charged the card before confirming inventory.
    steps = [c["name"] for c in transcript["tool_calls"]]
    if "charge_card" in steps and "check_inventory" in steps:
        if steps.index("charge_card") < steps.index("check_inventory"):
            return 0.0, "charged before checking inventory"
    return 1.0, "ordering ok"
```

An outcome assertion can pass on a trajectory that was correct only by luck; a
trajectory assertion can fail a path that nonetheless reached a valid end state.
Run both and report them separately.

### Multi-Turn State and Conversation Evals

Multi-turn evals require maintaining conversation state across turns and testing
context retention:

- **N-1 approach:** Provide the first N-1 conversation turns as context,
  evaluate turn N. This reproduces realistic conversation state without fully
  synthetic conversations.
- **Context utilization:** Measure whether later turns correctly reference
  earlier information using cosine similarity or LLM rubric grading
  ([Anthropic example](https://platform.claude.com/docs/en/docs/test-and-evaluate/develop-tests)).
- **Simulated users:** For conversational agents, use a second LLM to play the
  user role. This is necessary for automated multi-turn eval at scale.

### Debugging Agent Failures: Transition Failure Matrices

[Hamel Husain / Shreya Shankar](https://hamel.dev/blog/posts/evals-faq/)
recommend building **transition failure matrices**: a matrix showing the last
successful state vs. the first failure location across a batch of traces. This
reveals where in the pipeline failures concentrate, guiding targeted debugging
rather than system-wide tuning.

Worked example, 200 failing traces from a retrieval-then-synthesize agent
(rows = last successful step, columns = first failed step):

| last good \ first fail | retrieve | rank | synthesize | format | count |
|------------------------|:--------:|:----:|:----------:|:------:|:-----:|
| parse_query            | 18       | —    | —          | —      | 18    |
| retrieve               | —        | 71   | —          | —      | 71    |
| rank                   | —        | —    | 96         | —      | 96    |
| synthesize             | —        | —    | —          | 15     | 15    |

The 96 + 71 = 167 failures cluster at the `rank → synthesize` boundary:
retrieval works, but ranking surfaces the wrong context and synthesis runs on
it. Fix ranking first — it dominates. Formatting (15) is noise by comparison.

### pass@k and pass^k Metrics

Due to non-determinism, run multiple trials per task:

- **pass@k:** Probability that at least one of k trials succeeds. Use when one
  working solution is sufficient (e.g., code generation, research tasks).
- **pass^k:** Probability that all k trials succeed. Use for
  reliability-critical systems where every invocation must work
  ([Anthropic](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)).

Given `n` sampled trials of which `c` passed, the unbiased pass@k estimator from
the Codex paper
([Chen et al., "Evaluating Large Language Models Trained on Code", arXiv:2107.03374](https://arxiv.org/abs/2107.03374))
avoids the high variance of `1-(1-c/n)^k`:

```python
from math import comb

def pass_at_k(n, c, k):
    # Unbiased estimate of P(at least 1 of k trials passes), given c/n observed passes.
    if n - c < k:
        return 1.0
    return 1.0 - comb(n - c, k) / comb(n, k)

def pass_caret_k(n, c, k):
    # P(all k trials pass) under sampling-without-replacement from the n observed trials.
    if c < k:
        return 0.0
    return comb(c, k) / comb(n, k)
```

Judge-vs-human agreement should be reported as precision/recall, not raw
accuracy (misleading on imbalanced label sets):

```python
def judge_quality(judge_labels, human_labels):
    # Treat "fail" as the positive class — the failures are what you care about catching.
    tp = sum(j == "fail" and h == "fail" for j, h in zip(judge_labels, human_labels))
    fp = sum(j == "fail" and h == "pass" for j, h in zip(judge_labels, human_labels))
    fn = sum(j == "pass" and h == "fail" for j, h in zip(judge_labels, human_labels))
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    return {"precision": precision, "recall": recall}
```

### Grader Design for Agents

Avoid requiring a specific sequence of tool calls unless the sequence itself is
the requirement. Grade **outcomes** over **paths** wherever possible; otherwise
valid alternative approaches are incorrectly penalized. Combine:

1. Code-based outcome assertions (database state, file contents, return values)
2. LLM rubric graders for transcript quality (reasoning coherence, tool
   interaction patterns)
3. Safety checkers (guardrails against harmful intermediate actions)
