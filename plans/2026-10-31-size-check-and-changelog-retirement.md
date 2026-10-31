# Retire the dated changelog; adopt the toolkit size check — plan

Status: approved by my human partner. Base: `dev`.

A retired or inverted decision is deleted from the index and its node, the
deleting commit says why, and the D-number gap stays — my human partner's call,
taking the brief's default. It applies twice: to D2 in step 1 and to D55 in step
11.

## Why

Two decisions by my human partner. **The dated changelog retires**
(`inbox/2026-10-31-brief-retire-dated-changelog.md`). 123 of 124 records landed
with the commit they restate, and `CLAUDE.md` already says git history is the
changelog.
**The toolkit's byte-cap size check replaces the repo's 400-line check**
(`plugin-dev/migrations/v0.13.0.md`, `plugin-dev/manual/size-check.md`).
`just check-size` lists 10 files over a cap. `docs/changelog.md` goes with the
first decision, and the other nine split along seams. **Nothing is exempted**,
so no `size.exempt` is created. `installation.md` is 20 bytes over, and the
manual forbids shaving, so it splits like the rest.

## Decisions to record

- **D72**, in a new node `docs/references/design-history.md`: git history is the
  design's changelog. The dated records and both indexes are deleted, and a
  design-significant change carries its why in the commit body or the node. A
  decision that is inverted or retired is deleted from `decisions.md` and its
  node. The deleting commit says why, the diff keeps the text, and the number is
  not reused. Rejected alternatives: keeping the existing records frozen while
  writing no new ones (craft permits it, but a frozen index is still a file the
  hub links and the size check counts) · splitting `changelog.md` by period to
  pass the size check · a "retired decisions" section in `decisions.md`.
  Recovery of a record goes in the deleting commit's body:
  `git log -- docs/changelog/`, then
  `git show <deleting-commit>^:docs/changelog/<file>`.
- **D73**, in `docs/references/artifact-size.md`, which replaces D55 (deleted
  under D72): the artifact cap is the toolkit's `plugin-dev/check-size.sh`. It
  sets 20000 bytes per file, and 10000 for a `SKILL.md`, over every file git
  lists and does not ignore. It is wired as an uncached `precommit` dependency,
  and `oversized-file` leaves `check-docs-links.py`. D55's five rejected
  alternatives carry over to D73, each restated against the byte cap where its
  wording names lines. "Raising the cap" and "leaving the rule a convention with
  no checker" stand as written. "Gating tokens instead of lines" becomes "gating
  tokens instead of bytes", because counting tokens still needs the API. "A
  separate checker script for the source tree" stands because one script covers
  every file. "Counting only shell files, not python" stands because the byte
  check counts every file. Newly rejected: keeping the line check beside the
  byte check, because the two measures disagree and a file can pass one and fail
  the other. The mechanism points at `plugin-dev/manual/size-check.md` and is
  not retyped.

## Steps

Each step is one commit on `dev`. Each is gated by `just precommit`, run in the
background as `CLAUDE.md` describes, and gets a delegated `/code-review medium`
right after it lands. High and medium findings are fixed in a follow-up commit,
and that commit gets the same review. Steps 2–10 are
**move plus citation updates only**. Moved text stays byte-identical. The only
lines that change are headings and their D-lists, opening summaries that
enumerate what a file holds, pointers, and one link left where the text was.
Check with `git diff -M --color-moved=zebra`. After step N, `just check-size`
(unwired) lists exactly the files no step has reached yet. Every split targets a
result well under the cap, not just under it.

Every split updates these files, and `tools/check-docs-links.py` catches only
some of the misses:

- the new node's heading D-list and the old node's trimmed one
  (`enumeration-drift`);
- `docs/decisions.md`: the group block, split into a new group with its link and
  its *Rejected* names, or the tiered-memory delegation sentence at :219–231
  (`delegation-drift`, `stub-without-body`);
- the `docs/design.md` Architecture link, where the hub pointed at the moved
  part.

The old node still exists after a split, so a pointer that places a moved
decision there raises no `broken-link`. **The citation rule** for each split
step: grep the repo, excluding `plans/`, `inbox/`, `plugin-dev/` and `memory/`,
for every moved D-number and every moved function name, and for the old node's
filename. Repoint every hit that places moved content in the old node, whether
it is a link, a code span or prose, in `docs/`, `skills/`, `CLAUDE.md` or a
script comment. Hits found while reviewing this plan are examples, not the list:
`cc-memory-retrieval.md:7` (D18 "in `references/cc-platform.md`"),
`tiered-memory.md:50–52` (D41 in `merge-and-resolve.md`),
`plugin-upgrade-notice.md:21` (D5 in `session.md`). The step's report lists each
hit and whether it was repointed.

A decision's rejected alternatives travel with it.

**Dispatch.** Step 1 goes to Sonnet, reviewed by Opus. Steps 2–7 go to one
Sonnet agent reused across the six, with one Opus reviewer reused across them.
Steps 8–9 go to Haiku (fully specified moves), reviewed by Sonnet. Step 10 goes
to Sonnet, reviewed by Opus. Step 11 has a Sonnet red author, a separate Sonnet
red reviewer, Haiku for the green code and Sonnet for its prose, and an Opus
review. Agents are reused by `SendMessage` until ~150k tokens, with `name`
unset, and each names an output file for its report.

### 1. Retire the dated changelog, record D72, delete D2

- Delete `docs/changelog.md`, `docs/changelog-archive.md` and `docs/changelog/`.
- **Fold before deleting.** For each live citation of a record, read the record
  and either fold the argument the node relies on into the node, in the present
  tense, or drop the sentence. Report which was done for each. The citations are
  `docs/references/cc-memory-retrieval.md:5`,
  `docs/references/memory-authoring-guidance.md:52` and
  `docs/references/artifact-size.md:120`.
- **D2** (`merge-and-resolve.md:183–189`) is only a pointer to a record, so it
  is deleted under D72. Its lines go from `decisions.md:21`, from
  `merge-and-resolve.md:10` and `:173`, and from the body at `:183–189`.
  `:336`'s "D1, D2, D3 and D6" becomes "D1, D3 and D6".
- Text that names the changelog:
  - In `docs/design.md`'s preamble (`:8–11`), only the clause "how it got here
    is in [changelog.md](changelog.md)" goes. The living-design statement and
    the decisions.md sentence stay. The `## Changelog` section (`:321–326`)
    goes, which leaves five sections.
  - `docs/design.md:318–319` and `docs/decisions.md:281` ("lives in the
    changelog") are restated as the D72 rule.
  - `CLAUDE.md:38–40` changes "six-section" to "five-section" and "the living
    design, the changelog, and reference material" to "the living design and
    reference material".
- Write `design-history.md` with D72 in the house node shape: summary bullets,
  the argued body, then `## Rejected alternatives`. Add a decisions group
  linking it, and a hub link where `design.md`'s preamble describes the docs
  layout.
- In code: the `tools/check-memory-hygiene.py:40` comment drops
  `docs/changelog/`; the `tests/plugin_distribution.bats:115` comment drops the
  changelog row; the `tests/check_docs_links.bats:46–54` case becomes a file in
  a non-`references/` docs subdirectory, so it still proves that the walk
  descends.
- Post: `grep -rnE 'changelog(-archive)?\.md|changelog/'` outside `plans/`,
  `inbox/`, `plugin-dev/` and `memory/` returns nothing, so no link or path to a
  deleted file remains. The bare word stays legitimately in `CLAUDE.md:37` ("git
  history is the changelog"), in D72's own wording, and in `TODO.md`'s two lines
  that step 11 strikes. `just check-size` lists the nine remaining files.

### 2–7. Split the six oversized nodes (one commit each)

The sizes are as `just check-size` reported them. The measured bytes are the
estimates the implementer verifies.

2. **`cc-platform.md`** (22517) → new **`active-recall.md`**, "decision D18". It
   takes D18 (`:52–115`) and its two rejected alternatives, "hook-side injection
   of the bodies" and "a `PreToolUse` deny on the first durable write". That
   moves ≈5.3k. The rest of the node keeps D15, D23, D51 and D60, and its
   summary drops the "force a `Read`" clause. In `decisions.md`, D18 leaves the
   platform group and gets a new "Active recall" group with those two rejected
   names.
3. **`index-composition.md`** (24999) → new **`composition-reports.md`**,
   "decisions D34, D35, D57". The seam is the moment a reader holds something
   composition printed: a pointer-presence or dangling-line report (D34), the
   welded-line refusal (D35), the mount's size line (D57). It takes D34 and D35
   (`:158–228`), D57 (`:314–343`) and the rejected alternatives that cite them:
   "recompose owning index-line presence" and "deleting a memory file when its
   pointer line is removed" (D34), "reporting the mount's size as a percentage"
   and "sharing D39's `budget` marker kind" (D57). That moves ≈8k. D29–D31, D36
   and D37 stay: D31's triggers and validation stay beside the projections (D36)
   that cite them (`:238`). The two cross-node citations left are D34's mention
   of D36 and its contrast with D31's validations; both become links to
   `index-composition.md`. Update the delegation sentence
   (`decisions.md:221–222`) and both nodes' heading D-lists and summary bullets.
   In `tiered-memory.md`, the sibling count at `:5` and `:23` ("five siblings",
   already one short of the six the delegation sentence names) becomes seven,
   and the composition bullet (`:34–40`) moves D34, D35 and D57 to a bullet
   linking the new node.
4. **`installation.md`** (20020) → new **`memory-remote.md`**, "decisions D8,
   D64, D65". It takes `## Remote Repository` (`:173–267`), D8, D64, D65 and
   their rejected alternatives, which moves ≈8k. D25, D45, the install command
   and hook-manager support stay. In `decisions.md`, the "Install and the memory
   remote" group splits in two. In `design.md:285–289`, "the disclosure text and
   the per-provider creation methods" point at the new node.
5. **`merge-and-resolve.md`** (≈23.2k after step 1) → new **`branch-model.md`**.
   It takes the summary's own "Trunk and direction" cluster:
   `### What each phase does with live`, D1, D6, D41, and the rejected "`live`
   as a working branch". That moves ≈5.5k. The rest stays as "Doing the merge":
   D3, D7, D9, D13, D24, D49 and the two skills. `design.md` § Branch Model
   (`:162–166`) points at the new node for D6 and D41. Repoint
   `tier-stores.md:13–14`'s link for D41.
6. **`session.md`** (20377) → new **`hook-wrappers.md`**, "decisions D5, D11".
   It takes `## Hook Wrappers` (`:18–59`), D5, D11 and the rejected "tracked
   hook scripts", "a literal `.git/gitlore-<hook>` path" and "a per-worktree
   wrapper anchor". That moves ≈7k. `session.md` keeps D14 and D59. Repoint the
   wrapper half of the `installation.md` intro link (`:8–10`), and split the
   `decisions.md` "session and its wrappers" group in two.
7. **`tier-stores.md`** (22691) → new **`tier-conflicts.md`**, "decision D44".
   It takes D44 (`:250–317`) and the rejected "an append-only constraint", "a
   `merge` driver plus `.gitattributes`" and "`**/MEMORY.md merge=union` plus
   dedup". That moves ≈6k. In the delegation sentence, "D42–D44" becomes
   "D42–D43" plus the new node. In `tiered-memory.md`, the sibling count at `:5`
   and `:23` goes from seven to eight, and the stores bullet (`:49–52`) moves
   D44 to a bullet linking the new node.

### 8–9. Split the two resolve libraries (one commit each)

Each new file is function-only and starts with the same "Part of lib/resolve.sh;
source that, not this file." header. It gets a `source` line in
`scripts/lib/resolve.sh` (`:28–50`) next to its origin, because
`tests/helpers/setup.bash:129` globs the directory but `resolve.sh` sources by
name. The origin's header comment drops the moved responsibility, and comments
that name a moved function point at its new file. Grep `docs/references/` for
each moved function and repoint any file citations. Post: `declare -F` lists the
same names after sourcing `resolve.sh`, and `declare -f` of every moved function
is byte-identical before and after.

8. **`resolve-merge-state.sh`** (21450) → **`resolve-merge-prepare.sh`**,
   "prepare the merge itself". It takes `gitlore_prepare_merge` and
   `gitlore_yield_merge` (`:267–367`, ≈6.5k). The marker and state-file IO, the
   directive and index-problem recording stay.
9. **`resolve-recovery.sh`** (20386) → **`resolve-recovery-repair.sh`**, the
   repair arms. It takes `gitlore_recover_landed_merge`,
   `gitlore_adopt_recovered_merge` and `gitlore_restore_staged_merge`
   (`:111–297`, ≈9.5k). The classifier `gitlore_recover_stale_no_merge_head` and
   the three lookups (`gitlore_pending_commit`, `gitlore_landed_merge_commit`,
   `gitlore_drop_merge_preparation`) stay.

### 10. Split the `memory-writing` hub

`skills/memory-writing/SKILL.md` is 15615 bytes against the 10000 hub cap. The
seam is **when the content is needed**, not topic: what every write uses stays
in the hub, and what only some writes reach moves to `references/`, which
already holds `owner-inventory.md`. A node read on every invocation saves
nothing, since it is paid as a second read each time. So §1 (bar the owner
list), §2, §7 (bar its last paragraph) and §8 stay. §8 also stays whole because
`plugin_distribution_commands.bats:31` greps it for `gitlore-commit`. The
frontmatter is untouched (`plugin_distribution.bats:71–76`).

Four nodes, each named for the moment that opens it:

- `references/owners.md`: §1 Q2's per-owner list (`:45–66`, 1553 bytes) and §7's
  last paragraph (a fact written to override an installed skill). Both are
  consulted once a candidate owner is in view; Q2's question itself stays in the
  hub, since every write asks it. The `owner-inventory.md` link is repointed for
  the new directory.
- `references/file-shape.md`: §3 and §4 bodies. Needed when a file with the same
  moment clause already exists, or a file is filling toward recall's 4096-byte
  limit.
- `references/tier-routing.md`: §5 and §6 bodies. Needed when a tier is mounted
  and the fact might go up.
- `references/gate-pass.md`: §9 body. Needed only when a caller sends the agent
  here over a batch of facts already written: the `gitlore:commit` review
  (`skills/commit/SKILL.md:15`), `/gitlore:install` (`commands/install.md:27`)
  and a tier mount (`commands/add-tier.md:127`,
  `scripts/lib/index-compose.sh:299`).

Headings `## 3.`–`## 6.` and `## 9.` stay, each followed by one pointer line
that states the node's moment in literals the reader holds and links the node.
§9's line names its three callers, since "arriving at a gate" is the moment a
reader cannot recognise. Keeping the headings keeps the in-hub `(§N)` references
valid. The callers are not edited in this commit: they already invoke the skill,
and the hub's §9 line routes them. The citation rule applies; its known hit is
`docs/references/memory-authoring-guidance.md:112` ("§9 of `SKILL.md` carries
it"), repointed to `gate-pass.md`.

About 6.6k moves out and about 0.8k of pointer lines comes in, leaving the hub
near 9.8k. If `check-size` still lists it, stop and report: no shaving, no
further node without my human partner's call.

Post: `just check-refs` resolves the new links, and `just check-size` lists no
file.

### 11. Wire `check-size`, retire the line check, record D73

- **Red** (Sonnet; reviewed by a different agent): in
  `tests/justfile_gates.bats`, beside the `:125` case, assert that
  `.recipes.precommit.dependencies[].recipe` includes `check-size`. It fails
  against the unchanged justfile.
- **Green code** (Haiku):
  - `justfile:69` becomes
    `precommit: format-docs check-distribution check-refs check-size`.
  - In `tools/check-docs-links.py`, these go: `MAX_LINES`, `check_size`,
    `discover_sources`, `SOURCE_DIRS`, `SOURCE_SUFFIXES`, both size loops in
    `main`, and `"oversized-file"` in `BLOCKING_CHECKS`. The docstring's bullet
    and line-cap paragraph go too, and "Nine checks. Eight are blocking" becomes
    "Eight checks. Seven".
  - In `tests/check_docs_links.bats`, the four `oversized file:` cases
    (`:117–160`) and the `"oversized-file"` assertion in the sign-off case
    (`:174`) go.
- **Green prose** (Sonnet):
  - Rewrite `artifact-size.md` around D73, following the Decisions section
    above. "What the cap bounds" argues bytes, "What the checker walks" points
    at the manual, D55's body goes, and its rejected alternatives are restated
    under D73.
  - In `decisions.md`, the Artifact size group gets D73's conclusion line and
    *Rejected* names.
  - Restate `design.md` NFR12 (`:126–132`) in bytes, with D73.
  - Drop the line-cap clause from `testing.md:87–89` and from
    `commit-gate.md:96–97` ("for the line cap and citations" becomes "for
    citations").
  - `justfile:93–106` comments: drop "so a line count means something" and the
    line-cap sentence.
  - `tests/justfile_format_docs.bats:39` comment: drop the line-cap clause.
  - `CLAUDE.md:69–70`: add `check-size` to the checks that "run uncached and
    write no gate file". "Four fresh gates" stays: it counts the gate files, and
    `check-size` writes none.
  - Strike `TODO.md`'s two lines for these decisions, and add the out-of-scope
    follow-ups below.
- Post: `just check-size` prints its `check-size: cap 20000 bytes:` sign-off
  line, and `just precommit` passes.
  `grep -rn 'oversized-file\|MAX_LINES\|400-line'` outside `plans/`, `inbox/`,
  `plugin-dev/` and `memory/` returns nothing.

## Out of scope

- `plugin-dev/check-refs.sh`'s default `docs/changelog` exemption. It changes
  only through a toolkit release.
- The ddaanet tier's 400-line rule in `memory/ddaanet/shared-claude.md` (§ Code)
  binds every ddaanet repo, so changing it is a proposal for my human partner.
  It goes in `TODO.md`, not here.
- `memory/ddaanet/claude-plugin-dev.md:37,40`, which cites the toolkit's own
  changelog.
- `inbox/2026-10-31-brief-hub-keeps-conclusions.md`. Its `decisions.md` layout
  question is not mixed into these splits.
- Rewording any moved text, and any other superseded entry the D72 rule might
  reach.
- Release notes. `dist.include` does not ship `docs/`.
- Frozen mentions under `plans/`.
