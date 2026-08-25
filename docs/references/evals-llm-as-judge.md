# LLM-as-judge

Section 5 of the [evaluation best-practices reference](evals-best-practices.md).

---

## 5. LLM-as-Judge

**LLM-as-judge scales model-graded evaluation across volumes that human review
cannot cover, but requires careful rubric design and ongoing calibration to be
trustworthy.**

### When to Use It

Use LLM judges for criteria that are:

- Too nuanced for regex/code checks (tone, coherence, helpfulness)
- Too expensive to grade with humans at scale
- Well-defined enough that a rubric can be written down

[Anthropic's eval docs](https://platform.claude.com/docs/en/docs/test-and-evaluate/develop-tests)
advise: "If you don't know what a passing answer looks like, an LLM judge won't
either." Build the rubric first; validate it against human-labeled examples
before deploying at scale.

### Rubric Design

- **Binary (pass/fail) over Likert scales.**
  [Hamel Husain](https://hamel.dev/blog/posts/llm-judge/) argues binary labels
  force clearer thinking and reduce annotator inconsistency. Middle-ground
  ratings on 1–5 scales hide uncertainty.
- **Be specific and empirical.** "The answer should always cite a source from
  the provided context in the first sentence. If it does not, grade as
  'incorrect'." Avoid vague criteria like "helpful."
- **Encourage chain-of-thought before scoring.**
  [Anthropic](https://platform.claude.com/docs/en/docs/test-and-evaluate/develop-tests):
  "Ask the LLM to think first before deciding an evaluation score, then discard
  the reasoning." This improves performance on complex judgements.
- **Evidence-anchoring.** The
  [RULERS framework (Hong et al., 2026)](https://arxiv.org/abs/2601.08654)
  demonstrates that "locked rubrics" compiled into versioned immutable bundles,
  combined with structured decoding that requires explicit evidence citations,
  significantly improve human-agreement and stability against adversarial rubric
  perturbations.

### Pairwise vs. Pointwise

- **Pointwise:** Judge evaluates a single response against a rubric. Simpler,
  works offline and online, but sensitive to absolute scale calibration.
- **Pairwise:** Judge compares two responses and picks the better one. Higher
  signal per comparison but doesn't produce absolute scores;
  [OpenAI's eval guide](https://developers.openai.com/api/docs/guides/evaluation-best-practices)
  notes "pairwise comparisons are typically done offline" due to cost.

For release decisions, pairwise comparison of current vs. previous version is a
robust signal.

### Calibrating Against Human Labels

Build judges iteratively:

1. Collect 100+ human-labeled examples (binary pass/fail with detailed critique
   notes).
2. Prompt an LLM judge with your rubric and few-shot examples drawn from those
   critiques.
3. Measure precision and recall against the human labels—not raw agreement
   (misleading on imbalanced sets).
4. Iterate rubric and prompt until agreement is satisfactory.
   [Hamel Husain](https://hamel.dev/blog/posts/llm-judge/) reports convergence
   typically requiring 2–3 rounds; Honeycomb's example achieved >90% agreement
   in three rounds.

[Shankar et al.](https://arxiv.org/abs/2404.12272) caution that criteria drift
means this calibration must be repeated as the system or user expectations
evolve.

### Known Biases and Pitfalls

| Bias | Description | Mitigation |
|------|-------------|------------|
| **Position bias** | In pairwise evals, judges favor the response listed first. Swapping order can shift accuracy by >10%. | Use balanced permutation of options; aggregate scores across orderings. [(arxiv 2602.02219)](https://arxiv.org/abs/2602.02219) |
| **Verbosity bias** | Judges prefer longer, more formal outputs regardless of substance—an artifact of pretraining and RLHF. | Use rubrics that explicitly penalize unnecessary length; check correlation between length and scores. |
| **Self-preference** | A judge model assigns higher scores to outputs from models with similar training distributions. [Wataoka et al. (2024)](https://arxiv.org/abs/2410.21819) link this to **perplexity-based preference**: LLMs prefer low-perplexity text, not necessarily better text. | Use a different model family for judging than for generation; calibrate against human labels. |
| **Rubric fragmentation** | LLM evaluation "dialects" differ across model families. A rubric calibrated on GPT-4o may not transfer to Llama. [(arxiv 2602.08672)](https://arxiv.org/abs/2602.08672) | Recalibrate any rubric when switching judge models. |
| **Shortcut bias** | Judges may key on surface features (formatting, keywords) rather than substance. | Include adversarial examples in calibration sets that look good but fail on substance. |

### Judge Prompt Templates

**(a) Pointwise binary pass/fail.** Rubric-driven, reasons first then the
reasoning is discarded by the parser, emits structured JSON. Set the judge to
temperature 0.

```text
You are a strict evaluator. Decide whether the RESPONSE satisfies every item
in the RUBRIC. Judge only against the rubric — do not reward length, fluency,
or formatting.

<rubric>
{rubric}
</rubric>

<input>
{input}
</input>

<response>
{response}
</response>

Think step by step inside <reasoning>...</reasoning>, checking each rubric item
against the response and citing the exact span that satisfies or violates it.
Then output a single JSON object on the last line and nothing after it:

{"verdict": "pass" | "fail", "failed_criteria": [<rubric item ids>], "confidence": 0.0-1.0}
```

Parser keeps only the final JSON line; the `<reasoning>` block is logged for
audit but not scored (chain-of-thought-then-discard).

**(b) Pairwise A/B with position swap.** Run the judge twice per pair with A and
B swapped; a response only "wins" if it wins both orderings, otherwise score it
a tie. This neutralizes position bias.

```text
Compare two responses to the same INPUT against the CRITERIA. Pick the better
one, or declare a tie if they are equivalent in quality.

<input>
{input}
</input>

<criteria>
{criteria}
</criteria>

<response_A>
{response_a}
</response_A>

<response_B>
{response_b}
</response_B>

Reason inside <reasoning>...</reasoning>, then output a single JSON object on the
last line:

{"winner": "A" | "B" | "tie", "reason": "<one sentence>"}
```

```python
def pairwise_judge(judge, input_, criteria, resp_x, resp_y):
    # Run both orderings; require agreement to call a winner.
    fwd = judge(input_, criteria, a=resp_x, b=resp_y)["winner"]   # X is A
    rev = judge(input_, criteria, a=resp_y, b=resp_x)["winner"]   # X is B
    if fwd == "A" and rev == "B":
        return "X"
    if fwd == "B" and rev == "A":
        return "Y"
    return "tie"   # disagreement across orderings ⇒ position-bias-driven, treat as tie
```
