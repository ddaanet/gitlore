## Brief: an interruption between `gitlore_prepare_merge` succeeding and `gitlore_write_merge_state` running leaves an orphaned `MERGE_HEAD` no gate can see

2026-08-12 — target: `gitlore` (this repo) · found from `edify`

Confirmed, recovered by hand, and re-verified against current `HEAD`
(`afb02b9`, today). `edify`'s `memory/ddaanet` tier hit a real, clean,
non-conflicting merge that a killed `push-memory.sh` run left half-landed:
`MERGE_HEAD` set, the merged result correctly staged, but no state file —
because `gitlore_yield_merge` calls `gitlore_write_merge_state` only
**after** `gitlore_prepare_merge` returns, and the interruption fell in
that window. The next invocation's own `checkout --detach` then silently
wiped the orphaned `MERGE_HEAD` (`remove_branch_state`, on a same-commit
no-op checkout — see [[reference_git_checkout_clears_merge_state]] in
`memory/ddaanet/`), and every retry after that repeated the same
"Already up to date." / "could not prepare the memory merge" misdiagnosis,
because `gitlore_prepare_merge` reads `pending=$(git -C "$mempath" rev-parse
HEAD)` — and `HEAD` was already sitting on the authority from the wiped
attempt.

**`afb02b9` (this repo, today) does not fix this** — I read it before
writing this brief, and re-checked line-by-line rather than trusting the
commit message. It fixes a related but distinct defect in the same
function: `gitlore_prepare_merge` used to leave `HEAD` detached on the
authority after *any* failed preparation, including the harmless case where
the ref was merely behind (nothing to merge, not diverged). That commit
adds an ancestor short-circuit before the checkout, restores `HEAD` on a
no-`MERGE_HEAD` failure, and — most relevant here — adds
`gitlore_check_head_live_agree`, called before every *push* attempt
(`scripts/lib/resolve.sh:590,658`), which refuses to publish a store whose
`HEAD` and local `live` disagree.

Two things remain true after `afb02b9`, both verified directly against the
current source, not inferred from the commit message:

1. **`gitlore_prepare_merge` still reads `pending` from `HEAD`, not from
   `live`** (`scripts/lib/resolve.sh:222`, unchanged by `afb02b9`). D17's own
   model treats `live` as the durable pointer to a store's real content and
   `HEAD` as transient — deliberately moved by this very function. Once
   `HEAD` has been displaced by *any* earlier event (an orphaned interrupted
   run being the obvious one), every later call keys off the wrong commit.
2. **`gitlore_detect_stale_merge_state` still keys entirely on the state
   file's presence, never on `MERGE_HEAD` itself**
   (`scripts/lib/resolve.sh:47-61`, unchanged). `docs/design.md` states the
   intended invariant plainly (quoted in `afb02b9`'s own diff): *"A crashed
   merge leaves the state file behind. Every gate guards on it."* That is
   false in exactly the window between `gitlore_prepare_merge` returning and
   `gitlore_write_merge_state` completing — the merge has genuinely started
   (real `MERGE_HEAD`, real staged content) with no state file yet.

### What `afb02b9` changed about the blast radius

For the **push** path (`gitlore_push_stores`), `gitlore_check_head_live_agree`
now runs before anything else, so a `HEAD`≠`live` orphan is caught up front
instead of silently misdiagnosed. But its remedy for one of the three
ancestry outcomes is itself a plain `checkout --detach live` — the exact
operation that destroys a clean, uncommitted `MERGE_HEAD` with no warning
that one might be sitting there. Confirmed by direct repro below: this is
not a hypothetical composition of two facts, it is the literal printed
remedy text executed as printed.

(The real `edify` incident, replayed against today's `afb02b9` logic, would
have hit the *other* ancestry outcome — `HEAD` and `live` had genuinely
diverged, neither an ancestor of the other, so `gitlore_check_head_live_agree`
would print "run /gitlore:resolve to reconcile them" rather than the
destructive one-liner. I checked this by computing `merge-base --is-ancestor`
both directions on the real, still-present commits — `cd0c389` and `285274f`
— after recovering the tier; neither is an ancestor of the other. The
destructive-remedy shape below is a distinct, still-realistic scenario, not
a literal replay, and I'm not claiming it's what I hit.)

For the **commit-time** sync path — `gitlore_sync_tiers_to_live` and
`gitlore_sync_memory_to_live`, invoked whenever the parent's pre-commit hook
processes dirty memory — there is **no equivalent pre-flight guard at all**.
Both functions attempt `push . HEAD:live` directly; only on failure do they
call `gitlore_classify_refusal "$path" HEAD live`, and route straight into
`gitlore_yield_merge` (→ `gitlore_prepare_merge`) on `diverged` — with no
call to `gitlore_check_head_live_agree` on that branch at all
(`scripts/lib/resolve.sh`, the `elif gitlore_check_head_live_agree …` arm
only fires when the refs *don't* diverge). An orphaned `MERGE_HEAD` from an
earlier interruption sitting on a displaced `HEAD` is silently discarded by
`gitlore_prepare_merge`'s own checkout here, with no protective message
reaching the operator at any point — the sharper, still fully exposed
instance of the same underlying defect.

### Decisions

- **Read `pending` from `live`, not `HEAD`**, in `gitlore_prepare_merge`.
  This is the actual root cause; both symptoms above are consequences of it,
  not independent bugs.
- **Make the stale-merge guard check `MERGE_HEAD` directly.**
  `gitlore_detect_stale_merge_state` needs a third outcome —
  `MERGE_HEAD` present, state file absent — routed to its own
  manual-intervention message (there's no `changed_files`/`conflicted_files`
  briefing to hand a merger sub-agent, so it can't be `abort-then-retry`
  as-is, but it should name `MERGE_HEAD`'s value as the pending commit that
  needs re-merging rather than reporting "clean").
- **Or, more directly: write the state file before the risky work, not
  after.** Reordering `gitlore_yield_merge` — write an in-progress marker
  immediately before calling `gitlore_prepare_merge`, upgrade it to the full
  state file on success — makes any interruption after the checkout always
  leave something the guard can see, restoring the design doc's stated
  invariant instead of leaving it aspirational for one specific window.
- Either of the above closes the gap generally, including the unprotected
  commit-time path — a pending-source fix or a `MERGE_HEAD`-aware guard is
  effective wherever `gitlore_prepare_merge` is called from, unlike
  extending `gitlore_check_head_live_agree` to more call sites, which would
  only add advisory coverage one caller at a time.

### Constraints

- Not fixable from the `edify` session that found it, same convention as
  [[brief-index-compose-drops-unterminated-final-line]].
- Already recovered by hand in `edify`: verified `git write-tree` matched a
  fresh `git merge-tree --write-tree <authority> <pending>` (nothing lost),
  restored `MERGE_HEAD`/`MERGE_MSG`, hand-wrote a matching state file via
  `gitlore_write_merge_state` (so the real `continue-after-merge`
  continuation did the commit, compose, and publish — not a hand-rolled
  substitute), then landed the corresponding root-memory commit through the
  normal FR11-gated flow. Nothing here is blocked on this fix landing.

### Rejected approaches

- Fixing only `gitlore_check_head_live_agree`'s message wording (e.g. "you
  may lose an in-progress merge, check first"). Advisory text doesn't cover
  the commit-time path, which never reaches that function at all on the
  `diverged` branch. It's also not this codebase's style elsewhere —
  `afb02b9`'s own fix restores `HEAD` on failure programmatically rather
  than documenting the restore command for a human to run.
- Extending `gitlore_check_head_live_agree` to the commit-time call sites
  as the fix. It would close the specific reproduced case, but leaves the
  actual root cause (`pending` read from `HEAD`) in place for any caller
  that doesn't remember to add the same pre-flight check — the state-file
  or pending-source fix is structural where this is per-site.

### Additional context

**Repro** (constructed to exhibit the ancestry shape verified above; not a
literal replay of the `edify` incident — see the parenthetical above for
why). Verified clean end to end, no setup errors:

```sh
G=/Users/david/code/gitlore/scripts/lib
. "$G/log.sh"; . "$G/util.sh"; . "$G/resolve.sh"

M=$(mktemp -d)
git init -q "$M/store"
printf 'a\n' > "$M/store/a.md"
git -C "$M/store" -c user.email=r@r -c user.name=r add -A
git -C "$M/store" -c user.email=r@r -c user.name=r commit -qm base
B=$(git -C "$M/store" rev-parse HEAD)
git -C "$M/store" branch live "$B"
git -C "$M/store" checkout -q --detach live

printf 'a\nlocal1\n' > "$M/store/a.md"
git -C "$M/store" -c user.email=r@r -c user.name=r commit -qam "local work 1"
printf 'a\nlocal1\nlocal2\n' > "$M/store/a.md"
git -C "$M/store" -c user.email=r@r -c user.name=r commit -qam "local work 2"
git -C "$M/store" push -q . HEAD:live   # advance local live; HEAD stays there too

# Simulate an interrupted run: gitlore_prepare_merge invoked with a STALE
# authority (B, an ancestor of live) — e.g. computed before live advanced
# further, or against a since-superseded remote tip.
gitlore_prepare_merge "$M/store" "$B" >/dev/null
echo "MERGE_HEAD after prepare: $(git -C "$M/store" rev-parse -q --verify MERGE_HEAD || echo none)"
# → a real sha, not none. HEAD is now $B (an ancestor of live) — the
#   interrupted run's checkout, with the caller dying before write_merge_state.

gitlore_guard_stale_merge_state "$M/store" && echo "guard: clean (blind spot)"
gitlore_check_head_live_agree "$M/store" "store" || echo "check_head_live_agree: refused"

git -C "$M/store" checkout -q --detach live   # the printed remedy, verbatim
echo "MERGE_HEAD after remedy: $(git -C "$M/store" rev-parse -q --verify MERGE_HEAD || echo GONE)"
```

Actual output from running this:

```
MERGE_HEAD after prepare: a9399c69c24544a68769e2219b77bf2fd297bec6
guard: clean (blind spot)
gitlore: store's HEAD is not at its local 'live' (HEAD bcae81f, live a9399c6), so nothing was published. Put HEAD back on 'live': git -C "…/store" checkout --detach live
check_head_live_agree: refused
MERGE_HEAD after remedy: GONE
```

**Real-world shape it came from.** `edify`'s `memory/ddaanet` tier,
`push-memory.sh` invoked via `/gitlore:push` today, before `afb02b9` landed.
First run hung past a 2-minute tool timeout and was killed; it had gotten
far enough to `checkout --detach origin/live` and complete a clean `merge
--no-commit --no-ff` of the local unpublished tip (`285274f…`, two commits)
into the remote's tip (`cd0c389…`), staging real content (a genuine 3-way
blend in the tier's own `MEMORY.md`, confirmed identical to a fresh `git
merge-tree --write-tree` recomputation), but died before
`gitlore_write_merge_state` ran. The second run misread `pending` as `HEAD`
(already on the authority from run one), got "Already up to date.", and
reported "could not prepare the memory merge... Inspect the memory
worktree" — a message that named the right worktree but gave no actionable
path back, since every subsequent invocation would have repeated the same
misdiagnosis. Recovery required reading this repo's own source to
reconstruct the missing state file by hand and re-enter the real
`continue-after-merge` continuation, rather than anything `gitlore` itself
could report a path out of.
