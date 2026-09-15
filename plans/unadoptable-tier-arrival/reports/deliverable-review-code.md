# Deliverable review — code

## Scope reviewed

Range `e60ff38..HEAD`. Every changed function was read whole, in its surrounding
context:

- `scripts/lib/index-compose.sh`: `gitlore_weld_tail`, `gitlore_welded_path`
  (228–265), `gitlore_compose_check_index` (267–299), `gitlore_repair_index`
  (301–453), `gitlore_repair_tier_file` (455–462), `gitlore_compose_problems_in`
  (464–478), plus `gitlore_compose_check` and `gitlore_compose_up`, which these
  functions rely on.
- `scripts/lib/resolve.sh`: `gitlore_sync_memory_to_live` (978–1254, the rc 1
  arm is 1099–1153), `gitlore_push_stores` (1308–1534), `gitlore_merge_stores`
  and `gitlore_merge_one_store` (1559–1707), `gitlore_adopt_advanced_live`
  (1804–1837), `gitlore_adopt_tier_into_root` (1865–1883),
  `gitlore_adopt_repair_arrival` (1900–1968), `gitlore_adopt_commit_repair`
  (1976–1985), `gitlore_adopt_report_refusal_and_walk_back` and
  `gitlore_adopt_walk_back_tier` (1993–2020),
  `gitlore_adopt_stage_pair_and_commit` (2026–2046). Also
  `gitlore_adopt_recovered_merge`, to check which callers reach
  `gitlore_compose_up`.
- `scripts/resolve.sh`: the whole file (503 lines). That covers
  `compose_merged_indexes`, `rest_unadopted_tier`, `push_or_report`, the
  `continue-after-merge` dispatch, `check_store_gates` and the gate order.
- `scripts/cc-hooks/memory-commit-batch.sh`: 100–121.
- Callers checked for the errexit context: `scripts/merge-memory.sh:53` (bare
  call), `scripts/commit-memory.sh:66` (bare call),
  `scripts/git-hooks/pre-commit:68` (`|| exit $?`), plus every caller of
  `gitlore_merge_stores` and `gitlore_compose_up`.

Checks run:

- `shellcheck -x` on all four files: clean.
- Grep of the added lines for citations of `plans/`, `memory/`, slice or item
  ids, runbook, K/S/D ids or line numbers: none.
- Probe of `gitlore_repair_index`. Inputs: a three-bullet weld, two stray lines
  with a whitespace-only line in the region, a differing duplicate where the pin
  lacks the second line, an identical duplicate as an unterminated last line, a
  guarded weld (target missing), a duplicate at the end with a stray before it,
  and a weld hiding a duplicate. All ran under `set -euo pipefail` with the tier
  directory named `tier dir`, and every repaired output passed
  `gitlore_compose_check_index`.
- Probe of `gitlore_compose_problems_in`. The `$mempath` was `/x/my mem*[a]`,
  with tiers `t`, `t b` and `tt`, a decoy `/x/my memZa/t/...` line and a rule 3
  line. Each file matched only its own lines, so glob characters are taken
  literally and a tier name that prefixes another is not confused with it.

Checked with no defect found:

- **Errexit.** Each new call is either a condition, `|| rc=$?`, or
  `|| return 1`. `compose_merged_indexes` is called bare, and its new
  `[ -n "$merged_tier" ] && …` is not the last command of a list whose failure
  would trip errexit.
- **Bash 3.2.** Every expansion of an array that may be empty is guarded by a
  `${#a[@]}` test. Sparse `drop`/`grouped` elements are read as `${x[i]:-}`.
  `+=` and `local -a` are both 3.1+. Not run under a real 3.2: no 3.2 binary on
  this box.
- **K1 interruption.** The rewrite happens in `mktemp -d "$gitdir/…"`, the blob
  comes from `hash-object -w --no-filters`, the tree is built in a temporary
  `GIT_INDEX_FILE`, R is made with `commit-tree -p HEAD`, then
  `push . R:refs/heads/live`, and only then `checkout --detach live`. The
  worktree never holds R uncommitted.
- **Byte round-trip.** `git show HEAD:MEMORY.md` streams the raw blob with no
  textconv and no smudge. `hash-object --no-filters` stores it raw.
- **Env leak.** Every entry point unsets `--local-env-vars` before the bare
  `git` calls in `gitlore_adopt_commit_repair` run.
- **Fetch-first.** A local `live` that is an ancestor of `origin/live` skips the
  adoption. Because HEAD ⊆ `live` ⊆ remote, the fast-forward is always legal. A
  failed fetch, no remote, or a remote with no `live` still adopts, and the
  failure is reported afterwards.
- **K6.** The tier push happens before memory's push in the `live`-ahead arm and
  in the `behind` arm. A take pass that repairs a tier later in the loop is
  published by that tier's own iteration. A take pass that returns 1 after an
  earlier tier's repair publishes nothing, and the next push keeps the tier
  first. The one path that breaks the order needs a race (origin advancing
  mid-push).
- **S4 contract.** All four `push_or_report` calls use `|| rc=$?`. Status 2
  rests an unadopted tier and exits 1 on both `continue-after-merge` arms.
  `check_store_gates` exits 1 on status 2. `rest_unadopted_tier` is always
  reached through `[ -z … ] ||`.

## Critical

None.

## Major

None.

## Minor

**m1: when the repair cannot proceed, only the carrier's problems are reported,
and sometimes none are.** `scripts/lib/resolve.sh:1873-1874, 1913-1937`. Axis:
error signaling / completeness. Severity: Minor.

`gitlore_adopt_tier_into_root` passes only `$carrier_problems` to
`gitlore_adopt_repair_arrival`. The full first refusal (`$composed`) is not
passed, so root, manifest and other-tier lines from that refusal never reach the
output when the repair cannot land.

- **Unrepairable arm (1920–1928).** It prints the carrier lines as
  `live:MEMORY.md: …` and ends "Once the index is fixed where it was published,
  run /gitlore:merge again." A root rule 3 leftover in the same refusal stays
  hidden until the upstream fix arrives and the next take refuses again. This
  breaks the check's own contract ("a user fixing a broken store wants the whole
  list", `index-compose.sh:153-154`), and the pre-change walk-back printed the
  whole list.
- **Build and read failure arms (1913–1919, 1929–1931).** The arrival or pin
  cannot be read, the rewrite fails, or `commit-tree` fails. These print no
  problem list at all, and the walk-back ends with the default "Fix the store,
  then run /gitlore:merge again."
- **Refused `live` update (1939–1942).** It gets the same default remedy.

Found by reading: `$composed` has no path into the function. Unprobed.

Suggested fix:

- Pass the non-carrier remainder of `$composed` and print it in the unrepairable
  arm.
- On the transient arms (a lock, a failed build), replace "Fix the store" with
  the outline's own "the next take repairs again".

**m2: in the `behind` arm, a failed retry push is always reported as "not
because of divergence".** `scripts/lib/resolve.sh:1399-1407`. Axis: error
signaling. Severity: Minor.

The retry push after a repairing take goes to the non-divergence message
whatever git said. If origin advanced between the take's fetch and this push,
the refusal is `(fetch first)` and the message states the wrong cause. This
needs a race, so it is rare. The message block also copies the block at
1432–1436.

Suggested fix: route the retry's `$tier_err` through the same `case` as the
first push, or at minimum drop the "not because of divergence" claim here.

**m3: dropping an unterminated last duplicate strips the newline from the line
before it.** `scripts/lib/index-compose.sh:432-448`. Axis: K3 byte preservation.
Severity: Minor.

`terminated` is read from the original file, and the last element of `p3` is
written without a newline. If the dropped duplicate was that unterminated last
line, the surviving line before it loses the newline it had. Probed on
`# H\n- [A](a.md) — x\n- [B](b.md)\n- [A](a.md) — x` with no trailing newline:
the result ends `- [B](b.md)` with no newline. The file is unterminated before
and after, so nothing downstream breaks, but `- [B](b.md)` is a line no rule
named, and its bytes changed, which K3's "every other line keeps its bytes"
rules out.

**m4: a killed take leaves its scratch directory behind in the tier's gitdir.**
`scripts/lib/resolve.sh:1906, 1933`. Axis: robustness / interruption. Severity:
Minor.

`mktemp -d "$gitdir/gitlore-repair.XXXXXX"` is removed only by the `rm -rf` on
the normal path; there is no trap. A take killed between the two leaves a
directory holding the arrival copy, the pin copy and a temporary index. It is
outside the worktree, so K1 holds and `add -A` never sees it. But the name is
unique per run, so directories pile up, one per killed take. Compare
`gitlore_compose_write`, which uses a fixed `$$` name that the next run
overwrites.

**m5: the comment says "walk back from" when it means "adopt past".**
`scripts/lib/index-compose.sh:268-270`. Axis: clarity. Severity: Minor.

"a problem this reports and gitlore_repair_index cannot fix is a defect no take
can walk back from". The take does walk back from such a defect
(`gitlore_adopt_walk_back_tier`). What it can never do is adopt past it: the
tier is wedged. Suggested wording: "…is a defect no take can adopt past".

Tracked follow-ups seen during the review:

- The `memory-commit-batch.sh` wording "make it and the retry picks it up" meets
  the batch-retry approval gap (tracked).
- Untested: a failed `git status` in the rc 1 arm; `--no-filters` keeping CRLF
  (tracked).
- `index-compose.sh`, `lib/resolve.sh` over the 400-line cap (tracked).
- Rootless store skips every index check (tracked).

## Conformance map

| Requirement | Covered by |
|---|---|
| K1 — repair is a plain commit on the arrival, built from a temporary index, `live` advanced by `push .`, tier moved only by checking out `live`, retry | `lib/resolve.sh:1900-1968`, `1976-1985` |
| K1 — refused `live` update walks back, `live` stays on the arrival, exits 1 with git's message | `lib/resolve.sh:1939-1943` |
| K2 — repair when any problem names the arriving carrier, by exact prefix | `lib/resolve.sh:1872`; `index-compose.sh:467-478` (probed) |
| K2 — the rest reported, tier rests with R in `live` | `lib/resolve.sh:1954-1958` |
| K2 — nothing names the carrier: walk back, arrival in `live` | `lib/resolve.sh:1877-1880` |
| K2 — unrepairable: problems attributed to `live`, not the worktree | `lib/resolve.sh:1920-1928` (see m1 for what it omits) |
| K3 — welds (guarded), then strays to the trailer start, then duplicates with the pin pick; one report line per edit; clean index byte-identical | `index-compose.sh:308-453`, `455-462` (probed; see m3) |
| K3 — check comment couples each new rule to a repair rule | `index-compose.sh:267-270` (see m5) |
| K4 — continuation refuses on problems in the merged index, keeps state and `MERGE_HEAD`, lands otherwise | `resolve.sh:131-140`, `150-158` |
| K5 — abort on a dirty index file with attributed problems; restamp; root rules 2/3 and clean files advisory; comment names the split | `lib/resolve.sh:1099-1153` |
| K6 — take in push publishes R before memory, both arms | `lib/resolve.sh:1366-1370`, `1394-1409`, `1959-1965` |
| K6 — `/gitlore:merge` names `/gitlore:push` | `lib/resolve.sh:1963-1964` |
| S1 — helper shared by S2/S3 | `index-compose.sh:464-478`; used at `lib/resolve.sh:1120,1129,1872`, `resolve.sh:135` |
| S2 — fetch first; skip adoption when `live` ⊆ `origin/live`; a failed fetch still adopts, then reports | `lib/resolve.sh:1597-1645` |
| S2 — reach through `gitlore_adopt_advanced_live` and the remote fast-forward | `lib/resolve.sh:1835`, `1705` |
| S3 — gate before commit, exit 1 | `resolve.sh:131-140` |
| S4 — `push_or_report` returns 0/1/2, never exits; every call `\|\| rc=$?` | `resolve.sh:263-279`, `343`, `363`, `432`, `453` |
| S4 — status 2 rests an unadopted tier and exits 1 | `resolve.sh:347-350`, `368-371` |
| S4 — rest guard: pin only when `live` contains HEAD, else remedy | `resolve.sh:230-235` |
| S4 — default mode exits 1 on status 2 | `resolve.sh:433-434`, `454-455` |
| Commit-batch message defers to a reason that names a fix | `cc-hooks/memory-commit-batch.sh:104-121` |
| S5, S6 — prose and design records | Not code; outside this review |
| S7 | Dropped by decision |
