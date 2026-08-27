> Applied in commit 2f2ec69 (2026-08-27): B1–B3, W1–W7, all seven `scripts/`
> NITs, and W8 as an allow-list, recorded as D45. The two `plugin-dev/` NITs are
> not applied — vendored, to propose upstream in claude-plugin-dev. Files NOT
> changed since v0.5.0 were out of scope; a second pass over them, with macOS
> compatibility required, is queued.

# shell-gotchas audit — gitlore, changes since v0.5.0

Scope: every `.sh`/`.bats`/hook file touched between `v0.5.0` and the working
tree. `scripts/**` audited whole (skill rule 2); tests audited at the changed
hunks only; `plugin-dev/**` is vendored and listed separately.

`shellcheck 0.10.0 -S style` is clean on all sixteen touched `scripts/**` files,
and no finding below is one shellcheck reports. No suppression in these files is
unjustified — every `# shellcheck disable` carries a reason comment.

Counts: **3 BLOCK, 8 WARN, 7 NIT** in `scripts/**`; 2 NIT in `plugin-dev/`.

Bash used for every probe: GNU bash 5.2.37 on Linux, `LANG=C.UTF-8`.

---

## BLOCK

### B1 — `scripts/lib/edit-weld.sh:343-349`: `$?` after an untaken `if` is 0, so a failed repair reports success (NEW code)

```sh
  if jq -j '.exp' "$state" > "$scratch" && cat "$scratch" > "$file"; then
    rm -f "$scratch"
    return 0
  fi
  status=$?          # <-- always 0: POSIX says an `if` with no else and a false
  rm -f "$scratch"   #     condition exits 0, and $? is the `if`'s status
  return "$status"
```

Gotcha: **exit status silently lost / dishonest success path** (SKILL rule 3).
This is the exact trap that `scripts/lib/index-sync.sh:77-80` documents and
avoids by capturing `$?` *inside* an `else` branch — `gitlore_weld_repair` is
the one place in the repo that does not.

Why it bites: `gitlore_weld_repair` never returns non-zero. Its only caller,
`scripts/cc-hooks/edit-weld-post.sh:106`, is
`if err=$(gitlore_weld_repair "$state" "$file" 2>&1); then` — so the failure
branch at 110-114 is dead code. On a failed repair the hook tells the user
*"gitlore: repaired a welded Edit in $file"* and tells the model *"the file on
disk now holds exactly what the edit asked for, so your own model of it is the
correct one"* — while the welded lines are still on disk. That is a wrong-output
report on top of live data corruption, in the hook whose entire purpose is to
contain that corruption.

Triggers: a read-only target (the realistic one — an `Edit` into a file the
worktree left mode 444), a full disk, or a `$state` file jq cannot parse.

Verified:

```
$ # corrupt state file
BUG: returned 0 on jq failure          (target unchanged: "orig")
$ # chmod 444 target, valid state
caller takes the SUCCESS branch -> reports "repaired a welded Edit"
target on disk: A/B/                   (unrepaired)
```

Fix: mirror `index-sync.sh`'s shape.

```sh
  if jq -j '.exp' "$state" > "$scratch" && cat "$scratch" > "$file"; then
    rm -f "$scratch"
    return 0
  else
    status=$?
    rm -f "$scratch"
    return "$status"
  fi
```

---

### B2 — `scripts/lib/resolve.sh:669,672,755,758`: the memory commit is unchecked, and the caller's `||` turns errexit off for the whole call tree (pre-existing)

```sh
    gitlore_git -C "$mempath" add -A
    GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile"
    rm -f "$msgfile"
```

Gotcha: **`set -e` is transitively disabled inside a function called from a
`&&`/`||` list** (robustness.md, "Off inside conditions, transitively"; SC2310
only, and only optionally). `scripts/git-hooks/pre-commit:68` calls it as

```sh
gitlore_sync_memory_to_live "$mempath" || exit $?
```

so nothing in `gitlore_sync_memory_to_live` — or in
`gitlore_sync_tiers_to_live`, which it calls at 754 — runs under errexit.

Why it bites: when the commit fails, execution falls through to
`rm -f "$msgfile"` (759), which **deletes the user's approved commit summary**,
then to the `push . HEAD:live` at 771, which is a no-op success because HEAD
never moved — so the function returns 0, the pre-commit hook passes, and the
parent commit lands recording the *old* memory gitlink. Memory stays
uncommitted, the approval is gone, and nothing is reported. Same shape one level
down for tiers at 669/672.

Realistic triggers for the commit failing: `user.email` unset in the memory
store, the memory-side FR11 gate erroring, a lock `gitlore_git`'s retry budget
could not outlast, a full disk. Same for `add -A` failing on an unreadable file.

The two entry points disagree: `scripts/commit-memory.sh:63` calls the same
function *bare* under `set -euo pipefail`, so there the failure correctly aborts
and the summary survives. Identical code, opposite failure semantics.

Verified — the real `gitlore_sync_memory_to_live` extracted from
`scripts/lib/resolve.sh`, with `gitlore_git` stubbed to fail on `commit`:

```
== called the way pre-commit does: f "$x" || exit $? ==
  (simulated commit FAILURE)
  return code            : 0
  approved msgfile still there? NO — DELETED
  git calls made         : ... add -A ... commit -q -F .../gitlore-memory-message

== called bare under set -e ==
  return code            : 1
  approved msgfile still there? YES
```

Fix: check each mutating call explicitly rather than relying on an errexit that
is not in force at these lines.

```sh
    gitlore_git -C "$mempath" add -A || return 1
    GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile" \
      || return 1
    rm -f "$msgfile"
```

(and the same at 669/672 for the tier loop). `shellcheck --enable=all` reports
these as SC2310 on the call site, which is the cheap regression guard.

---

### B3 — `scripts/add-tier.sh:284`: appending to `.gitlore-tiers` welds onto an unterminated last line (pre-existing)

```sh
printf '%s\n' "$name" >> "$mempath/.gitlore-tiers"
printf 'gitlore: activated — appended to %s/.gitlore-tiers ...\n' "$mempath"
```

Gotcha: **unterminated last line / concatenation weld** — the repo's own rule
(`.claude/rules/shell.md`: *"Concatenating file parts has the mirror hazard: an
unterminated part welds onto the next"*). `gitlore_compose_write`
(`index-compose.sh:646`) and `gitlore_index_merge` (`index-merge.sh:151`) both
insert a separator before appending for exactly this reason; the two
`wire-*.sh` hook appenders lead with `printf '\n# gitlore: managed\n'`, which
makes them safe by accident. `add-tier.sh` is the one appender with neither
guard.

Why it bites: the manifest is *documented as hand-editable* — this script's own
final message says *"reorder the file by hand to change that"* — and a hand
edit, an agent `Edit`, or any writer that does not terminate leaves the last
line bare. The next mount then produces one welded entry. Both tiers go dormant
(neither name is in the manifest any more), and `gitlore_compose_check` rule 2
refuses the entire store with *"the tier manifest lists 'ddaanetnewtier', which
is not mounted"* — while `add-tier.sh` has already printed
*"gitlore: activated"*. A success message after a corrupting write.

Verified:

```
$ printf 'ddaanet' > .gitlore-tiers        # hand edit, no trailing newline
$ printf '%s\n' newtier >> .gitlore-tiers
$ cat .gitlore-tiers
ddaanetnewtier
entries gitlore_active_tiers would yield:
  [ddaanetnewtier]
```

Fix — separator-only, same shape as `gitlore_compose_write`:

```sh
manifest="$mempath/.gitlore-tiers"
if [ -s "$manifest" ] && [ "$(tail -c 1 "$manifest" | wc -l | tr -d ' ')" = 0 ]
then
  printf '\n' >> "$manifest"
fi
printf '%s\n' "$name" >> "$manifest"
```

---

## WARN

### W1 — `scripts/cc-hooks/session-start.sh:166`: blanket `2>&1` on the ff-merge, and the fallback message guesses "diverged" (pre-existing)

```sh
  if gitlore_git -C "$mempath" merge --ff-only live >/dev/null 2>&1; then
    add_sysmsg "gitlore: memory ready (detached at live)."
  else
    add_sysmsg "gitlore: memory diverged from live. Run /gitlore:resolve, ..."
```

Gotcha: **blanket `cmd 2>/dev/null` to silence one expected message**, plus the
repo's own rule *"Never replace git's message with a guess"*
(`.claude/rules/shell.md`). This is the only redirect among the sixteen touched
scripts with no justifying comment; every other one in the set carries one.

Why it bites: `--ff-only` refuses for several reasons, and every one of them is
reported to the user as divergence — a lock `gitlore_git`'s retry could not
clear (its whole captured stderr is swallowed by the `2>&1`), a corrupt object,
an unwritable worktree, an unborn `live`. `/gitlore:resolve` cannot help with
any of those, and the user is sent there anyway with git's actual explanation
discarded.

Fix: capture and report, the shape used everywhere else in this codebase.

```sh
  if merge_err=$(gitlore_git -C "$mempath" merge --ff-only live 2>&1); then
    add_sysmsg "gitlore: memory ready (detached at live)."
  elif [ "$(gitlore_classify_refusal "$mempath" HEAD live)" = "diverged" ]; then
    add_sysmsg "gitlore: memory diverged from live. Run /gitlore:resolve, ..."
  else
    add_sysmsg "gitlore: memory could not be fast-forwarded onto live. git said:
$merge_err"
  fi
```

### W2 — `core.quotePath` mangles non-ASCII paths out of `--name-only` / `ls-files` / `ls-tree` (pre-existing)

Sites: `scripts/lib/resolve.sh:358-360` (`changed_files`), `365-367`
(`conflicted_files`), `382` (`ls-files > "$treef"`);
`scripts/lib/index-merge.sh:172` (`gitlore_conflicted_indexes`), `191`
(`gitlore_index_paths_in`).

Gotcha: **parsing git output without a plumbing-safe format**
(environments.md, "Parsing git output"). git quotes any path containing a
non-ASCII byte, a `"` or a `\` — this is on by default and independent of
`--name-only` vs `-z`.

Verified:

```
$ git ls-files
"caf\303\251.md"
$ git diff --name-only <empty-tree> HEAD
"caf\303\251.md"
$ git -c core.quotePath=false ls-files
café.md
```

(Spaces are *not* quoted — I checked `a b/MEMORY.md` and `nor mal.md` come
through verbatim — so ordinary whitespace safety is intact here. This is the
non-ASCII case only, which is why it is WARN and not BLOCK.)

Why it bites, concretely:

- `gitlore_conflicted_indexes` — `[ -f "$store/$name" ]` fails on the quoted
  literal, so a conflicted `MEMORY.md` under a non-ASCII-named tier is silently
  dropped from `conflicted_files` and the merger sub-agent is sent past a real
  conflict, which is exactly the failure that function exists to prevent.
- `gitlore_index_paths_in` / `gitlore_merge_indexes` — `rev-parse "$ref:$path"`
  misses, all three sides come out empty, and the `cp` at `index-merge.sh:235`
  fails onto `|| continue`. No data loss, but that index never gets the
  entry-wise merge, so the duplicate-pointer defect it exists to catch goes
  undetected.
- `changed_files` in the state file names a file the merger cannot open.

Fix: add `-c core.quotePath=false` to these five invocations. A tier is a store
owned by another repo, so ASCII-only paths are a convention, not an invariant.

### W3 — `pipefail` + `grep -q`: a matching search reports "not found" once the producer exceeds the pipe buffer (pre-existing)

Sites: `scripts/lib/index-compose.sh:174, 269, 404`;
`scripts/lib/index-merge.sh:75-77`. All are
`printf '%s\n' "$var" | grep -qxF -- "$needle"` under `set -o pipefail`
(inherited from every entry point: `session-start.sh`, `index-sync-post.sh`,
`resolve.sh`, `push-memory.sh`).

Gotcha: **`set -o pipefail` + an early-exiting consumer** — `grep -q` exits at
the first match, the producer takes SIGPIPE, and pipefail reports 141 for a
pipeline that *succeeded*. The same gotcha is already fixed deliberately
elsewhere in this repo: `index-sync.sh:186-189` swapped `head -n` for
`awk 'NR<=n'` with a comment, and `resolve.sh:269-271` captures `ls-remote`
before matching for the same reason. These four sites were not swept.

Verified (threshold is the 64 KiB Linux pipe buffer):

```
small: pipeline rc=1  (bytes=100)        # no match, correct
big:   pipeline rc=141 (bytes=304999)    # PATTERN PRESENT, grep exited 0
```

Why it bites — and why WARN not BLOCK: at 141 the caller reads the wrong answer
in both directions. `index-compose.sh:174` would refuse a healthy store
(*"the tier manifest lists 'X', which is not mounted"*); `269` would stop
reporting a genuine duplicate pointer; `index-merge.sh:75-77` would flip a
presence bit and drop or duplicate an entry in the merged index. But the
producers here are a tier list and an accumulating path list, and the root index
budget is 25 KiB total — so at current sizes none of them reaches 64 KiB.
Latent, with a cheap fix.

Fix: drop the pipe. `grep -qxF -- "$needle" <<<"$var"` (bash here-string, no
pipeline, no producer to signal), or `case`/`while` over the list.

### W4 — `scripts/install/run.sh:56` and `scripts/install/init-submodule.sh:146`: `grep -qx "$mempath"` treats the path as a regex (pre-existing)

```sh
if [ -e "$mempath" ] && ! git config --file .gitmodules \
     "submodule.gitlore-memory.path" | grep -qx "$mempath"; then
```

Gotcha: an unanchored variable used as a **pattern rather than a fixed string**
— `-x` anchors the whole line but the metacharacters still apply. `.` matches
any character, `[`/`\`/`*` change or break the match.

Why it bites: `mempath` is `$1` to `run.sh`, so it is user-supplied. A path like
`.memory` or `mem.dir` matches lines it should not; a path containing `[`
produces `grep: brackets not balanced` and, under `set -o pipefail` inside a
condition, is read as "not registered" — so `run.sh` proceeds to the
non-empty-directory refusal or `init-submodule.sh` re-runs the first-install
block over an existing store.

Fix: `grep -qxF -- "$mempath"` at both sites. (`-F` and `--` — the `--` also
covers a leading-dash path.)

### W5 — `scripts/install/init-submodule.sh:179,244`: `cd "$mempath"` with no `unset CDPATH` (pre-existing)

Gotcha: **CDPATH makes `cd` search elsewhere and print its target**
(environments.md, "Self-location and cwd discipline"). `run.sh:3` and
`add-tier.sh:22` and `resolve.sh:5` all open with `unset CDPATH`;
`init-submodule.sh` does not.

Why it bites: `unset CDPATH` in `run.sh` protects the child only when CDPATH was
*exported*; a shell-local CDPATH was never in the child's environment anyway, so
via `run.sh` this is covered either way. But `init-submodule.sh` is also invoked
directly (the suite does, and the header documents it as a step). With
`CDPATH=$HOME` and a `$HOME/memory` directory present, `cd "$mempath"` at 179
lands in the *wrong repository*, and the subshell then runs `gitlore_git add -A`
and `commit --allow-empty -m "Initial memory"` there. Line 244 is worse: `cd`
followed by `git branch live` and `git checkout -q --detach live`.

Fix: add `unset CDPATH` under `set -euo pipefail` at line 119, matching the
other three entry points.

### W6 — `scripts/cc-hooks/session-start.sh:27`: `|| echo false` performs the exact downgrade the comment above it forbids (pre-existing)

```sh
# ... but a *malformed* settings.json is a real fault that
# would otherwise be silently downgraded to "gitlore disabled" — the whole hook
# then no-ops with no explanation.
[ -f .claude/settings.json ] || exit 0
enabled=$(jq -r '.gitlore.enabled // false' .claude/settings.json || echo false)
[ "$enabled" = "true" ] || exit 0
```

Gotcha: **fallback inside a command substitution** plus a dishonest guard. The
file guard removes the *missing-file* case, which is what the comment describes;
it does nothing about a *malformed* one, and `|| echo false` then swallows it
into `enabled=false` and `exit 0`. jq's parse error does reach stderr, but this
hook's own note at line 53-56 records that `SessionStart` stderr is invisible to
the user outside `--verbose`. So a typo in `settings.json` disables gitlore
entirely and silently — no hooks wired, no memory redirect, no message.

Fix: separate the two cases and report the malformed one on the channel the user
actually sees.

```sh
if ! enabled=$(jq -r '.gitlore.enabled // false' .claude/settings.json 2>&1); then
  jq -nc --arg e "$enabled" '{systemMessage:("gitlore: .claude/settings.json could not be parsed, so gitlore is inactive this session: " + $e)}'
  exit 0
fi
```

### W7 — `scripts/install/init-submodule.sh:195-196`: the gitfile and `core.worktree` hardcode a one-component `mempath` (pre-existing)

```sh
printf 'gitdir: ../.git/modules/gitlore-memory\n' > "$mempath/.git"
git config -f .git/modules/gitlore-memory/config core.worktree "../../../$mempath"
```

`run.sh` accepts `mempath` as `$1` and validates only that it is empty or an
existing gitlore submodule — never that it has a single component. With
`mempath=store/memory` both relative depths are off by one, so the gitfile
points outside the repo and `core.worktree` resolves wrong. The submodule looks
installed and every later `git -C "$mempath"` fails or escapes.

Fix: derive the depth, or refuse a `mempath` containing `/` in `run.sh` the way
`add-tier.sh:120-123` already refuses a slash in a tier name.

### W8 — `scripts/cc-hooks/session-start.sh:107`: `sh -c "$cmd"` executes a line from a *tracked* file (pre-existing; design, not a catalogued gotcha)

```sh
cmd=$(head -1 "$SENTINEL" | tr -d '\n')
case "$cmd" in
  ""|direct|manual) ... ;;
  *) sh -c "$cmd" ;;
esac
```

`.claude/gitlore-hook-setup` is committed (`git ls-files` confirms), and the
`*)` arm is by design — the wire-* scripts legitimately write
`lefthook install`, `npx husky`, `overcommit --install` there. But that makes
cloning any repo and starting Claude Code in it run whatever that file's first
line says, gated only by `gitlore.enabled` in the equally-tracked
`.claude/settings.json`.

Flagging for triage rather than proposing a fix: the trust model is a design
call, not a shell defect. If the intent is only the three known managers, an
allow-list (`lefthook install|npx husky|overcommit --install`) closes it without
changing any supported path.

---

## NIT

- **`scripts/lib/index-compose.sh:363`** —
  `printf '%s\n' "$input" | head -n "$CAP"` under `pipefail` is the same SIGPIPE
  shape as W3 (measured: pipeline rc=141 once input exceeds the pipe buffer).
  Harmless today because every caller invokes `gitlore_cap_list` inside
  `$(...)`, where errexit is off and the output is already complete — but a
  future bare call under `set -e` would lose the "… and N more" line.
  `awk -v n="$CAP" 'NR<=n'`, as `gitlore_index_largest` already does.
- **`scripts/lib/util.sh:360` vs `:278`** — `while IFS= read -r -d '' rec` in
  `gitlore_tier_paths` omits the `LC_ALL=C` that
  `gitlore_commit_msg_freshness` carries at 278 for the bash 5.0–5.3 multibyte
  `read -d ''` bug (BP#65). I could not reproduce an overshoot on 5.2.37 —
  `read -r -d ''` handled invalid UTF-8 (`A\xff\xfeB`) correctly — so this is an
  inconsistency to close, not a demonstrated defect.
- **`scripts/lib/index-compose.sh:638`, `scripts/lib/index-sync.sh:57`** — the
  scratch file (`$1.gitlore-compose.tmp`, `$file.gitlore.tmp`) is created
  *beside the target*, i.e. inside the memory worktree. `edit-weld.sh:336-339`
  explicitly rejects that placement, for the stated reason that the FR11 gate's
  `git add -A` sweeps up an untracked neighbour. Both sites clean up on every
  failure branch, so the window is only a kill mid-write — but it is a window
  the third site was designed to close.
- **`scripts/add-tier.sh:163`** — `seed=$(mktemp -d …)` has no
  `trap 'rm -rf "$seed"' EXIT`. The two push failures clean up explicitly, but a
  failing `git init`/`add`/`commit`/`branch`/`remote add` (all unchecked under
  top-level `set -e`) aborts and leaks the directory.
- **`scripts/lib/util.sh:95`** — `gitlore_has_submodule` is
  `gitlore_memory_path >/dev/null 2>&1`, discarding exactly the stderr that
  `gitlore_memory_path`'s own comment (85-86) calls *"a genuine fault"*. Drop
  the `2>&1`; the helper is already silent on the expected miss.
- **`scripts/cc-hooks/index-sync-post.sh:167`** — `touch "$nudge_file"` is
  unguarded under `set -euo pipefail`. A failure there aborts the hook before
  the `jq -n` at 230, discarding the whole report — including the `failed` list
  at 218 that names files whose frontmatter is now stale.
  `touch … || budget=""`.
- **`scripts/install/init-submodule.sh:233`** —
  `tmp=$(mktemp) && grep -vx '\.gitmodules' .gitignore > "$tmp" && mv …`: a
  `.gitignore` whose only line is `.gitmodules` makes `grep -v` exit 1, the
  chain stops, `$tmp` leaks and the ignore line survives. Not silent (the
  `gitlore_git add .gitmodules` at 236 then fails loudly under `set -e`), but
  the diagnosis points at the wrong thing. `|| :` on the grep, or
  `grep -vx … || true`.

---

## Clean

`scripts/hook-manager/wire-direct.sh`, `scripts/cc-hooks/edit-weld-pre.sh` and
`scripts/lib/index-sync.sh` are clean apart from the NITs named above — the
`read -r -d ''` NUL framing in `edit-weld-pre.sh:23-33`, the `-mtime`/`-delete`
sweeps, the `wc -l | tr -d ' '` BSD-padding guards and the `mktemp
"${TMPDIR:-/tmp}/…"` templates are all portable-correct as written.

Two shapes I suspected and cleared, so they do not get re-raised:

- `scripts/resolve.sh:48` — `[ "$(… | wc -l)" -gt 1 ]` without the `tr -d ' '`
  the other three `wc` sites use. BSD `wc` pads, but bash's `[ … -gt … ]` skips
  leading whitespace (`[ "       2" -gt 1 ]` → true), as does `$(( ))`. Not a
  macOS break. The `tr` *is* required at `index-compose.sh:647` and
  `index-merge.sh:153`, which compare with `=` — and both have it.
- A `while`/`for` body ending in `continue` or in a false `[ … ] && …` list does
  not leak a non-zero status or trip errexit (verified: rc=0 in both shapes), so
  `gitlore_compose_root_bullets` and `push-memory.sh:372-374` do not produce the
  spurious pipeline failures they look like they might.

---

## plugin-dev (vendored — propose upstream only)

Do not edit in place; these go to `claude-plugin-dev` and arrive via a
`dist-vX.Y.Z` bump.

- **NIT — `plugin-dev/release.sh`, `check_marketplace_writable`**:
  `probe=$(mktemp "$marketplace_dir/…XXXXXX" 2>/dev/null) || die "… If this is a
  Claude Code sandbox restriction: …"`. Provoking the failure is the mechanism,
  so the redirect is defensible, but mktemp's own words are discarded and the
  message asserts a sandbox cause — a missing directory or a full disk gets the
  same sandbox advice. `err=$(mktemp … 2>&1) || die "$marketplace_dir is not
  writable: $err …"` keeps both.
- **NIT — `plugin-dev/release.sh`, `common_preflight`**: the new
  `git diff --quiet HEAD -- . ':(exclude)memory'` hardcodes `memory` as the
  gitlink path. gitlore's own `mempath` is `$1` to `install.sh` and only
  defaults to `memory`, so a consumer that installed elsewhere still gets
  "uncommitted changes". Reading the submodule path from `.gitmodules` would
  generalise it.

I checked and **cleared** the one shape that looked like a BLOCK here: the added
`[ "$mode" = "release" ] && check_marketplace_writable` sits mid-function, not
at the end of `common_preflight` (which ends with the `git -C "$MARKETPLACE_DIR"
diff --quiet … || die`). A false `&&` list mid-function is exempt from errexit
(verified: execution continues, function returns 0), so `release.sh --resume` is
not broken. Had that line been last, the bare `common_preflight` at line 306
would have exited 1 with no message — verified separately, and worth a comment
upstream so a later edit does not move it there.

## Not covered

`scripts/check-docs-links.py` and `scripts/check-memory-hygiene.py` (+965 lines
since v0.5.0) are Python, outside this skill's scope. `scripts/git-hooks/*` and
`scripts/lib/log.sh` are unchanged since v0.5.0 and were read only where a
touched file's behaviour depended on them (the `|| exit $?` call site in B2).
