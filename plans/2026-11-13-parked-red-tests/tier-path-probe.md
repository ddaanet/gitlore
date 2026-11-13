# Probe: unvalidated `submodule.*.path` in `gitlore_tier_paths`

Repository untouched. Scratch: `/tmp/claude/gitlore-fanout/probe-paths/`
(probe.bats, a `helpers` symlink to the repo's `tests/helpers` so `setup.bash`'s
relative sources resolve, and `g*.XXXX` scratch git dirs). git 2.47.3, Linux.
Tags: **[run]** = executed here, **[read]** = from reading code.

## Verdict

The finding holds, and the reach is far larger than the gate cleanup:

- `..` escapes [run]. An absolute path does not, because every consumer builds
  `"$mempath/$tier"`, so `/etc` becomes `memory//etc`, which is inside the store
  [run, test 1].
- Newline injection is a second escape route, and it gets past both proposed
  fixes as stated [run].
- Worst effect reproduced: `gitlore-push`, and so also the parent's `git push`
  through pre-push, which calls the same `gitlore_push_stores` [read], creates a
  `live` branch at HEAD in an unrelated repository and pushes it to that
  repository's own `origin`. Commits that were never pushed are published, exit
  0, and stdout says nothing [run, test 3].
- A `.gitmodules` entry with no gitlink in the index is treated as a full tier
  everywhere. Every reproduction uses exactly that shape, since git refuses a
  gitlink at `..` [run].
- **No guessing is needed.** `path = ..` names the parent repository itself.
  `gitlore-push` then creates `live` at the parent's HEAD and pushes it to the
  parent's origin: the parent's unpushed commits are published on a branch
  nobody asked for [run, probe "bare '..'"]. A dirty parent also counts as a
  dirty tier, which blocks every memory commit [read].
- **A symlink route gets past fix A.** Commit a symlink `memory/s -> ../..` and
  give `.gitmodules` the path `s/victim-…`. The path has no `..` component, yet
  the push publishes the victim's HEAD exactly as before [run, probe "symlink"].
  git refuses a gitlink at `s/x` while `s` is a tracked symlink
  (`'s/x' appears as both a file and as a directory`) [run], so B closes this
  route and A does not.
- The victim's HEAD stays on its branch after the push; there is no detach
  [run].

## Consumer table

"Reach" assumes the path is `../../victim`, where `victim` is any repository (or
for some rows any directory) at a guessable location relative to `memory/`.
Every git-acting loop guards with `[ -e "$mempath/$tier/.git" ]`, so a git act
needs the victim to be a real repo. A file read only needs the file to exist.

| file:line | action on `$mempath/$tier` | reach with `../../victim` |
|---|---|---|
| scripts/lib/session-gate-cleanup.sh:33 (SessionStart, automatic) | `rm -f` of the hook, `git config --unset gitlore.hooksDir` | Deletes the victim's `pre-commit` only if it holds gitlore's wrapper line, and unsets its `gitlore.hooksDir` [run, test 4] |
| scripts/lib/session-tiers.sh:144 (SessionStart, automatic) | `submodule update --init -- "$tier"` when no `.git` (git refuses: outside repository [run]); `git fetch origin live` in the victim (writes FETCH_HEAD and objects, network to the victim's origin); rev-parse reads; position reports into context | Network fetch and object writes in any repo; its branch and position text reaches the session [read] |
| scripts/lib/resolve-push.sh:159 (gitlore-push, pre-push) | `gitlore_ensure_live` (`branch live HEAD`), `gitlore_repair_stranded_live` (`push . HEAD:live`), `fetch`, **`push origin live`**, and a take via `gitlore_merge_stores` | Creates a `live` branch in the victim and **publishes its HEAD to its origin** [run, test 3] |
| scripts/lib/resolve-push.sh:180 | second pass: `push origin live` if `live` is not on origin | same as above [read] |
| scripts/lib/resolve-take-tiers.sh:39 (take: /gitlore:merge, push) | `gitlore_take_tier` → `merge_one_store`: fetch, adopt a `live` ahead, ff/checkout, merge preparation, carrier repair commit | Can move the victim's HEAD and working tree when its origin has a `live`, e.g. when the victim is another gitlore store. With no remote `live` it does adopt work and nothing else; that branch is what ran in test 3, whose stderr has git's `couldn't find remote ref live` [read; run only on the no-`live` path] |
| scripts/lib/resolve-take-tiers.sh:71 | `gitlore_tier_take_refused`: status read; refusal text | DoS: a dirty victim blocks `/gitlore:merge` [read] |
| scripts/lib/resolve-sync-tiers.sh:56 (gitlore-commit) | `add -A` + `commit -m <section>` in the victim, then `git -C mempath add -- "$tier"` (git refuses outside the repo → return 1) | Commits the victim's entire working tree, but only if the approved summary has a `== ../../victim ==` section [read] |
| scripts/commit-memory.sh:128,171,199,61,73 | stale-merge guard, `status --porcelain` in the victim, section matching | A dirty victim forces `store '../../victim' has changes and no section`: DoS of every memory commit, or a lure into the sync above [read] |
| scripts/push-memory.sh:86 | `store_state`: rev-parse reads | read only [read] |
| scripts/lib/resolve.sh:78 `gitlore_memory_stores` | lists `$mempath/$tier` to its callers | every caller of the store list inherits the victim [read] |
| scripts/lib/util-merge-state.sh:87 | `gitlore_store_mid_merge`: reads MERGE_HEAD state | a mid-merge victim blocks the root flows [read] |
| scripts/lib/resolve-sync-memory.sh:113,141,211 | `diff --cached -- "$tier"` in mempath (git refuses outside the repo), stale guard, status of `MEMORY.md` | reads, error noise [read] |
| scripts/lib/resolve-merge-prepare.sh:48,246 | gitlink checks via `rev-parse "$incoming:$tier"`, `git add -- "$tier"` in mempath | refused by git outside the repo [read] |
| scripts/lib/resolve-adopt-report.sh:147, resolve-unresolvable.sh:161 | `rev-parse ":$tier"` in mempath (misses), victim HEAD reads, report text | read [read] |
| scripts/lib/index-compose-check.sh:24,257,282,298 | mounted-set membership, pin relation, take-refused status | read. Also `mounted` is what admits a manifest entry (rule 2) [read] |
| scripts/lib/index-compose-dangling.sh:55 | membership | read [read] |
| scripts/add-tier.sh:144 | name collision check | none [read] |
| scripts/resolve.sh:226,246 (via `gitlore_memory_stores`) | stale-merge guard; `gitlore_ensure_live` + `check_store_gates`: `push . HEAD:live`, then a push to origin or a prepared merge (`gitlore_yield_merge`) in the victim | the same publish as the push row, plus a merge prepared inside the victim on divergence [read] |
| scripts/lib/resolve-merge-stores.sh:42,77 (`gitlore_guard_every_store`), merge-memory.sh:62 | guards, then `gitlore_merge_stores` → the take row | as the take row [read] |
| scripts/lib/resolve-adopt.sh:141, resolve-merge-stores.sh:232 (reached from the take) | `checkout -q --detach live` in the tier | moves the victim's HEAD onto `live` whenever `live` differs from HEAD. When ensure_live made `live` at HEAD, the test-3 shape, no detach happened [run] |
| scripts/git-hooks/pre-push:61 | `gitlore_push_stores` | the push row, on every parent `git push` [read, grep] |
| index-compose-dangling.sh:116, index-sync.sh:160, cc-hooks/index-sync-pre.sh:26, add-tier.sh:312 | the manifest file path itself (`$mempath/.gitlore-tiers`), or `gitlore_active_tiers` entries used as text | the file is fixed inside the store; entries are only read [read] |
| **`gitlore_active_tiers`** (`.gitlore-tiers`, the same untrusted store content): index-compose-project.sh:144,185,305, index-compose-orphans.sh:25, index-compose-pending.sh:72, index-sync.sh:169, session-diagnostics.sh:66, util-config.sh:76 | reads `$mempath/$tier/MEMORY.md`, frontmatter description, stamps | Together with a `.gitmodules` entry, one compose pass copies the victim's `MEMORY.md` bullet lines into root `memory/MEMORY.md`, which the next memory commit and push publish. The victim file is not written; the pass returns 1 on its second-pass check, but the root write from pass 1 stays [run, test 2]. `gitlore_active_tier_scopes` puts the victim's `MEMORY.md` description into SessionStart context [read]. Control with the climb only in `.gitlore-tiers` and no `.gitmodules` entry: rule 2 refuses ("not mounted"), and root `MEMORY.md` is not written [run]. The SessionStart consumers (`gitlore_active_tier_scopes`, session-diagnostics.sh:66) do not go through rule 2 and read the victim's `MEMORY.md` frontmatter whenever `$mempath/$tier/.git` exists. That stays open under both fixes [read] |

Path shapes other than `..` [run unless marked]:

- **Absolute `/x`**: prefixed to `memory//x`, inside the store.
  `git -C mempath … -- /x` is refused as outside the repository.
  `rev-parse ":/x"` parses as a commit-message search (`:/<regex>`), so a pin
  lookup can return an unrelated commit [read].
- **Leading `-`**: every use is after `--` or prefixed with `$mempath/`, so
  there is no option injection [read]. git fsck rejects it on its own
  (`gitmodulesPath`).
- **Newline**: `path = "inside\n../../elsewhere"` comes out of
  `gitlore_tier_paths` as two lines, `inside` and `../../elsewhere` [run, test
  1]. Every consumer reads line by line.

## What git refuses on its own [all run]

- `git config -f .gitmodules -z --get-regexp` returns `../../victim`,
  `/abs/victim`, `-leading`, `nl⏎../../victim2` and `ok/nested` verbatim.
- `git fsck --strict` and a `receive.fsckObjects` remote accept
  `path = ../../victim`, absolute paths and newline paths. They reject only a
  path starting with `-` (`gitmodulesPath`) and a submodule *name* containing
  `..` (`gitmodulesName`). So the hostile `.gitmodules` passes a fsck-checking
  host. Whether GitHub's checks go further was not tested.
- `git submodule status` silently skips entries with no gitlink.
  `git submodule update --init -- ../../victim` fails with
  `'../../victim' is outside repository`.
- Gitlinks: `update-index --cacheinfo 160000,…` refuses `../../victim`, `../x`,
  `/abs/x`, `a/./b`, `a//b`, `a/.git`, and a newline path. It accepts `-lead`.
  `git mktree` refuses `..` and any entry containing `/`.
- **The gap**: a nested tree whose entry is `in⏎..`, holding a gitlink `x`,
  gives index path `in⏎../x`. It passes `fsck --strict`, is accepted by a
  `receive.fsckObjects` remote, and `read-tree` and `checkout` take it (checkout
  rc=0; `ls-files -s` shows `"in\n../x"` as a stage-0 gitlink). Split on the
  newline it becomes `in` and `../x`, which escapes one level (to `memory/../x`,
  a path in the parent repo). A deeper climb is impossible because `..` cannot
  be a tree entry.
- **No gitlink needed**: a `.gitmodules` entry with no mode-160000 index entry
  is listed by `gitlore_tier_paths` and acted on by every consumer. Tests 2–4
  use only that shape.

## Reproduction

Run with
`cd /Users/david/code/gitlore && bats /tmp/claude/gitlore-fanout/probe-paths/probe.bats`;
all 8 pass (tests 1–4 reproduce; tests 5–8 are the follow-up probes cited
above). While this ran, `git status` showed `tests/commit_pin_guard_yield.bats`
and `tests/release_fix_unresolvable.bats` modified. This probe edited neither,
so another session is probably working in the tree. Fixture:
`make_parent_with_memory`, plus a memory commit adding
`submodule.evil.path = ../../victim-<tmp>` to `memory/.gitmodules`, pushed to a
bare memory remote. The victim is `$(dirname $TMP_REPO)/victim-<tmp>`: one
commit ("private, never pushed") and an origin bare repo with no branches.

Test 3 runs `bash scripts/push-memory.sh`:

```
status=0
stdout:
stderr: fatal: '../../victim-gitlore-test.6HEAhB' is outside repository at '/tmp/claude-1000/gitlore-test.6HEAhB/memory'
fatal: couldn't find remote ref live
fatal: '../../victim-gitlore-test.6HEAhB' is outside repository at '/tmp/claude-1000/gitlore-test.6HEAhB/memory'
```

After it, `git -C $VICTIM rev-parse live` equals the victim's HEAD, and so does
`refs/heads/live` on `$VICTIM_REMOTE`, which had no refs before. Exit 0; the
only output is git's stderr noise.

Test 2 (`.gitlore-tiers` lists the climb, the victim's `MEMORY.md` holds
`- [secret](secret.md) — a private repo hook line`), after
`gitlore_compose memory`:

```
status=1
root index line '../../victim-…/secret.md' has a prefix naming no mounted tier — …
--- root MEMORY.md:
# memory
- [secret](../../victim-gitlore-test.wJhStv/secret.md) — a private repo hook line
```

The victim's `MEMORY.md` checksum is unchanged.

Test 4: after `gitlore_retire_store_gates memory`, the victim's wrapper
`pre-commit` is gone and its `gitlore.hooksDir` is unset.

## Fix comparison

None of the "closes" claims below were run against a shadowed
`gitlore_tier_paths`. They are [read] reasoning from the git refusals that were
[run] above.

**(A) Drop absolute paths and paths with a `..` component.**

- Closes every literal `..` row above, bare `..` and a trailing `/..` included,
  if the check is per component. Absolute paths need no closing.
- Does not close the symlink route: a tracked `s -> ../..` plus path `s/victim`
  has no `..` component and still escapes [run]. Closing it in A would mean
  resolving each path's realpath against the store, which is more code and racy.
- Does not close the newline route. `in⏎../x` has components `in⏎..` and `x`,
  neither of which is `..`, and it still splits into `../x` downstream. A must
  also drop any path containing a newline, and the check has to run on the
  NUL-delimited value before printing.
- Breaks nothing legitimate: a real tier path is relative and normalized,
  because git will not stage a gitlink otherwise.
- Cost: one `case` in the read loop, about 5 lines plus a stderr notice so a
  dropped entry is not silent.
- Leaves a `.gitmodules` entry with no gitlink treated as a tier, e.g. `x`
  pointing at whatever `memory/x/.git` exists, such as a nested repo a user
  cloned into the store. The reach is inside the store, and the push row still
  applies to it.

**(B) List only `.gitmodules` paths that are gitlinks (mode 160000) in the
memory index.**

- Closes every `..` and absolute row, because git refuses such index paths
  ([run] above). It closes the symlink route, since git will not put a gitlink
  under a tracked symlink [run]. It also closes "registered but never a
  gitlink".
- Does not close the newline route either. The nested-tree gitlink `in⏎../x` is
  a real index entry. B also has to drop newline paths.
- Legitimate states:
  - Mid-mount: `git submodule add` writes the gitlink and `.gitmodules`
    together, and add-tier reads `gitlore_tier_paths` only at :144, before the
    add [read]. So add-tier is not broken.
  - "No stage-0 gitlink (mid-mount, or removed)", as commented at
    index-compose-check.sh:327 and resolve-adopt.sh:69: those consumers already
    treat it as "no pin" and skip.
  - A root merge with a conflicted gitlink has it only at stages 1–3. B must
    match any stage (`ls-files -s -z`, mode field, ignore the stage), or a
    conflicted tier vanishes from the resolve flows mid-merge.
  - An unmaterialized tier keeps its gitlink, so it is fine.
- Cost: one `git -C mempath ls-files -s -z` plus a set intersection, about 10–15
  lines. It also depends on mempath being a usable repo, which every caller
  already assumes.
- Runtime: one more fork per call. `root_change_is_tier`
  (commit-memory.sh:61,73) calls it inside nested per-entry and per-pointer
  loops, so a commit with many changed `MEMORY.md` lines pays that fork once per
  pointer. Hoisting the list once per run there is cheap.
- Test fixtures: a grep found no test that writes a `memory/.gitmodules` entry
  without staging a gitlink; the `.gitmodules` hits are reads [run, grep]. So B
  is not expected to change an existing fixture's tier set [read].

**Recommendation: B, with a newline drop, and A's `..` check kept as a cheap
second line.** A alone is insufficient even with the newline drop, because of
the symlink route [run]. B is required.

- B ties "is a tier" to what git itself validates, the index's verify_path. That
  covers every path-shape case without gitlore keeping its own list of bad
  forms, and it also removes the "a `.gitmodules` line alone makes a tier" reach
  that A leaves.
- The newline drop is needed under either fix and closes the one shape git
  accepts in the index.
- A's check costs one `case` line. It is optional under B, since git already
  refuses those index paths, but it makes the function's contract readable
  without knowing git's index rules.

Separately, `gitlore_active_tiers` needs no validation of its own once it is
filtered against the validated `gitlore_tier_paths`. Today only compose rule 2
does that, and only after the pass has already read the files (test 2). Routing
every `gitlore_active_tiers` consumer through that intersection is a design
change to propose, not part of this fix.

Not covered, out of scope: `.gitmodules` `url` is equally
contributor-controlled, and SessionStart's `submodule update --init` clones from
it.
