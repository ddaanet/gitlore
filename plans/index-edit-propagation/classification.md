# Classification — index-edit propagation findings

Source: `inbox/brief-index-edit-propagation-findings.md` (2026-09-03, reported
against gitlore 0.7.1). Three discrete items; **implicit bundling** — the input
artifact enumerates them.

## Requirements-clarity gate

- **Requirements source:** brief
  (`inbox/brief-index-edit-propagation-findings.md`)
- **Completeness:** concrete mechanism per finding — item 1 Y, item 2 N (stated
  cause is not the observed mechanism), item 3 N (brief states cause not
  established). Measurable criterion — item 1 Y, items 2/3 N.
- **Routing:** proceed to per-item triage; items 2 and 3 are defects whose
  investigation structure supplies the missing mechanism.

## Triage recall

Selected from the in-context index: `hook-input-schema` (PostToolBatch is
per-batch, `agent_id` present only when the hook fires *inside* a subagent),
`gitlore-tier-merge-direction` (root is canonical, the carrier copy goes in the
same pass), `jsonl-sidechain-segregation` (subagent transcripts are the ground
truth for whether a hook fired), `directive-states-acts` (what a hook's
`additionalContext` may contain). Already in context: `design-doc-writing`,
`design-doc-no-situational-state`, `design-doc-rewire-dead-components`.

## Item 1 — composition's `additionalContext` denies what composition does

- **Classification:** Simple
- **Implementation certainty:** High — one string at
  `scripts/lib/index-compose.sh:718`
- **Requirement stability:** High
- **Behavioral code check:** No — no new function, logic path or branch
- **Work type:** Production
- **Artifact destination:** agentic-prose (script-emitted text an agent acts on)
- **Evidence:** `gitlore_compose_down` picks the **root** bullet's text for any
  path root carries (`scripts/lib/index-compose.sh:497`), so the carrier line's
  text is rewritten, not merely placed. D29 scopes "never its text" to
  *the root index*; D36 states the down projection writes the carrier "with
  root's text and root's order". The design is correct and the behaviour is
  intended — the hook message dropped D29's scoping and is the defect. No test
  asserts the sentence.

## Item 2 — `originSessionId` provenance restamped on update

- **Classification:** Defect
- **Implementation certainty:** Low — the brief's stated cause is disproved
- **Requirement stability:** Low
- **Behavioral code check:** Unknown until the writer is identified
- **Work type:** Investigation
- **Artifact destination:** investigation
- **Evidence:** `gitlore_set_frontmatter_description`
  (`scripts/lib/index-sync.sh:53`) rewrites **only** the first `description:`
  line, via awk, and passes every other line through. `originSessionId`,
  `node_type`, `modified` and the trailing space after `metadata:` appear
  nowhere in gitlore's scripts (`grep -rn originSessionId` over `scripts/`
  returns nothing) and are present in memory files gitlore has never written
  through this path. The stamping is Claude Code's own auto-memory writer, so
  the brief's suggested fix — "stamp `originSessionId` only when creating a
  file" — has no site in this repo.

## Item 3 — an index edit inside a subagent propagates to nothing

- **Classification:** Defect
- **Implementation certainty:** Low — brief states cause not established, two
  rival explanations wanting different fixes
- **Requirement stability:** Moderate — the intended behaviour is not in doubt
- **Behavioral code check:** Yes — the fix will change a logic path in the
  Pre/PostToolBatch pair
- **Work type:** Production (via investigation)
- **Artifact destination:** production
- **Evidence:** `hook-input-schema` records `agent_id` as present *only* when a
  hook fires from within a subagent, which is evidence hooks do fire there and
  weakens the brief's first explanation. The second — a stash consumed by an
  earlier batch — is live: `index-sync-pre.sh` and both PostToolBatch consumers
  key on two fixed paths in the memory gitdir (`gitlore-index-preimage`,
  `gitlore-compose-stamp`), shared by parent and subagent with no per-agent
  keying, and each post hook `rm -f`s the file unconditionally. Reproduction
  must discriminate before either fix.

## Out of scope

The brief's closing observation — 13 tier descriptions that never matched their
index lines across 228 commits — is the sync keying on a *changed* hook by
design (`index-sync-post.sh`: existing line with unchanged hook → `continue`). A
backfill pass is a separate capability, not one of these three findings.
