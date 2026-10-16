# ddaanet tier: wrong author identity — proposal

A proposal for my human partner to decide, not a runbook; nothing here is
executed. A step marked **[partner]** writes to a repository other than gitlore:
my human partner runs it or explicitly authorises it, step by step. No step uses
`--no-verify`; branch creation and switching stay my human partner's.

## 1. Findings

### 1.1 The numbers

Measured in `/Users/david/code/gitlore/memory/ddaanet`
(`git log --all --format='%an <%ae> | %cn <%ce>'`):

- 353 commits over all refs. 55 have author `T <t@e.c>` and the correct identity
  (the global `user.*`) as committer; 26 are `gitlore <gitlore@localhost>` on
  both sides (out of scope); 272 are correct.
- All 55 are on `origin/live`; none is on `main`, whose 6 commits are ancestors
  of `live` inside the unchanged prefix. The remote advertises exactly two refs,
  `live` and `main`, and answers an anonymous https `ls-remote`, so the tier
  appears to be public.
- The earliest T commit is dated 2026-07-26, the latest 2026-09-26. Because a
  commit id covers its ancestors, a rewrite changes **294 of the 325** ids on
  `origin/live`; the 31 oldest keep theirs. Old and new `live` therefore share a
  merge base. This is what makes the rewrite dangerous (1.4).
- Local `live` here is 2 ahead and 7 behind `origin/live`; `main` matches.

### 1.2 Where `T <t@e.c>` comes from

**The config write.** The session transcript
`~/.claude/projects/-Users-david-code-gitlore/b75fba34-d0f7….jsonl` records, at
2026-07-21T10:45:45Z, a throwaway probe:

```sh
P=$(mktemp -d "$TMPDIR/fifo.XXXX"); (cd "$P" && git init -q -b main . &&
  git config user.email t@e.c && git config user.name T && …)
```

`TMPDIR` is unset in that shell: the result reads
`mktemp: failed to create directory via template '/fifo.XXXX'`, then
`warning: re-init`. `cd ""` stays in the project root, so both `git config`
calls land in `gitlore/.git/config`. gitlore's first T commit follows twelve
minutes later; its 382 T commits have T as author *and* committer, which is what
a repo-local identity produces.

**The leak into the stores.** In the tier the committer is correct and only the
author is wrong; in `gitlore-memory` the 73 T commits have committer
`gitlore <gitlore@local>`. `git commit` exports `GIT_AUTHOR_NAME`/`_EMAIL` to
its hooks, and `git rev-parse --local-env-vars` does not list them, so a store
commit made from inside the parent's `pre-commit` takes the parent's author and
its own committer. A two-repo probe under `$TMPDIR` reproduces exactly that
pair. No script under `scripts/` mentions `GIT_AUTHOR`.

Consequences for recurrence: `gitlore/.git/config` holds no `user.*` now and no
consumer's parent, memory or tier config holds T, so every T commit in the tier
originates from gitlore sessions. The leak path is retired at gitlore's tip
(D58) but latent in the installed plugin every consumer runs (0.9.0 still ships
`scripts/git-hooks/pre-commit`); it shows only where the parent's identity
differs from the store's. The probe pattern itself — an unchecked `mktemp`
followed by `cd "$P"` — recurs in any repo.

### 1.3 Consumers on this machine

Thirteen repos under `/Users/david/code` mount the tier
(`<repo>/memory/.gitmodules` names `ddaanet-memory`). No fetch was run: "behind"
is against the newest `origin/live` any clone holds, which is the remote's
`live` at the time of writing.

| repo | tier HEAD | local-only tier commits | tier dirty | plugin |
|---|---|---|---|---|
| claude-plugin-dev | behind 15 | 0 | no | no |
| craft | behind 35 | 0 | no | yes |
| cwd-safety | off remote | 1 | no | yes |
| edify | behind 9 | 0 | no | yes |
| ghmem | at tip | 0 | no | unlisted |
| gitlore | off remote | 2 | no | yes |
| handoff | off remote | 1 | no | yes, pinned |
| micro | off remote | 2 | yes | no |
| onekeys | behind 193 | 0 | yes | yes |
| plugin-craft | behind 37 | 0 | no | yes |
| prohibitions | off remote | 2 | no | yes |
| sandbox-lies | off remote | 1 | yes | yes |
| shell-gotchas | behind 97 | 0 | no | yes |

- Every tier clone is detached with HEAD equal to its local `live`. No clone
  holds a stash, a prepared merge, or a T-authored local-only commit: all nine
  unpublished tier commits carry the correct identity.
- Unpublished *memory* commits: cwd-safety 1, gitlore 3, handoff 1, onekeys 1,
  prohibitions 2, sandbox-lies 1. micro's memory repo and parent have no remote;
  ghmem's parent has none.
- "plugin" is the listing in `~/.claude/plugins/marketplaces/ddaanet`: entries
  carry no ref, so an install takes the default-branch tip; handoff alone pins a
  tag (`v0.15.0`); edify installs by `git-subdir`. `~/.claude/plugins/cache/`
  holds further recursive clones of the tier, install artefacts that never push.

**This list cannot cover clones on other machines** or outside
`/Users/david/code`; each holds the old history and behaves as 1.4 describes.

### 1.4 How a rewritten tier reaches a consumer

Read from the scripts and confirmed by experiment. No node or decision treats a
force-updated store remote; the one sentence on force-pushes
(`docs/references/merge-and-resolve.md:43-45`) is about the parent.

- **SessionStart** pins the tier at the recorded gitlink
  (`scripts/lib/session-tiers.sh:66`), runs `git fetch origin live` (`:83`) and
  classifies by two ancestry tests. A rewritten remote is neither ancestor nor
  descendant, so it reports "has diverged … Run /gitlore:merge … or
  /gitlore:push" (`:98`). It moves nothing.
- **`/gitlore:merge`** (`scripts/merge-memory.sh:53`) fetches
  (`scripts/lib/resolve-merge-stores.sh:75`), finds the remote not contained in
  HEAD (`:149`) and HEAD not contained in the remote (`:170`), and calls
  `gitlore_yield_merge … origin/live head-vs-remote HEAD` (`:173`). Only a dirty
  tier is refused first (`:163-168`).
- **`gitlore_prepare_merge`** (`scripts/lib/resolve-merge-state.sh:279-301`)
  checks the new `origin/live` out detached and runs
  `git merge --no-commit --no-ff <old HEAD>`. Nothing passes or needs
  `--allow-unrelated-histories`, because the histories are related. Both sides
  made the same changes since the base, so the merge is clean and `MERGE_HEAD`
  exists (`:302`).
- The directive tells the agent to dispatch the merger "now without asking
  first" (`:205-209`), and `continue-after-merge` commits
  (`scripts/resolve.sh:74`). The merge commit has the new tip as first parent
  and **the old tip as second parent**.
- **Any push** does the same without `/gitlore:merge`: `pre-push` and
  `/gitlore:push` share `gitlore_push_stores`; the tier push is refused as
  non-fast-forward, classified `diverged`, and yields the same merge
  (`scripts/lib/resolve-push.sh:146-185`). A plain `git push` of a consumer's
  parent is enough.

**Experiment.** A throwaway bats file under `$TMPDIR` loads the suite's own
helpers (`tests/helpers/{tier-fixtures,stub-synth,merge-memory}`), builds a bare
tier remote with one T-authored commit between two others, rewrites it on a
mirror with `git filter-repo --mailmap` and force-pushes it.

1. `merge-memory.sh` exits 1 with `gitlore: memory merge prepared`,
   `conflicted_files: []`, staged tree equal to the new tip's. The continuation
   lands a two-parent commit and `push-memory.sh` publishes it: the remote's
   `live` goes from 0 T commits back to 1, and from 4 commits to 7.
2. `push-memory.sh` run straight after the rewrite prepares the same merge.
3. The section 3 repoint, then `commit-memory.sh`, `merge-memory.sh` and
   `push-memory.sh`, ends with 0 T commits on HEAD, `live` and the remote.

So: **one un-migrated clone, anywhere, silently re-publishes all 55 commits and
doubles the history on its next merge or push, and the tooling instructs the
agent not to ask.** SessionStart's wording was read, not exercised.

### 1.5 Gitlinks

Each memory commit records a tier gitlink; each parent commit records a memory
gitlink. Counted over local refs: 348 memory commits across the 13 memory repos
record, or descend from a commit that records, a tier id the rewrite changes;
about 1,720 parent commits and 57 tags sit downstream of those.

- **Branch tips.** A memory tip naming an old tier id still works locally (the
  object is in the clone); a *fresh* recursive clone needs that commit from the
  tier remote. Nine marketplace-listed plugins have a default-branch tip in that
  position (all but onekeys), as does handoff's pinned tag.
- **Historical commits.** A dangling gitlink in an old memory commit breaks
  nothing in gitlore's own paths, which read only the index and HEAD pins. It
  breaks `git submodule update` on a checkout of that commit, and an install
  pinned to an old tag.
- **Installs.** `/plugin install` clones with `--recurse-submodules` (tier fact
  `plugin-recurse-clone.md`). For an id no advertised ref reaches,
  `git submodule update` falls back to fetching it by id; whether GitHub serves
  that, and for how long, is not established here. Treat it as unreliable.

## 2. Preconditions for any rewrite

1. **For A or H, decide before the in-flight rewrite pushes** (section 5).
2. **Quiesce.** No session live in any consumer, on any machine, from the
   force-push until that clone has crossed. A session's commit or push in an
   un-crossed clone is the 1.4 path.
3. **Empty the clones first.** Publish every unpublished tier commit (six
   clones) through each repo's own `/gitlore:push` **[partner]**, and commit or
   discard the three dirty tiers **[partner]**. The alternative is carrying
   commits across by cherry-pick (section 3, case c), once per clone.
4. **Keep the commit map.** `git filter-repo` writes `commit-map` (old id, new
   id, every commit). Store it under `plans/ddaanet-identity-rewrite/`; section
   3 and option A read it.

## 3. Bringing one clone across

Shared by options A, B and B+. Run per clone **[partner]**, before any
`/gitlore:merge`, `/gitlore:push` or parent `git push` in that repo. `MAP` is
the stored commit map.

```sh
R=/Users/david/code/handoff            # the consumer
MAP=/Users/david/code/gitlore/plans/ddaanet-identity-rewrite/commit-map
T="$R/memory/ddaanet"
( set -e          # no final `repointed` line: a check failed, nothing ran after
  test -z "$(git -C "$T" status --porcelain)"         # tier is clean
  OLD=$(git -C "$T" rev-parse HEAD)
  test "$OLD" = "$(git -C "$T" rev-parse live)"       # HEAD is live
  NEW=$(awk -v o="$OLD" '$1 == o { print $2 }' "$MAP")
  test -n "$NEW"                                      # else case c
  NEWMAIN=$(awk -v o="$(git -C "$T" rev-parse main)" '$1 == o { print $2 }' "$MAP")
  test -n "$NEWMAIN"                                  # main is on old history
  git -C "$T" fetch origin live main
  test "$(git -C "$T" rev-parse "$OLD^{tree}")" = \
       "$(git -C "$T" rev-parse "$NEW^{tree}")"       # same content
  git -C "$T" checkout --detach "$NEW"
  git -C "$T" branch -f live "$NEW"
  git -C "$T" branch -f main "$NEWMAIN"
  git -C "$R/memory" add ddaanet && echo "repointed to $NEW" )
```

Then the ordinary lockstep: an approved summary, `commit-memory.sh`, the parent
commit that records the memory gitlink, and the pushes. The memory commit is
required, not tidiness: SessionStart re-pins the tier at the recorded gitlink
every session (`session-tiers.sh:66`), so an uncommitted repoint is undone.
Staging the gitlink is what satisfies the pin guard, which reads the index
(`scripts/lib/index-compose-check.sh:211`) and otherwise reports "moved outside
/gitlore:merge" (`:273`). The trees are identical, so the root index does not
change and composition has nothing to project.

- **Case a, HEAD at the old tip:** `NEW` is the new tip. An id the map sends to
  itself (the 31-commit prefix) needs nothing.
- **Case b, HEAD behind:** `NEW` is HEAD's rewritten counterpart, an ancestor of
  the new `origin/live`; the next `/gitlore:merge` is an ordinary fast-forward
  with adoption.
- **Case c, local-only commits:** absent from the map. Map their base, check it
  out, `git cherry-pick <base>..<old HEAD>`, and require the resulting tree to
  equal the old HEAD's before moving `live`.

**Proof that this clone cannot re-import**, after the memory commit; all five
required:

```sh
git -C "$T" rev-list --count --author=t@e.c HEAD live main       # 0
git -C "$T" merge-base --is-ancestor HEAD origin/live; echo $?   # 0
git -C "$T" merge-base --is-ancestor live origin/live; echo $?   # 0
git -C "$T" merge-base --is-ancestor main origin/main; echo $?   # 0
test "$(git -C "$R/memory" rev-parse HEAD:ddaanet)" = \
     "$(git -C "$T" rev-parse HEAD)" && echo pinned
```

The `HEAD` and `live` ancestry lines are the tests both merge gates apply
(`resolve-merge-stores.sh:170`, `resolve-push.sh:152`); with both true neither
classifies the tier as diverged, and `gitlore_prepare_merge` refuses outright
(`resolve-merge-state.sh:279`). Old objects stay in the clone (reflog, and a
`refs/gitlore/compose-base` ref no current script reads) but are not pushed. No
gate reads the tier's local `main`; its line keeps a branch in the clone from
pointing into the old history.

## 4. Options

### A. Full cascade

Rewrite the tier, remap tier gitlinks through every memory repo, remap memory
gitlinks through every parent, retag.

1. Preconditions (section 2).
2. Rewrite a mirror of the tier with a mailmap; verify tree-for-tree equality
   against the original and 0 T commits; store the map. *Scratch only.*
3. For each of the 13 memory repos: rewrite a mirror, replacing every
   mode-160000 entry through the tier map; store that repo's map. *Scratch.*
4. For each parent: rewrite a mirror, replacing memory gitlinks through that
   repo's map; recreate the affected tags. *Scratch.*
5. **[partner] Irreversible, outward:** force-push the tier, then 12 memory
   remotes, then 11 parent remotes including default branches and 57 tags.
6. **[partner]** Reset every clone of every repo, on every machine, to the new
   history; reinstall every plugin.

- **Buys:** no dangling gitlink anywhere; every historical checkout and every
  old tag installs.
- **Costs:** rewrites the default branch and release tags of ten published
  plugins, so every installed copy and every third-party clone diverges; about
  2,070 commits change id; ids quoted in changelogs, issues and docs go stale;
  GitHub releases detach from moved tags. Published parent history is rewritten
  to re-pin memory, the act D46 rules out for the tooling
  (`docs/references/git-hooks.md:79`) — a one-off by hand is a different act,
  but the same cost argument applies. Protected branches may refuse the pushes.
- **Effort:** days, mostly verification and the long tail of clones; section 3
  does not suffice, since parents and memory repos need the same repoint.

### B. Rewrite the tier only

1. Preconditions (section 2).
2. Rewrite and verify on a mirror, store the map. *Scratch only.*
3. **[partner] Irreversible, outward:** `git push --force-with-lease` of `live`
   to the tier remote. `main` lies in the unchanged prefix and keeps its ids.
4. **[partner]** Section 3 in each of the 13 clones, each ending in a memory
   commit, a parent commit and their pushes.
5. **[partner]** A new handoff release and a marketplace bump for its pin.

- **Buys:** the right identity on the tier's `live`; nothing else rewritten.
- **Costs:** every historical memory commit keeps an old tier id that the remote
  no longer advertises. Between step 3 and each consumer's step 4, a fresh
  install of that plugin depends on GitHub serving an unreferenced commit; old
  tags stay in that state for good.
- **Effort:** half a day for 13 crossings; open-ended for other machines.

### B+. B with a staged archive ref — dominates B

Same as B, with two extra steps around the force-push:

- Before step 3, **[partner]** push the old tip to a second branch on the tier
  remote (for example `archive/live-pre-identity`). Outward, reversible.
- After every consumer has crossed and published, decide whether to delete that
  branch **[partner]**. Deleting is the irreversible step; until then every old
  gitlink stays fetchable and no install window opens.

Costs nothing over B and removes B's install window. While the branch exists the
T commits remain reachable in the repository, off `live`; keeping it forever is
a legitimate end state that trades "T is gone" for "every old tag installs".
gitlore reads only `live`, so the extra branch is inert to it.

### C. No rewrite

1. Confirm no `user.*` remains in any consumer's config (true on this machine).
2. Optionally **[partner]** add a `.mailmap` to the tier through an ordinary
   approved memory commit: `git log`, `shortlog` and `blame` then show the right
   name locally.
3. Fix the sources (section 6: G3 and probe hygiene).

- **Buys:** zero risk, no coordination, nothing to re-import, no interaction
  with the in-flight rewrite.
- **Costs:** the 55 commits keep `t@e.c`. GitHub does not apply `.mailmap` and
  attributes by author email, so they stay unattributed there.
- **Effort:** an hour.

### H. A for gitlore, B+ for the rest

gitlore and `gitlore-memory` are being rewritten anyway. Folding the tier map
into that pass gives those two repos A's result at little extra cost while the
other twelve consumers take B+. It exists only until the in-flight rewrite
pushes.

## 5. Interaction with the in-flight gitlore rewrite

`gitlore-memory` records tier gitlinks in 146 of its 209 commits; 114 are
affected by a tier rewrite.

- **A or H:** one pass. Rewrite the tier mirror first, then redo the
  `gitlore-memory` mirror with the tier map applied in the same filter run, then
  redo the gitlore mirror against the new memory map. Pushing the in-flight
  result first forces a second rewrite of both repos.
- **B or B+:** independent. The in-flight rewrite pushes whenever it is ready;
  `gitlore-memory` keeps old tier ids in its history like every other consumer,
  and its tip crosses by section 3.
- **C:** independent.

## 6. Does gitlore need a code change?

Section 3 is safe without one, but only for clones somebody remembers. The 1.4
path has no refusal, and consumers run the installed plugin, so a fix protects a
clone only after a gitlore release *and* a plugin update on that machine: if a
guard is wanted, the force-push follows the release.

- **G1, rewrite-aware take.** Before either yield
  (`resolve-merge-stores.sh:170`, `resolve-push.sh:181`), test whether the
  pending tree is the tree of a commit on the authority — the check section 3
  makes by hand; `git cherry` covers pending commits beyond it. A match means
  the authority was rewritten: repoint and stage the pin, never merge. Ancestry
  cannot tell a rewrite from a divergence; content identity can. SessionStart's
  message (`session-tiers.sh:98`) takes the same test.
- **G2, refusal only.** The same detection, ending in a refusal that names the
  manual procedure. Smaller; leaves the crossing manual.
- **G3, identity scrub.** Unset `GIT_AUTHOR_*` and `GIT_COMMITTER_*` beside the
  existing `--local-env-vars` unset, so a store commit never inherits a parent
  hook's author. Independent of A/B/C and cheap.
- **Probe hygiene.** No `cd "$P"` on an unchecked `mktemp`; a cwd-safety hook
  could refuse a bare `git config user.*`. Another repo: propose only.

G1 and G2 are design decisions for `docs/design.md`; under C only G3 applies.

## 7. Summary

| | A | B | B+ | C | H |
|---|---|---|---|---|---|
| T gone from the remote | yes | yes | on delete | no | on delete |
| Dangling old gitlinks | none | all | on delete | none | on delete |
| Install window | reinstall all | yes | no | no | no |
| Published history rewritten | 11 repos | none | none | none | gitlore |
| Re-import risk (1.4) | yes | yes | yes | no | yes |
| Couples to in-flight rewrite | one pass | no | no | no | one pass |
| Effort | days | half day | half day | hour | half day + |

## Open questions

1. **Clones on other machines.** Unknown count and state. Evidence: my human
   partner's own inventory; on each machine, the section 1.3 scan.
2. **Does GitHub serve an unreferenced commit by id, and until when?** Not
   tested. Evidence: after B's force-push on a scratch repository,
   `git fetch origin <old id>` from a fresh clone, repeated over days; or a
   GitHub statement. B+ makes the answer irrelevant until the archive branch is
   deleted.
3. **Is the tier public?** An anonymous `ls-remote` succeeds from this sandbox,
   whose proxy may add credentials. Evidence: the repository's settings.
4. **A second clone of a consumer already crossed elsewhere.** Its memory root
   fast-forwards to the new pin and SessionStart checks the tier out there while
   local `live` still names the old tip. `gitlore_repair_stranded_live` then
   reports "each moved … Run /gitlore:resolve"
   (`resolve-merge-stores.sh:242-252`); what `/gitlore:resolve` does next is not
   traced. Evidence: extend the experiment with a second clone.
5. **Mode-160000 remapping in `git filter-repo`** is assumed workable through a
   commit callback over `file_changes`; G1's detector is untried on real tier
   history. Evidence: a scratch run of each against a rewritten mirror.
6. **Does GitHub offer an author-email push rule on this plan?** It would be the
   only guard that also covers un-updated plugins. Evidence: the organisation's
   ruleset settings.
7. **`.mailmap` inside a tier** is unchecked against composition (evidence: a
   fixture run); 1.5's counts use local refs (evidence: fresh mirrors).
