# Minor findings pass — code and tests

## Item 1 — `gitlore_adopt_recovered_merge` short-circuit

**Changed:**
- `scripts/lib/resolve.sh`: `gitlore_adopt_recovered_merge` — added a
  short-circuit right after `[ "$rel" != "$own_path" ] || return 0`: reads the
  tier's HEAD and the enclosing index's gitlink and returns 0 when they already
  agree, with a comment explaining why (a second up projection would overwrite a
  root-index edit made since the pair was adopted). Extended the function's
  header comment with one sentence recording the short-circuit.
- `tests/resolve_recovery.bats`: added
  `recovery: adoption is a no-op when the enclosing index already records the tier's HEAD`,
  placed after
  `recovery: the branch where HEAD already carries the landed merge stages it too`.

**Red run (unchanged code), verbatim:**
```
not ok 15 recovery: adoption is a no-op when the enclosing index already records the tier's HEAD
# (in test file tests/resolve_recovery.bats, line 421)
#   `cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/edited-index"' failed

bats: 22 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.tjXdFC
```
Reds on the MEMORY.md content assertion, not on a fixture error — confirms the
fixture reaches the compose-up path before the fix exists.

**Green after the fix:** `tests/resolve_recovery.bats` — 23 passed, 0 failed.

## Item 2 — argue the fatal `agent_id` read in index-sync-pre.sh

**Changed:** `scripts/cc-hooks/index-sync-pre.sh` — added a 7-line comment above
the `agent_id=$(jq -r '.agent_id // empty' <<<"$payload")` read (no
`|| agent_id=""` fallback added, per instructions), arguing: the payload already
parsed at the `tool=` read above so this read cannot fail on shape; a PRE hook
dying here has written no baseline, so nothing is stranded — the post hooks find
no stash/stamp and skip the batch, same outcome as a non-index call; and the
exit-code consequence — `jq` exits 5 on unparseable input, a `PreToolUse` hook
blocks only on exit 2, so a dead read here never blocks the observed
Write/Edit/Bash.

No test required for this item (it documents a design choice, not new behavior).

## Item 3 — test the `|| agent_id=""` fallback

**Changed:**
- `tests/cc_hook_index_compose.bats`: added
  `an unparseable payload still composes on the unkeyed baseline (fallback proof)`,
  after `an index-touching batch composes and reports on both channels`. Seeds
  the unkeyed compose stamp via `pre`, feeds garbage stdin
  (`printf "not json" | bash "$HOOK"`, via
  `run --separate-stderr bash -c '...' _ "$HOOK"` to keep the hook's own stdout
  JSON isolated from jq's stderr diagnostic), and asserts exit 0, the unkeyed
  stamp consumed, and valid JSON carrying `systemMessage`. A
  `# shellcheck disable=SC2016` line is needed immediately above — shellcheck's
  bats-mode parser recognizes the bare `run bash -c '...$1...' _ "$X"` idiom
  used elsewhere in the suite, but not the same idiom prefixed with
  `--separate-stderr`; confirmed as a false positive by testing both forms
  directly with `shellcheck -x`.
- `tests/index_sync.bats`: added
  `post: an unparseable payload still propagates on the unkeyed baseline (fallback proof)`,
  after `post: propagates a CHANGED index hook into the file's frontmatter`.
  Seeds a stash directly (mirroring the neighbouring `post_stdin` cases), feeds
  garbage stdin to `index-sync-post.sh`, asserts exit 0, `description:`
  propagated, and the stash consumed.

Both cases carry a 2-3 line comment above them naming the state that reds them
(the `|| agent_id=""` fallback removed).

**Red run (fallback temporarily removed from both hooks), verbatim:**
```
not ok 6 an unparseable payload still composes on the unkeyed baseline (fallback proof)
# (in test file tests/cc_hook_index_compose.bats, line 167)
#   `[ "$status" -eq 0 ]' failed

bats: 24 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.aaLQqr
```
```
not ok 21 post: an unparseable payload still propagates on the unkeyed baseline (fallback proof)
# (in test file tests/index_sync.bats, line 308)
#   `[ "$status" -eq 0 ]' failed

bats: 84 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.gI61F7
```
Only the new case failed in each file. Fallback restored in both files (`diff`
against a pre-edit backup confirmed byte-identical restoration).

**Green with fallback restored:**
- `tests/cc_hook_index_compose.bats` — 25 passed, 0 failed.
- `tests/index_sync.bats` — 85 passed, 0 failed.

## Item 4 — fix wrong comments in tests/commit_memory.bats

**Changed:**
- (a) Rewrote the born-green comment in
  `a tier moved sideways off its pin aborts the commit`: it now says "is checked
  out at" stays green under the mutation (the ahead wording at
  `index-compose.sh:358` carries the same phrase, verified by grep), and names
  the negative `!= *"ahead"*` assertion near the end of the case as what
  actually reds.
- (b) Rewrote all four `CLAUDECODE` comments
  (`the rc-1 user arm does not tell a user to retry a commit that succeeded`,
  `the rc-2 user arm tells a user to retry`,
  `the pin-abort user arm tells a user to retry`, and one more of the same
  shape) to state: a bats run inherits `CLAUDECODE` from the invoking shell, and
  a subagent dispatch exports it as 1, so it is unset explicitly to read the
  user arm regardless of the ambient environment. Kept the
  `tests/git_hook_memory_pre_commit.bats:29` reference — checked that line still
  does `unset CLAUDECODE` in the matching case.

**Green:** `tests/commit_memory.bats` — 23 passed, 0 failed.

## Item 5 — fix predicate description in tests/resolve_recovery.bats

**Changed:** Rewrote the comment above
`recovery: the same recovery for the memory root stages nothing in the parent repo`
(now at line ~425, shifted by Item 1's insertion). It no longer claims a
`gitlore_tier_paths` clause; it now states the actual predicate — root MEMORY.md
present AND the store's path is NOT the superproject's own
`submodule.gitlore-memory.path` — consistent with the later comment (now ~lines
501-515) above
`recovery: a host project that keeps a root MEMORY.md is not a memory store`,
and with `gitlore_adopt_recovered_merge`'s own header comment in
`scripts/lib/resolve.sh`. Kept the "no longer reds under [a predicate missing
the exclusion clause]" paragraph — verified it is still true (the case is gated
by the parent repo having no root MEMORY.md at all, clause 1, independent of
which second clause the predicate carries) — and reworded its opening clause to
stop referring to the now-removed `gitlore_tier_paths` framing.

**Green:** `tests/resolve_recovery.bats` — 23 passed, 0 failed (same run as Item
1's).

## Item 6 — tests/git_hook_pre_commit.bats

**Changed:**
- (a) `the parent pre-commit hook aborts on an off-pin tier`: added
  `[[ "$output" == *"moved off the commit the memory store records for it"* ]]`
  after the status assertion (the hook runs under plain `run`, so stderr is in
  `$output`), with a one-line comment. Confirmed the header string against
  `gitlore_sync_memory_to_live` at `scripts/lib/resolve.sh:1050`.
- (b) `an aborted compose keeps the approved summary usable`: moved
  `head_before=$(git -C memory rev-parse HEAD)` above `chmod a-w memory/beta`.

**Green:** `tests/git_hook_pre_commit.bats` — 18 passed, 0 failed.

## Lint

`scripts/lint-shell.sh` — `lint-shell: 138 files clean`.

## Deviations

None. All six items completed as specified.
