# Approval wording and repo gates

The wording of the FR11 approval, and the repo's own gate and tooling. The
commit the agent makes once the user approves a summary, and why no gate stands
inside the store, are in
[memory-commit-ownership.md](memory-commit-ownership.md) (D58, D70); the git
hook that carries a push out is in [git-hooks.md](git-hooks.md). FR11 itself
stays in `design.md`.

- Approval — **D19** one canonical approval wording, held in the
  `gitlore:commit` skill and nowhere else
- Repo gates — **D22** the memory-hygiene checker is a repo-local gate, not
  shipped surface · **D67** the repo's own gate and dev tooling lives in
  `tools/`, outside `dist.include`

---

## Decisions — D19, D22, D67

Why the approval has one wording, why the hygiene checker stays repo-local, and
where the repo's own tooling lives.

**D19 — Memory-approval wording: one canonical copy, in the `gitlore:commit`
skill**

The FR11 approval prompt — "summarize pending memory changes, present them, get
approval" — is needed by every caller that drives a memory commit. Composed
independently, the copies drift: the in-gitlore ones did once (2026-07-16, "one
prompt fix, three surfaces"), and a hand-synced copy in a different repo
entirely can only drift further. The wording therefore has one home,
`skills/commit/SKILL.md`, and a caller outside gitlore invokes the skill rather
than carrying text of its own. The `SessionStart` orientation and
`commit-memory.sh`'s usage error each name the skill and do not restate it.

**The skill holds two blocks.** The first is the review directive: before the
summary is drafted, the pending memory changes are held against the
`memory-writing` skill, and what it finds is fixed first (D48). The second is
the body spec — one `== <store> ==` section per store with changes, each a
subject line, a blank line, then **one paragraph per changed memory file**, each
opening `**<Kind> <tier>/<slug>:**` with the kind drawn from New, Update,
Augment, Reduce, or Remove — followed by a literal template. A paragraph names
the change in one clause and spends its one to three sentences on what the diff
cannot show: what prompted it, what the old wording got wrong, where removed
content went, and who decided. It does not retell the new body: across the
memory commits of every ddaanet store (2026-10-27, 275 summaries), about three
sentences in four of a New, Update or Augment paragraph restated the diff, and
the cause sat last, after them. The approver has watched the edits land in the
conversation, so the retelling costs review without informing it. A `MEMORY.md`,
root or tier, is excluded from the listing: an index line moves with the fact it
points at, so a paragraph for it would restate its neighbour and put the routing
table on the same footing as the facts. Shipping the template rather than
describing the shape lets the agent copy a form instead of inferring one, and
the bold prefix is what makes the body scannable in the approval summary.

**The template is pinned against the script.** The wording is prose a script
parses, so the two cannot be allowed to drift apart:
`tests/commit_skill_template.bats` fills the skill's template and pipes it to
`bin/gitlore-commit`, which must accept it.

**D22 — The memory-hygiene checker is a repo-local gate, not shipped surface**

`tools/check-memory-hygiene.py` runs uncached at the head of `just precommit`
(the cache cannot see a fact change through the `memory` gitlink) and checks
prose shape, wikilink targets, reference style and volatile git state across the
store. It stays in gitlore's own `tools/`; the plugin ships none of it.

**Shipping it would make python3 and PyYAML a user-facing dependency.** The
install surface is bash, git and jq, and every hook and script on the runtime
path stays within that. A gate that runs at *this* repo's commit time may reach
for a parser; a gate distributed to every consumer repo may not, and hand-rolled
frontmatter regex would trade a real dependency for a worse one.

**Most of what it checks is a house style, not a gitlore contract.** Prose shape
and reference form are ddaanet-tier writing conventions; a repo that mounts a
tier inherits that tier's facts, not gitlore's opinion about how facts are
phrased. `volatile-state` is the exception whose subject really is the store's
own design — an abbreviated commit id in a fact body rots because the store
outlives the ref that named it, in any repo, under any house style. It matches
`\b[0-9a-f]{5,40}\b` over frontmatter-stripped bodies, less all-digit runs and a
closed 47-word list of a-f-spellable words; over this store, 4 hits, 4 true
positives, with the all-digit exclusion missing roughly 4% of seven-character
shas as the stated residual. One generalizable check does not carry a runtime
dependency into every consumer. Several would reopen this.

**D67 — The repo's own tooling lives in `tools/`, not `scripts/`**

`dist.include` lists `scripts` whole, so a file in `scripts/` ships to every
consumer. The gate and dev tooling (`check-docs-links.py`,
`check_docs_decisions.py`, `check_common.py`, `check-memory-hygiene.py`,
`lint-shell.sh`, `lint-cache-keys.py`, `run-bats-cached.sh`,
`parse-bats-junit.py`, `mutate-and-run.sh`, `test-macos.sh`) is gitlore's own
and moved to `tools/`, which is not listed, so what ships is decided by where a
file lives and not by a list that has to stay current. A per-file exclude or
allowlist drifts silently when a file is added; leaving the files in `scripts/`
with docstrings saying they do not ship leaves the shipping to the author's
memory. The runtime scripts stay in `scripts/`; the checkers scan `tools/` for
the line cap and citations.

## Rejected alternatives

**A per-file `dist.include` exclude or allowlist for the tooling.** Drifts
silently when a file is added (D67).

**Tooling left in `scripts/` with its docstrings fixed.** Leaves the shipping to
the author's memory (D67).
