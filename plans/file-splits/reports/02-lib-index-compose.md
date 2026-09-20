# Split: scripts/lib/index-compose.sh

## Top-level-code check

The file has one piece of top-level code besides `source` lines (none existed)
and function definitions: `GITLORE_DANGLING_CAP="${GITLORE_DANGLING_CAP:-5}"`
at original line 619, a default-value assignment consumed only by the function
immediately below it, `gitlore_cap_list`. It carries its own 9-line comment
block directly above it (original 610-618), which reads as the intro to both
the constant and the function it feeds. Not ambiguous — it moved with
`gitlore_cap_list` into `index-compose-project.sh`, verbatim, rather than being
split from its comment or hoisted elsewhere.

One other pre-existing oddity, unrelated to top-level code: the comment block
"The whole in-session pass..." (original 938-954, describing `gitlore_compose`'s
three return codes) sits physically above `gitlore_compose_and_report`, not
above `gitlore_compose` itself, separated from it by one blank line and then
`gitlore_compose_and_report`'s own comment (956-964). This did not need a
decision because all three functions in that neighborhood
(`gitlore_compose_write`, `gitlore_compose_and_report`, `gitlore_compose`) stay
in `index-compose.sh` together — no file boundary crosses the ambiguity.

## Final partition

| File | Lines | Contents |
|---|---|---|
| `scripts/lib/index-compose.sh` | 377 | header, 3 `source` lines, `gitlore_bullet_path` … `gitlore_tier_of` (bullet/region helpers), `gitlore_compose_write`, `gitlore_compose_and_report`, `gitlore_compose` |
| `scripts/lib/index-compose-check.sh` | 285 | `gitlore_compose_check`, `gitlore_weld_tail`, `gitlore_welded_path`, `gitlore_compose_check_index`, `gitlore_compose_problems_in`, `gitlore_compose_check_pins` |
| `scripts/lib/index-compose-repair.sh` | 183 | `gitlore_repair_index`, `gitlore_repair_tier_file` |
| `scripts/lib/index-compose-project.sh` | 297 | `GITLORE_DANGLING_CAP`, `gitlore_cap_list`, `gitlore_compose_dangling`, `gitlore_compose_down`, `gitlore_index_has_tier`, `gitlore_compose_root_bullets`, `gitlore_compose_up`, `gitlore_compose_orphans`, `gitlore_index_has_path`, `gitlore_compose_pick` |

Total 1142 lines across 4 files (was 1111 in one file — the +31 is the new
header material, 3 `source` lines, and each part's own 4-6 line header
comment). All four files are ≤ 380 (cap 400), no deviation from the proposed
partition was needed. Mode bits: 644 on all four, matching
`scripts/lib/resolve.sh` and `scripts/lib/resolve-push.sh`.

`scripts/lib/index-compose.sh`'s header comment gained a paragraph naming the
three parts, in `resolve.sh`'s form, right before the three
`# shellcheck disable=SC1091` / `source` pairs.

## References updated

Every `source .../index-compose.sh` line (in `scripts/resolve.sh`,
`scripts/cc-hooks/add-tier-batch.sh`, `scripts/cc-hooks/session-start.sh`,
`scripts/lib/resolve.sh`, `scripts/cc-hooks/index-compose.sh` (the hook — a
different file by coincidence of name), `tests/index_merge.bats`,
`tests/evals/lib/asserts.bats` x2, `tests/index_compose.bats`,
`tests/evals/setups/mounted-tier.sh`) needed **no change**: `index-compose.sh`
still sources the three parts itself, so every existing caller gets every
function transitively.

Comments naming a specific moved function's file, updated:

- `tests/commit_memory.bats:472` — "the ahead wording (index-compose.sh:358)"
  → `index-compose-check.sh:267`. The old `:358` reference was already stale
  before this split (original line 358 was inside `gitlore_repair_index`'s
  comment, not the "ahead" problem message at all); I pointed it at the actual
  current location of the "ahead of the pin ... it advanced without composing"
  message inside `gitlore_compose_check_pins`, now in `index-compose-check.sh`.
- `tests/commit_memory.bats:924` — "`gitlore_compose` returns only 0, 1 or 2
  (index-compose.sh:800-853)" → `index-compose.sh:324-377` (the function's new
  location; it did not move files, only lines within the kept file).
- `tests/killed_take_repro.bats:143-144` — "(gitlore_compose_down,
  scripts/lib/index-compose.sh)" → `scripts/lib/index-compose-project.sh`, and
  reflowed the surrounding 3-line comment to stay within its established
  line-length range (the new filename pushed one line to 86 chars).
- `tests/helpers/triggers.bash:33-34` — "The dangling-pointer report's wording
  (scripts/lib/index-compose.sh)" → `index-compose-project.sh`, reflowed to two
  lines to keep the added characters from overrunning the line.

Everything else grepped (`docs/design.md`, `docs/decisions.md`,
`docs/references/*.md`, `scripts/`, `tests/`, `CLAUDE.md`) either names a
function generically (`gitlore_compose_check`, `gitlore_compose_up`, etc. in
`docs/references/tier-stores.md`, `tier-arrival-repair.md`, `git-hooks.md` —
no file path attached, left alone) or names `index-compose.sh` meaning the
library/compose pass as a whole, or the *hook* script
`scripts/cc-hooks/index-compose.sh` (a same-named but different file — e.g.
`docs/references/index-composition.md:85,137`, `session-start.sh:368`,
`add-tier-batch.sh` comments, `index-sync-pre.sh:58`, `index-sync-post.sh:273`,
`relay-drain.sh:11`, `index-merge.sh:3,27`, `tests/cc_hook_add_tier.bats:123`,
`tests/cc_hook_index_compose.bats` throughout). `docs/changelog/` left
untouched per instruction.

## File-as-data tests examined

- `tests/plugin_distribution.bats:99` — `grep -qF 'gitlore:memory-writing'
  "$PLUGIN_ROOT/scripts/lib/index-compose.sh"`. The matched string is inside
  `gitlore_compose_and_report`'s context text, which stays in
  `index-compose.sh` (kept file) — confirmed still present at line 297. No
  change needed.
- `tests/index_compose.bats:1231,1239,1246` — `source
  "$PLUGIN_ROOT/scripts/lib/index-compose.sh"` then call `gitlore_cap_list`
  directly. Works unchanged: sourcing the aggregator pulls in
  `index-compose-project.sh`, which now defines `gitlore_cap_list`.
- `tests/index_merge.bats:16`, `tests/evals/lib/asserts.bats:73,246`,
  `tests/evals/setups/mounted-tier.sh:44` — all `source` the aggregator path
  directly (not grep-as-data); unaffected for the same transitive reason.
- Searched for any other `grep.*index-compose\.sh` or the reverse across
  `tests/` and `scripts/`: only the `plugin_distribution.bats:99` hit above.
- `scripts/lint-shell.sh` discovers files via `git ls-files -- '*.sh'
  '*.bash' '*.bats'` (no per-file enumeration to update) — the new part files
  are picked up automatically. `justfile` and `scripts/lib/edit-weld.sh`
  carry no lib-file enumeration referencing `index-compose.sh`.

## Verification (all foreground)

**Function equivalence** — printed only `identical`:

```
$ git show HEAD:scripts/lib/index-compose.sh > scripts/lib/.oldchk.sh
$ dump() { bash -c 'source scripts/lib/util.sh; source scripts/lib/log.sh; source "$0"; declare -f $(declare -F | awk "{print \$3}" | grep "^gitlore_")' "$1"; }
$ dump scripts/lib/.oldchk.sh > df-old.txt; rm scripts/lib/.oldchk.sh
$ dump scripts/lib/index-compose.sh > df-new.txt
$ cmp df-old.txt df-new.txt && echo identical
identical
```

**No line lost** — printed nothing:

```
$ diff <(git show HEAD:scripts/lib/index-compose.sh | sort) \
       <(cat scripts/lib/index-compose.sh scripts/lib/index-compose-*.sh | sort) \
  | grep '^<'
(no output)
```

**Line counts** — all ≤ 380 (cap 400):

```
$ wc -l scripts/lib/index-compose*.sh
  285 scripts/lib/index-compose-check.sh
  297 scripts/lib/index-compose-project.sh
  183 scripts/lib/index-compose-repair.sh
  377 scripts/lib/index-compose.sh
 1142 total
```

**Lint**:

```
$ just lint
lint-shell: 141 files clean
```

**test-unit** (ran in background twice due to the 120s foreground cap; final
run against the finished tree):

```
$ just test-unit
bats: 976 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.06N7Jt
```

**test-integration**:

```
$ just test-integration
bats: 72 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.h2ywji
```

No failures were caused by the split; nothing needed a fix beyond the
reference updates listed above.

## Note on concurrent work

`tests/killed_take_repro.bats` and `tests/commit_memory.bats` were also being
edited by a sibling agent (splitting `scripts/lib/resolve.sh`) during this
run. `git diff` confirms both sets of edits landed independently without
clobbering each other — the sibling's `resolve.sh` → `resolve-adopt.sh` /
`resolve-adopt-report.sh` reference updates sit alongside my
`index-compose.sh` → `index-compose-check.sh` / `index-compose-project.sh`
updates in the same file, at different lines.
