# Memory hygiene sweep — ddaanet tier

Two passes over the ddaanet tier's 99 facts. They share a trigger and nothing
else: one is mechanical and belongs in a gate, the other is judgement and
belongs in a report.

Prompted by a 5-file random sample where every file had something, two had a
defect that mattered (a direct naming of my human partner, a reference to
`reference_own_hooks_json_sandbox_erofs` which no longer exists), and one was a
retirement candidate on the guide's own terms.

**Sweep B may be the compaction strategy, not merely hygiene.** One retirement
candidate in five files extrapolates to ~20 across 99, against a budget needing
~25 entries gone. That is n=5 and soft, but it is the only lever that removes
index bytes while touching no trigger token. The tier-wide-vs-sub-scoping fork
stays open until B reports.

## Decided

- Scope is `memory/ddaanet/` only. Other tiers are unmigrated; `micro` and
  `general` still point at `./.git/gitlore-placeholder`.
- B runs before the compaction fork is decided.
- **B proposes, never executes.** Retiring a shared-tier fact removes it from
  every ddaanet repo. The precedent: six tmux facts were retired as a closed
  workstream while two live skills still depended on them.
- Neither sweep rewrites fact bodies. Measured this session at 2% for zero index
  movement, and this repo's trim precedent damaged about a fifth of the lines it
  touched.

## Sweep A — mechanical, scripted, becomes a gate

Detections, each reporting `file:line`:

| Check | Rule |
| --- | --- |
| First person | `I `, `I'`, `my own` — excluding the required phrase `my human partner` |
| Deictics | `now`, `here`, `today`, `currently`, `recently`, `this session`, `needs a fresh session` |
| Direct naming | my human partner's given name in any `memory/**.md` body |
| Stale snake_case refs | `[a-z]+(_[a-z]+){2,}` tokens that look like pre-rename memory filenames |
| Dangling wikilinks | `[[slug]]` with no file whose frontmatter `name:` matches |
| Name drift | frontmatter `name:` ≠ file basename |

Implementation notes that are not optional:

- **Parse the frontmatter with a real YAML parser.** A regex for `name:` is the
  defect this sweep exists to catch, reproduced in the tool that catches it.
- **NUL-delimited file iteration** (`find -print0`), because the checker will
  outlive the assumption that no memory path contains a space.
- Direct naming warns rather than blocks outside `memory/`: content written in
  my human partner's name for an external audience legitimately carries it.
- Known live instance to confirm the checker catches: `.claude/rules/shell.md`
  cites `memory/feedback_whitespace_safety.md`,
  `memory/reference_git_hook_env_leak.md` and
  `memory/feedback_no_stderr_suppression.md`, all pre-rename paths.

Wire into `just precommit` once the existing violations are cleared — a gate
that starts red trains everyone to ignore it. This subsumes the standing
drift-guardrails item and the `memory-name-drift` brief.

**Open:** does the checker ship as part of gitlore (memory hygiene is arguably
the product's job) or stay a `scripts/` local? Defer until it works; the
decision costs nothing later and presupposing it shapes the code now.

### Settled while building it

`scripts/check-memory-hygiene.py`, covered by `tests/check_memory_hygiene.bats`.
Python because the YAML mandate above is the load-bearing requirement and the
strip-code-then-scan pass is a line-state machine; the repo already probes for
`python3 -c 'import yaml'` in `scripts/hook-manager/`.

**Two severities, decided on measured precision.** A check blocks only where the
pattern has no legitimate reading. Measured over the 101 facts:

| Blocking | first-person, direct-naming, pre-rename, broken-reference, name-drift, frontmatter |
| Warning | deictics, dangling wikilinks |

`here` and `now` are anaphoric far more often than deictic ("a mismatch here",
"a now-trivial script", "state what is true now"), and a dangling `[[link]]` is
a write-it-later marker as often as a dead cross-boundary one. Blocking on
either is the red-on-arrival gate this plan warns about.

**Prose checks read code-stripped text; reference checks read raw.** Fenced
blocks and inline spans are blanked before the prose and wikilink scans — that
alone took dangling wikilinks from 13 to 3 (bash `[[ … ]]` tests) and cleared
the `No agent named 'X' is currently addressable` false positives. The
reference checks must not strip: a stale memory path's natural habitat *is* a
code span, which is exactly the form all three `.claude/rules/shell.md` hits
take.

**Direct naming is case-sensitive.** `David` in prose is the violation;
`/Users/david/…` in a path is a filesystem fact. The capital separates them
with no exception list.

**The stale-token check anchors on the four `metadata.type` prefixes**
(`feedback|reference|project|user`) rather than the plan's bare
`[a-z]+(_[a-z]+){2,}`, which over a repo full of shell matches every ordinary
identifier. Scope excludes `tests/` (hundreds of `memory/notes.md` fixtures),
`plans/` and `docs/changelog/` (dated history, correctly citing the old names)
and `plugin-dev/` (vendored). In the remaining live scope it fires 4 times,
with no false positives.

**Broken-reference runs only inside `memory/`.** Shipped prose uses
`memory/ddaanet/foo.md` as a placeholder and is right to.

`<!-- hygiene-ok -->` on a line exempts it, for the guide files that must quote
the vocabulary they forbid.

## Sweep B — ownership audit, classify only

For each of the 99 facts:

1. Name the candidate owner: a skill, `docs/design.md`, a code comment,
   `CLAUDE.md`, or `shared-claude.md`.
2. **Grep that owner for the load-bearing terms.** A pointer claiming coverage
   is not coverage; the guide requires verifying it before proposing removal.
3. Emit one verdict: `retire` (owner covers it), `relocate` (acted-inline, no
   lookup step — belongs in always-on context), or `keep`.

Output is a single table: fact, verdict, named owner, the grep that confirms
coverage. Nothing is edited.

The three verdicts are not equal in value. `retire` removes an index line and
its trigger surface together — the only thing that buys headroom. `relocate`
buys index bytes but grows `shared-claude.md`, which is a different limit and
the one this repo has been told not to sweat.

**Execution shape is open.** 99 files is ~142KB of bodies, which does not fit
one context comfortably. Batched sequential passes, or parallel readers with a
merged report — worth deciding before starting, not during.

## Out of scope

- Rewriting fact bodies. Ruled out on measurement.
- Deciding tier-wide retirement vs. sub-scoping the mount. B's output is the
  input to that decision.
- Tiers other than ddaanet.
- Executing any retirement.
