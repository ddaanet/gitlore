# Report: should the per-commit `/code-review medium` run asynchronously?

Written 2026-11-18 by a read-only research agent, for the question my human
partner raised on 2026-11-17. Input for a decision, not a decision.

Sources: the gitlore project transcripts (main and `subagents/` files), the
11-17 release reports in `inbox/2026-11-17-report-*.md`, and `git log`,
`git blame` and cherry-pick replays in gitlore, craft, shell-gotchas,
sandbox-lies, edify and plugin-craft. The sample goes by recency: gitlore from
11-11 to 11-18 in depth, plus the five release runs of 11-17. Measured against
`edify:review` 0.4.0 ("the review sits on the critical path, so it runs before
the next slice starts"). Shas are current `dev` shas; the sha the transcript
used is in brackets, since history was rewritten after the reviews.

**Verdict:** making the review asynchronous costs little for doc and skill-text
commits, but script commits should keep blocking. Only one deferred fix in the
sample would have conflicted, and it was a script fix, while the review often
decides what the next slice is.

## Answer

**In 1 of 7 cases, a deferred fix would have conflicted with the independent
slice that followed the reviewed commit.** One more case was blocked at file
level without a git conflict. In four reviews the next slice was the review's
own output, so an asynchronous loop could not have separated them.

Overlap was measured with `git blame` on the slice's parent (did the slice
rewrite lines the fix wrote, or lines within 3 of them), and for the cases that
matter by replaying the history in a scratch clone: the slice cherry-picked onto
the code before the fix, then the fix on top.

The seven pairs where an independent slice followed a fix (gitlore):

1. **Conflict.** The review of the fetch-timeout commit `809e28ff` [df0ab91]
   found three script defects (the rewrite-record fetch still unbounded, a bad
   `GITLORE_FETCH_TIMEOUT` killing every fetch); `9830589a` [38f6bc8] fixed
   them. The next slice, the locale sweep `2356910f`, was independent (its TODO
   item predates the review) and set `LC_ALL=C` on the git line of
   `gitlore_fetch_bounded`, next to the `if` the fix rewrote. Cherry-picking the
   sweep onto `809e28ff` without the fix conflicts in
   `scripts/lib/util-merge-state.sh`.
2. **Blocked at file level, no git conflict.** The review of `66887bfd`
   [c199a2f] found the resolve skill's Loop sending a pin line on to Resume
   commit. The fix waited ("It lands after slice A is committed and
   `skills/resolve/SKILL.md` is split, since that file holds uncommitted slice A
   text and sits at 9984 of 10000 bytes", 11-16). `0977345a` landed after
   `3be4452d`, `65249d0e` and the split `9bf855e6`; it replays cleanly in either
   order. Uncommitted edits and the size cap held it, not the diff.
3. **Target moved.** The review of `b11a1e72`+`61631592` ran while `fc8efb18`
   moved the table it had flagged; the fix brief had to say "re-check M2 against
   the tree as it is now". A re-read, no conflict.
4. **Covered by the next slice.** The medium on `45627c05` was a missing yield
   in add-tier's doc clause; slice B (`65249d0e`) rewrote that clause anyway.
5. **No overlap.** `267228c2` (README `abort-merge` command, a commit-skill
   clause) shares no file with the next slice `809e28ff`; clean replay.
6. **No overlap.** `7cc0e4fb` and `dc143c98` (three out-of-diff places from the
   review of `3be4452d`+`65249d0e`) share no file with `9bf855e6`, `0977345a`.
7. **No overlap.** The doc fix `d3e82faa` against the plan commit `7f7f33df`.

**Reviews whose finding became the next slice**, where an asynchronous loop
would only have delayed the decision: the yield review of `b3bc448a` found the
hooks fetched with no time limit, and the fetch timeout `809e28ff` became the
next slice; the review of `69568a9a` found a stuck state fixed by `27488cfa`
(mapping inferred); the review of `27488cfa` raised a deadlock question whose
answer became the generalized yield `b3bc448a`; the review of the sentinel
commit `c7e997b1` found, and a probe confirmed, that `npx husky` wires nothing
on husky v8, which became the husky slice `0326c544` (replayed without the fix
round `b992a505`, it conflicts in `docs/references/installation.md`).

**The 11-17 release runs left almost nothing for a fix to collide with.** In
craft, shell-gotchas, sandbox-lies and gitlore's own-share run, the work after a
reviewed commit was the next fix round on the same sentences: in 16 of 18
consecutive fix-round pairs the later round rewrote 1 to 6 lines the earlier
wrote (sandbox-lies 8 of 8, shell-gotchas 5 of 6, gitlore 3 of 4). That measures
how slowly a fix loop converges, not a collision with other work. The one
independent slice after such a loop, craft's `/simplify` commit `6e3b216`,
shares `genuine-red.md` with the fixes but none of their lines.

## Reviews found

In the gitlore project directory, 100 sub-agent transcripts call the
`code-review` skill from 10-30 to 11-18, about 85 of them medium runs; seven are
repo-owning agents from the 11-17 run. Sibling project directories (not opened)
hold medium-review transcripts: shell-gotchas 38, sandbox-lies 24,
claude-plugin-dev 29, plugin-craft 5, craft 6, edify 0, mostly before 11-07.

Kinds: **S** correctness in a script or routing in a skill; **D** doc or skill
text contradicting a script or source; **P** a claim or wording in skill prose;
**T** a test asserting nothing; **—** no high or medium finding.

| Session (date) | Commit or slice reviewed | High/medium | Fixed | Overlap with following work |
|---|---|---|---|---|
| 6b67d7a4 (11-11) | `f335b1d9` | —, 3 and 7 lows | 0 | n/a |
| 6b67d7a4 (11-12) | `69568a9a` | 1 S (stuck state) | `27488cfa` | finding became the next commit |
| 6b67d7a4 (11-12) | `27488cfa` | 1 D, 1 S needing a decision | D amended; S became `b3bc448a` | finding became the next slice |
| 6b67d7a4 (11-12) | `c7e997b1` sentinel | 3 D, 1 S (husky v8) | 3 in `b992a505`; S became `0326c544` | finding became the next slice; husky conflicts replayed without `b992a505` |
| 6b67d7a4 (11-12) | `b992a505` fix round | 1 D | carried by the husky commit | husky rewrote the fix's lines |
| 6b67d7a4 (11-12) | `0326c544` husky | 1 D | amended | none |
| 69ec83c1 (11-13) | `b3bc448a` yield | 1 S, 2 D | D in `267228c2`; S became `809e28ff` | finding became the next slice |
| 69ec83c1 (11-13) | `dd28c5f6` | —, 5 lows | 0 | n/a |
| 69ec83c1 (11-13) | `61af6ec5..53c8c67d` | 2 D, 1 left to my human partner | `267228c2` | no (clean replay) |
| 69ec83c1 (11-13) | `809e28ff` fetch timeout | 3 S | `9830589a` | **yes**: `2356910f` conflicts on replay |
| 69ec83c1 (11-13) | `9830589a` | 1 D | `9377b547` (doc drift) | none |
| 69ec83c1 (11-13) | `2356910f`, `af54441f`, `dd7fb602` | 1 | 1 | none |
| 69ec83c1 (11-13) | `c6b28dc5` | —, 3 lows | 0 | n/a |
| adee4951 (11-14) | three splits | —, 5 lows | 0 | n/a |
| adee4951 (11-14) | `078d5ba8` | — | 0 | n/a |
| adee4951 (11-16) | `b11a1e72`+`61631592` | 2 D, 2 S | `22d5dd53`, `9c5f4da7` | target moved by `fc8efb18` |
| adee4951 (11-16) | `fc8efb18` | — | 0 | n/a |
| adee4951 (11-16) | loop `9c5f4da7` → `ab21df02` → `66887bfd` | 2, 2, 1 on one bullet | claim dropped at round 3 | each round rewrote the one before |
| adee4951 (11-16) | `66887bfd`+`45627c05` | 1 S, 1 D | S in `0977345a` after the split; D covered by slice B | file-level wait; covered |
| adee4951 (11-16) | `3be4452d`+`65249d0e` | 1 S, 2 D | `7cc0e4fb`, `dc143c98` | no |
| adee4951 (11-16) | `9bf855e6`+`0977345a` | — | 0 | n/a |
| adee4951 (11-16) | `7cc0e4fb`+`dc143c98` | doc drift, 1 left to my human partner | `d3e82faa` | no |
| f50b0e00 (11-17) | gitlore `338e5252` own share | P, five rounds | `98c4ffb6` to `b9291a05` | fix rounds only |
| f50b0e00 (11-17) | craft `d62855e` | 10, 6, 7, 5 (P) | 4, 4, then dropped; last round declined | `6e3b216`: same file, different lines |
| f50b0e00 (11-17) | craft release loop `d54db69` to `885abc0` | 8, 7, 1, 7 (P) | four rounds | fix rounds only; reopened after release by `09aaf0e` to `2dc287d` |
| f50b0e00 (11-17) | shell-gotchas `1710bc6`, `bdd0717`, rounds | D then P, seven rounds | `3473616` to `51bd1c8` | fix rounds only |
| f50b0e00 (11-17) | sandbox-lies `4b54d96` | P/D, three rounds | reverted in `7eb1802` | fix rounds only |
| f50b0e00 (11-17) | sandbox-lies `403f402` to `f202fc9` | P, four rounds | dropped at round 4 | fix rounds only |
| f50b0e00 (11-17) | sandbox-lies hook `464b083` to `6a05e5b` | S+D, five rounds | each fixed | fix rounds only |
| f50b0e00 (11-17) | edify `81444b31` | S, P | `a989a52d` | reviews ran while other agents edited the tree |
| f50b0e00 (11-17) | edify `a989a52d`, `0a40acf2` | 2, then 5 | 1 carried into the packaging commit; rest in `0ce0dad5` | absorbed into the following commit |
| f50b0e00 (11-17) | edify `0ce0dad5` | 1 P | `067dc0e2`, after the 26-file move | fix on a renamed path; not replayed |
| f50b0e00 (11-17) | plugin-craft `3c55f95`; `d4f11a8` | not read | `46d79b8`; `390ff32` | not established |
| 242f7b47 (11-18) | release medium loop | not read | `31d7962d` to `a25dda44` | release fixes rewrote the 11-16 per-commit fixes (`e058d484`: 4 lines of `7cc0e4fb`) |

Script findings come from gitlore's script commits, and about half turned into
design decisions. Doc-contradicts-script is the most common gitlore medium.
Prose findings are almost all from the 11-17 runs. No medium review returned a
"test asserts nothing" finding; those come from the red-phase reviews.

## The trade-off, from the data

**Gained by an asynchronous loop.** Wall time: review agents run a median 8.7
minutes first to last transcript line (p25 4.0, p75 21.7, n = 75); each fix
commit then pays a gate of about 9 minutes, so a blocking round costs about 18
minutes, and the 11-17 runs had four to seven rounds per loop. The 11-17 kind of
loop gains most: prose converging on one sentence, colliding with nothing, yet
blocking the release. It is already partly the practice: on 11-13 three
reviewers ran in parallel while red tests were written; on 11-16 reviews ran
alongside the red, green and split agents; edify's reviewers read "only through
git" because other agents were editing the tree. A slice that rewrites the
flagged text anyway closes the finding for free (case 4, edify's `lib/`).

**Lost when a finding lands two slices late.** A script fix in a function the
next slice builds on stops being a clean edit (case 1), and the next slice is
reviewed against code that still has the defect. The review often decides the
next slice: about half of gitlore's S findings did. The gate's hash breaks: an
edit landing mid-run voids it ("a husky red-test dispatch now would void the
pass", 11-12), so an asynchronous fix commit needs its own gate over a tree the
next slice is also editing and in practice waits anyway (case 2). Findings
drift: a target can move (case 3), and the 11-18 release loop re-fixed lines the
11-16 per-commit fixes had written.

**Where it nets out** (the agent's inference, not a measured rule): doc and
skill-text reviews can trail behind the next slice; a review should keep
blocking when the commit touches `scripts/` or `bin/`, or when the next slice
edits the same files.

## Not established

- About 100 sibling-repo medium reviews, mostly before 11-07, were not read; the
  11-17 sibling runs were covered only through gitlore-side agent files and the
  inbox reports.
- gitlore reviews from 10-30 to 11-10 were listed, not triaged; the 418c4f51
  compose-state chain of 7 reviews is the next worth reading.
- The 11-18 release medium loop and the plugin-craft reviews were not read.
- Blame cannot see a fix that only deletes lines, which the "drop the claim"
  rule produces, so overlap is undercounted for those rounds; fixes amended into
  their own commit have no commit to measure; TODO.md and TASK.md were ignored.
- Fix counts and kinds come from triage text and reports, not from re-reading
  each review file. Transcript shas were mapped to current shas by commit
  subject; the `27488cfa` mapping is inferred.
- Only cases 1, 2 and 5 and the husky pair were tested by cherry-pick replay.
