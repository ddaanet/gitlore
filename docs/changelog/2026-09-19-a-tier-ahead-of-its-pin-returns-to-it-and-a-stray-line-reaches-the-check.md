# 2026-09-19 — A tier ahead of its pin returns to it, and a stray line reaches the check (D44, D50, D52)

The pin guard's ahead-of-pin refusal prescribed a hand remedy: replace every
line of root's `MEMORY.md` whose link starts with the tier's prefix by the
carrier's lines, then stage the gitlink. That is the step `gitlore_compose_up`
performs on a take, and hand-composing it is how a root index acquires the
duplicates and welds D50's abort exists to catch. A tier that is clean and whose
local `live` already contains its `HEAD` is now checked out back at the pin. The
commits are not lost — `live` still holds them — and what the checkout leaves is
exactly the state `gitlore_adopt_advanced_live` takes from: a clean tier on its
pin with `live` ahead of it. The refusal still stands, because the root index
has yet to take the carrier, and it names `/gitlore:merge` as the command that
adopts.

The guard checks out; it does not adopt. Adoption writes the root index and
stages a gitlink, and the guard runs from every compose — `SessionStart`,
`PostToolBatch`, the commit path — where such a write would land work no
approval covers in the next approved commit. The checkout writes no index and
needs no approval: it returns the tier to the commit root already records, which
is what `submodule update` would do at the next `SessionStart` anyway. Adopting
inside the guard, and a blanket refusal for every tier ahead of its pin, are
both recorded as rejected. A checkout that fails leaves the tier untouched and
folds git's own message onto the problem line, with the `checkout --detach`
command that finishes the return. Every other ahead tier — dirty, no local
`live`, `live` short of `HEAD` or diverged from it — is refused where it stands,
now stating the two conditions the take needs and naming the ff-checked
`git -C "<abs>" push . HEAD:refs/heads/live` that puts `HEAD`'s commits where
the take reads them, with `/gitlore:resolve` for a push refused as a
non-fast-forward. A residual stands: a retry that does not run `/gitlore:merge`
first composes and commits normally over the returned tier, leaving the commits
in `live` for a later tier commit to meet as a non-fast-forward `HEAD:live`
push. Nothing is lost either way, and the message names the take.

The entry-wise index merge rebuilds the bullet block by emitting one line per
path of the merged path list, so a line inside the pointer region that carries
no path was never emitted. A stray non-bullet line one side introduced was
dropped silently; so was one every side inherited from the merge base, with
nobody in the merge having touched it. D44 already declines a side that names
one path twice, for precisely this reason — keying on the path would collapse
the pair and drop whichever line lost — and a non-blank non-bullet line inside
the pointer block is the same class: malformed before the merge, unrepresentable
in a block rebuilt from a path list, and reported by
`gitlore_compose_check_index`. The merge now declines such a side too, with the
same rc 2. Git's line-wise result then stands with the stray line intact, and
the merged-index gate refuses the landing and keeps the merge prepared for a new
synthesis — which is what D52 says happens, and was until now reachable in
`resolve_compose.bats` only by way of a duplicate path. Blank lines keep the
opposite answer: every compose pass rebuilds the bullet region from bullets
alone, so dropping a blank line is the normalization the rest of the system
performs rather than a loss. Preserving a stray line in place was refused —
under D37 the path sequences carry paths and never bullet text, and a stray line
has neither a path nor a stable offset once the merge has reordered the bullets
around it. The cost of declining more often is that git's line-wise result
stands more often, and that result can itself carry a duplicate pointer: the
trade the duplicate refusal has always made, caught by the same gate.

The merged-index gate's problem lines reached only whoever ran the continuation.
A merge is routinely met again by a session that never saw them — after a
`/clear`, a compaction, a fresh start — and the re-emitted directive is the
whole briefing the next sub-agent gets. The gate now records what it read into
the merge state file's new `index_problems` field, and
`gitlore_emit_merge_directive` emits those lines between the state-file path and
the dispatch paragraph. The field carries the check's verdict rather than only
its failures: a merge can stay prepared for a reason outside the merged files —
a refused commit, a message that would not build — and without recording the
empty answer a later directive would brief a sub-agent against an objection a
synthesis had already cleared. It is written at the gate and edited into the
existing file, because the gate runs long after the preparation, against a store
the merger has rewritten; a file written by an older version reads as carrying
none. With the lines travelling in the directive, the resolve skill's
resume-the-same-sub-agent workaround is cut to the stop rule it existed to
protect: a re-synthesis drawing the same problem line stops and relays to the
user.

A memory store with no root `MEMORY.md` was silent in every direction. The two
projections, the four index validations, the weld rule and the merged-index gate
all key on that file and return early without it, both `PostToolBatch` hooks
bailed before they read anything, and Claude Code loads no memory at all — so an
index written and committed in such a store went out unchecked. The compose hook
now says so once per session, on both channels, naming what is off and what to
write. It reports and never repairs: a `MEMORY.md` the hook wrote would enter
the store outside the approval gate, and `SessionStart` is the one place that
scaffolds, because what it writes rides the next commit under review. The notice
goes through the hook's existing relay tail, so a subagent firing it does not
spend the session's one telling inside its own transcript, and `PreCompact`
re-arms it alongside the other nudges. `/gitlore:install` could produce such a
store: the copy-existing-auto-memory branch owned the `else` that wrote the
scaffold, so an auto-memory directory holding fact files but no index — a
session interrupted before Claude Code wrote one, or one whose index was deleted
— was copied in whole and the initial commit recorded a rootless store. The copy
no longer owns that branch; the scaffold is written whenever the seeded store
has none, and a migration that brought its own index keeps it.

Two arms of the commit path aborted with nothing printed. Deciding whether a
composition problem sits in a file this commit changes means reading
`git status --porcelain -- MEMORY.md` for root's index and for each tier's
carrier, and a failed read left that question open with the commit stopping on
it in silence. Both now report through one helper: the compose refusal that sent
the run to the read, which index could not be read, that the commit was aborted
for that reason, that the approved summary is still in place, and the next
command — repair the store for the agent, establish why `git status` fails for
the user.

The precommit gates record a pass only for the tree their checks read.
`check-sentinel` takes the input hash before the checks start, on every path,
since a forced run and a first run both reach `record-sentinel`;
`record-sentinel` re-hashes and, on a mismatch, removes any stale sentinel, says
`gate: inputs changed while the checks ran; the pass was NOT recorded` and exits
1 rather than handing the caller a green verdict. A peer session editing an
input mid-run would otherwise have sealed in a pass for a tree nothing checked.
An unhashable input is kept distinct from a mismatch and keeps the older
contract: no sentinel, said loudly, recipe still green. `test-unit` subtracts
`:(exclude)tests/integration_*` from the shared input set — it runs none of
those suites, so editing one must not send the unit half through a nine-minute
re-run — and `test-integration` and `lint` keep them. `format-docs` excludes
`plans/*/reports`: a report records a run that has finished, so wrapping it
rewrites a file its author is no longer there to read, and it escapes no check
by staying unwrapped, the only line cap in the repo being
`check-docs-links.py`'s over `docs/`. `plans/` outside `reports/` stays wrapped.

`/gitlore:merge` reported a repair as one outcome when the run has three. The
skill now keys the publish claim on the tier line ending
`; /gitlore:push publishes it.`, and carries the resting case — this repo's own
index has problems, nothing is published until they are fixed, and the next take
adopts the repair without repairing again — and the unrepairable case with both
remedies the run prints, saying which applies. A repair that fails on its
scratch directory, a read, the rewrite, the commit build, the `live` advance or
the checkout after it is relayed as transient, because the next take repairs
from scratch. A new `## Correcting what arrived` section states that a take's
adoption is never a hand rebuild of root's block, that upstream's lines land
first and a correction to them is a later change of this repo's own — later
being the next step, not permission to skip it — and that dropping an arrived
pointer can take two edits: the composition drops a tier line from the carrier
only when the root index carried that path at `HEAD`, and whether an arrived
path is at `HEAD` depends on whether a commit has recorded the recomposed root
index yet. `git -C memory show HEAD:MEMORY.md` is the check to run before
assuming one pass suffices. That mechanism is recorded under D36.

Three smaller behaviours. The index budget notice reads as ambient: the user
line closes `— a size notice, nothing to act on`, and the model line states that
the fact just written stands, that nothing there asks for curation or names a
line to go, what the number is for — Claude Code's loader silently truncates
past 24.4KB — and that curation is the `/gitlore:index-audit` pass, run when it
is asked for. `relay-drain.sh` and the compose hook omit `hookSpecificOutput`
entirely when the context half is empty, the form `index-sync-post.sh` already
used; no producer reaches that state today, so it is defensive uniformity rather
than a fix. And `_gitlore_nudge_reset`'s age sweep of other sessions' markers
ends `|| true`: a gitdir refusing the unlink used to abort the whole
`nudge-reset.sh` hook under errexit, so the upgrade reset never ran either.

The records caught up with the code. D53 states that the stale-merge guard's
report-only arms do not restamp the approval, because the guard does not say
which arm failed; D54 accepts as residual a failure-time restamp that blesses a
concurrent write, the success path holding the same window open and wider.
`scripts/mutate-and-run.sh` is a new dev tool that mutates a file with a sed
script, runs a bats suite, restores byte for byte and reports KILLED or SURVIVED
— refusing a dirty or untracked subject, a mutation that matches nothing, a
filter that selects no test, and a restore that did not come back identical,
each of which otherwise reads as a mutant result. `gitlore_index_largest` is
gone: it had no production caller anywhere, and the doc sentence claiming the
budget pass names the five largest lines was corrected to what the pass does.
