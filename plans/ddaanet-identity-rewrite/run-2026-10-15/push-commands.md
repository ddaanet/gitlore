# Option H: record, archive, push and crossing commands

Every block is my human partner's to run, in order, each only after the previous
block's check printed what it says. The mirrors live on tmpfs under
`/tmp/claude-1000/identity-rewrite-h2` and do not survive a reboot: run blocks
1–4 before any restart, or redo the run. Every force-push leases on the remote's
current id, so a remote that moved since this run refuses instead of being
overwritten. The blocks are bash: run them under `bash`, or with the `!` prefix
in a Claude Code session, not in fish.

## 0. Gates

- The laptop runs gitlore 0.10.0 (D62's guard). A clone on a machine without it
  merges the old history back on its next merge or push.
- No session is live in any of the 14 clones that mount the tier, on any
  machine, until that clone has crossed (section 5).
- The remotes still hold the ids this run rewrote:

```sh
git ls-remote git@github.com:ddaanet/ddaanet-memory.git; git ls-remote git@github.com:ddaanet/gitlore-memory.git; git ls-remote git@github.com:ddaanet/gitlore.git refs/heads/main
```

Expected, and no `gitlore/*` branch anywhere: tier `live`
9662781221a887f9a7f050f3bce0ecf4552db6d9, tier `main`
7969ec87f99ffb46d5627f99d6efa6016461adce; memory `live`
a116ed627a5b80930ba4b42fdf9a12b2a39e3fde, memory `main`
497ac390c253735bf19a4540e92c21d92badb0e9; gitlore `main`
e993b49a295e956b032a7b8bcccd09fdd0b785c6. Any difference: stop.

## 1. Tier: record, archive, `live`

Tier `main` sits in the unchanged prefix and is not pushed.

```sh
W=/tmp/claude-1000/identity-rewrite-h2; U=git@github.com:ddaanet/ddaanet-memory.git; S=/Users/david/code/gitlore/scripts
"$S/record-rewrite.sh" "$W/tier-after.git" "$W/tier-after.git/filter-repo/commit-map" "$U" && git -C "$W/tier-before.git" push "$U" 9662781221a887f9a7f050f3bce0ecf4552db6d9:refs/heads/gitlore/archive/2026-10-15 && git -C "$W/tier-after.git" push --force-with-lease=refs/heads/live:9662781221a887f9a7f050f3bce0ecf4552db6d9 "$U" 68954767eea7d050704e6181f23b76cb917ad91f:refs/heads/live
git ls-remote "$U"
```

`record-rewrite.sh` prints `recorded 322 changed lines`. `ls-remote` lists
`68954767eea7d050704e6181f23b76cb917ad91f refs/heads/live`,
`7969ec87f99ffb46d5627f99d6efa6016461adce refs/heads/main`,
`9662781221a887f9a7f050f3bce0ecf4552db6d9 refs/heads/gitlore/archive/2026-10-15`
and a `refs/heads/gitlore/rewrites` line.

## 2. Memory store: record, archive, `live`, `main`

Remote `main` moves to the rewrite of its own current id (497ac39 → daf75b5);
the 22 local-only `main` commits stay unpublished, as now. Old `main` is an
ancestor of old `live`, so the one archive branch keeps both.

```sh
W=/tmp/claude-1000/identity-rewrite-h2; U=git@github.com:ddaanet/gitlore-memory.git; S=/Users/david/code/gitlore/scripts
"$S/record-rewrite.sh" "$W/memory-after.git" "$W/memory-after.git/filter-repo/commit-map" "$U" && git -C "$W/memory-before.git" push "$U" a116ed627a5b80930ba4b42fdf9a12b2a39e3fde:refs/heads/gitlore/archive/2026-10-15 && git -C "$W/memory-after.git" push --force-with-lease=refs/heads/live:a116ed627a5b80930ba4b42fdf9a12b2a39e3fde "$U" 3878a6d0e5e3d4cd82f4d754611cb9a6ed3306df:refs/heads/live && git -C "$W/memory-after.git" push --force-with-lease=refs/heads/main:497ac390c253735bf19a4540e92c21d92badb0e9 "$U" daf75b558f33da97d28a172e6d2539b7e7ce5676:refs/heads/main
git ls-remote "$U"
```

`recorded 211 changed lines`; then
`3878a6d0e5e3d4cd82f4d754611cb9a6ed3306df refs/heads/live`,
`daf75b558f33da97d28a172e6d2539b7e7ce5676 refs/heads/main`, the archive at
a116ed627a5b80930ba4b42fdf9a12b2a39e3fde and a `gitlore/rewrites` line.

## 3. gitlore: `main`, then tags

No record: a parent is outside D61. Remote `main` moves to the rewrite of
e993b49; the unpushed 22519aa stays unpushed (its rewrite is 3498182).
`tier-triage-nudge` stays local.

```sh
W=/tmp/claude-1000/identity-rewrite-h2; U=git@github.com:ddaanet/gitlore.git
git -C "$W/gitlore-after.git" push --force-with-lease=refs/heads/main:e993b49a295e956b032a7b8bcccd09fdd0b785c6 "$U" 09e6ad88cddf08c548bdff8f140b8d7448bb912d:refs/heads/main && git -C "$W/gitlore-after.git" push --force "$U" '+refs/tags/v*:refs/tags/v*'
git ls-remote "$U" refs/heads/main; diff <(git ls-remote "$U" 'refs/tags/*') <(git -C "$W/gitlore-after.git" ls-remote . 'refs/tags/*') && echo tags-identical
```

Prints `09e6ad88cddf08c548bdff8f140b8d7448bb912d refs/heads/main`, then
`tags-identical`. The 24 GitHub releases name their tag, and the push updates
each tag in place rather than deleting it; confirm they are still attached and
published:

```sh
gh release list -R ddaanet/gitlore -L 50 | grep -c Draft; gh release view v0.10.0 -R ddaanet/gitlore --json tagName,isDraft
```

`0`, then `"isDraft":false`.

## 4. This checkout

Tracked tree clean first — all three print nothing:

```sh
L=/Users/david/code/gitlore
git -C "$L" status --porcelain --untracked-files=no; git -C "$L/memory" status --porcelain --untracked-files=no; git -C "$L/memory/ddaanet" status --porcelain
```

Then tier, memory, parent. The parent fetches must not recurse: the vendored
`plugin-dev` gitlink 59ed770 exists nowhere and fails the fetch.

```sh
W=/tmp/claude-1000/identity-rewrite-h2; L=/Users/david/code/gitlore
cd "$L" && git -C memory fetch "$W/memory-after.git" a46bdd2f47656fbcd7d897b9c71c90975e371468 && scripts/cross-rewrite.sh memory/ddaanet && scripts/cross-rewrite.sh memory && git fetch --no-recurse-submodules "$W/gitlore-after.git" '+refs/heads/main:refs/rewrite/main' '+refs/heads/tier-triage-nudge:refs/heads/tier-triage-nudge' '+refs/tags/*:refs/tags/*' && git reset --hard refs/rewrite/main && git update-ref -d refs/rewrite/main && git fetch --no-recurse-submodules origin && echo repointed
```

Check:

```sh
L=/Users/david/code/gitlore
git -C "$L" rev-parse HEAD origin/main HEAD:memory; git -C "$L/memory" rev-parse HEAD live main HEAD:ddaanet; git -C "$L/memory/ddaanet" rev-parse HEAD live; git -C "$L" status --porcelain --untracked-files=no; for d in "$L" "$L/memory" "$L/memory/ddaanet"; do git -C "$d" log --branches --tags --format='%ae %ce' | grep -c -e t@e.c -e gitlore@local; done
```

Must print: 349818227d4ef57b02d1da2d49a268083adbe5e6,
09e6ad88cddf08c548bdff8f140b8d7448bb912d,
3878a6d0e5e3d4cd82f4d754611cb9a6ed3306df; memory 3878a6d…, 3878a6d…,
a46bdd2f47656fbcd7d897b9c71c90975e371468,
9103be7403df44f0a663e101264060b6b4e596af; tier 9103be7… twice; no status line;
`0` three times. Rehearsed end to end against local copies of the three remotes:
identical output.

## 5. The other thirteen clones

Only the tier is rewritten for them; their memory stores are not. Per clone,
before any session runs there. The scripts are called from the 0.10.0 cache by
absolute path, with `CLAUDE_PLUGIN_ROOT` exported: most clones' `gitlore.*`
config still names an older cache (0.6.0–0.9.0; shell-gotchas' 0.7.1 is gone),
refreshed only by a session, and without the variable `commit-memory.sh` and
`push-memory.sh` load their libraries from that older cache.

```sh
R=/Users/david/code/craft; export CLAUDE_PLUGIN_ROOT=/Users/david/.claude/plugins/cache/ddaanet/gitlore/0.10.0; P="$CLAUDE_PLUGIN_ROOT/scripts"
cd "$R" && test -z "$(git -C memory status --porcelain --untracked-files=no)" && "$P/cross-rewrite.sh" memory/ddaanet && bash "$P/commit-memory.sh" -F - <<'EOF' && git commit -m "🔧 memory: cross the ddaanet tier to its rewritten history" -- memory && test "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" && git -C memory/ddaanet merge-base --is-ancestor HEAD origin/live && echo crossed-and-committed
Cross the ddaanet tier to its rewritten history

The ddaanet tier's history was rewritten to correct the author identity on 55 commits; the tier gitlink moves to the rewritten counterpart of the same content. No fact changes.
EOF
```

Prints `crossed memory/ddaanet`, `staged ddaanet in …/memory`, then
`crossed-and-committed`. A clone already on the new history prints
`nothing to cross` and stops there. Then the pushes:

```sh
R=/Users/david/code/craft; export CLAUDE_PLUGIN_ROOT=/Users/david/.claude/plugins/cache/ddaanet/gitlore/0.10.0; P="$CLAUDE_PLUGIN_ROOT/scripts"
cd "$R" && bash "$P/push-memory.sh" && git push
```

The summary is this run's draft in the approval-clause format; it is not
approved until my human partner says so. Rehearsed verbatim under `env -i` on a
copy of cwd-safety (0.6.0 config and hooks, other parent files staged) against a
rehearsal tier remote: cross, memory commit and a parent commit touching only
`memory` succeed, and the tier ends pinned, on the new `live`, with 0 T commits.
The pushes were not rehearsed. A stale hooks dir makes the parent shim print
`hooks dir is stale` and skip, not fail.

Clones, each `/Users/david/code/<name>`: claude-plugin-dev, craft, cwd-safety,
edify, ghmem, handoff, micro-contrib, micro-craft, onekeys, plugin-craft,
prohibitions, sandbox-lies, shell-gotchas. All 13 sit on published tier history
with no local-only tier commits and a clean tier. The memory store must be clean
(the block's first test). The parent commit names `memory` as its only path, so
other staged or modified parent files — seven clones hold handoff files,
`.claude/settings.json` or a pending `memory` pointer — stay as they are and out
of the commit. A pending pointer is folded in: the crossing commit records the
memory store's new HEAD.

Clones on other machines take the same block once they run 0.10.0. The laptop's
gitlore clone differs, because its memory store and parent were rewritten too
and the mirrors are not there:

```sh
L=/Users/david/code/gitlore
cd "$L" && scripts/cross-rewrite.sh memory/ddaanet && scripts/cross-rewrite.sh memory && git fetch --no-recurse-submodules origin '+refs/tags/*:refs/tags/*' && git reset --hard origin/main && echo repointed
```

Adjust `L` to the laptop's path. Its memory `main`, if it holds commits past the
remote's, maps to an id only this machine has: `cross-rewrite.sh memory` then
refuses `main`, and the fix is
`git -C memory branch -f main daf75b558f33da97d28a172e6d2539b7e7ce5676` (or that
machine's own replay). Local parent commits past `origin/main` are discarded by
the reset: check `git log origin/main..main` first.

The archive branches go once every known clone has crossed (owner's call):
`git push <url> :refs/heads/gitlore/archive/2026-10-15` for the tier and the
memory store.
