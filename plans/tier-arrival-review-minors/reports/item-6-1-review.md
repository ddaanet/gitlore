# Item 6.1 review — merger and resolve-skill routing on the continuation's exit

Verdict: **pass after fixes.** There are no Critical or Major findings. Two
Minor wording fixes were applied. Nothing was committed or staged.

## 1. Quoted strings against the shipped script

Every quoted string is a real prefix of an emitted line:

- `gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:`
  matches `scripts/resolve.sh:136` in full.
- `gitlore: the merge message file could not be created` is a prefix of `:311`.
- `gitlore: the merge message could not be built` is a prefix of `:322`.
- `gitlore: the merge commit was refused` is a prefix of `:328`.
- `gitlore: memory merge prepared` is a prefix of the banner in
  `gitlore_emit_merge_directive` (`scripts/lib/resolve.sh`). That banner goes to
  stderr, which matches the skill's Standalone text "on stderr".
- The three Item 4.1 texts do not contain one another, so each prefix selects
  one arm.

## 2. Each exit class through the merger and the skill

| Exit class | Merger arm | Skill route | Landing claim? |
|---|---|---|---|
| Pre-landing refusals with a `gitlore:` line (`:35,43,52,58`) | other non-zero, fate unknown | Summarize | no |
| Pre-landing errexit aborts (load state, staging `add`) | other non-zero | Summarize | no |
| Merged-index refusal (`:136-138`) | merged-index arm | same sub-agent gets `rejected:` | no |
| Message-file, message-build or refused-commit (`:309-330`) | unlanded, stays prepared | Summarize, no `rejected:`, no Loop | no |
| exit 0 (`:375`, `:389`) | landed; quote `gitlore:` lines | Loop, then Resume commit, then Summarize | yes |
| Re-yield after a divergent `live` push (`:360`, `:381`) | landed and a new merge is prepared | Loop | yes (correct: the commit is at `:325`) |
| A failed re-yield (`\|\| exit 1`, no directive) | other non-zero | Summarize | no |
| `not because of divergence` push failure (`:364`, `:384`) | other non-zero | Summarize | no |
| Post-landing errexit (`update-ref -d`, clear-state, bookkeeping) | other non-zero | Summarize | no |

The directive is printed only when `gitlore_yield_merge` returns 0, and only
after the merge commit. Nothing before the merge commit prints it, so the
re-yield key is safe. Only exit 0 and the re-yield lead to a landing claim, and
both are true landings. The routes match the runbook's Item 6.1.

## 3. Flow coherence in the skill

- The new routing paragraph comes after the merged-index paragraph, as the
  runbook specifies. It does not contradict **Loop**: the re-yield goes to Loop,
  where `resolve.sh` re-emits the directive for the fresh merge.
- **Minor, fixed.** The two routes to **Summarize** jump over **Resume commit**
  only because of where the sections sit. Resume commit's "now that memory is
  resolved" is the only thing that stops a retry. Each of those two bullets now
  says `skipping **Resume commit**` explicitly, so an unlanded or unknown merge
  cannot lead to retrying the triggering commit.
- **Summarize** now opens with the landed-only rule. The post-landing sentence
  is now limited to "On a landed merge", and it is consistent with the exit-0
  arm. A refused-push remedy can still print at exit 0 (the tier-rest lines at
  `scripts/resolve.sh:227-232`).
- The Standalone text (`0` means healthy; non-zero with the banner means Parse
  directive; any other non-zero means surface and stop) still describes
  default-mode `resolve.sh` correctly. The continuation's exits never reach it
  directly.

## 4. Directive quality

- **Minor, fixed.** The merger and the skill's Summarize told the agent to quote
  "the reason git or the hook printed above it". A failed `mktemp` prints
  `mktemp`'s own error, not git's, and a message-build failure may print nothing
  from git. Both files now say "whatever the failing command printed above it",
  and Summarize's remedy says "fix that cause". This covers every arm and
  implies no reason that may be absent.
- Every arm states an act. There is no hedging, and no "Otherwise …
  post-landing" residue remains. The closing "In every branch, do not run the
  continuation a second time" is indented under the `approved` item, so it stays
  inside that item.
- Wrapping matches each file. The merger keeps long lines. The skill's
  Approve-or-reject bullets stay unwrapped, like their section, and the
  Summarize lines are hard-wrapped at ≤ 87 columns, like the existing lines.
  `SKILL.md` is 103 lines.

## Runs

- `GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/plugin_distribution.bats`:
  **15 passed, 0 failed**, after the edits.

## Files changed

- `/Users/david/code/gitlore/agents/memory-merger.md`: the refused-commit arm's
  quoting wording.
- `/Users/david/code/gitlore/skills/resolve/SKILL.md`:
  `skipping **Resume commit**` on both Summarize routes, and the Summarize
  bullet's quoting and remedy wording.

## UNFIXABLE

None.
