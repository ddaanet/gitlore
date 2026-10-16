# Option H: push and repoint commands

Run each block only after the previous block's check printed what it should.
Every push uses a lease on the remote's current id, so a remote that moved
refuses the push instead of being overwritten.

## 0. The remotes still hold the surveyed ids

```sh
git ls-remote git@github.com:ddaanet/ddaanet-memory.git refs/heads/live refs/heads/main refs/heads/archive/live-pre-identity
git ls-remote git@github.com:ddaanet/gitlore-memory.git refs/heads/live refs/heads/main
git ls-remote git@github.com:ddaanet/gitlore.git refs/heads/main
```

Expected, and nothing else: tier `live`
2515c5d07360f04c853faae364bf949fa4d5c584, tier `main`
7969ec87f99ffb46d5627f99d6efa6016461adce, no archive branch; memory `live`
e3f75de2971f71baab38401d9114c0e60e3407e7, memory `main`
497ac390c253735bf19a4540e92c21d92badb0e9; gitlore `main`
59a4adc8b917b1c3a41a5a14e85fb6bce390688f. Any difference: stop.

## 1. Tier: archive branch, then `live`

Tier `main` is in the unchanged prefix and is not pushed.

```sh
W=/tmp/claude-1000/identity-rewrite-h; U=git@github.com:ddaanet/ddaanet-memory.git
git -C "$W/tier-before.git" push "$U" 2515c5d07360f04c853faae364bf949fa4d5c584:refs/heads/archive/live-pre-identity && git -C "$W/tier-after.git" push --force-with-lease=refs/heads/live:2515c5d07360f04c853faae364bf949fa4d5c584 "$U" 70a1adfadba79f97695d821a643a701ebf6e4c20:refs/heads/live
git ls-remote "$U"
```

Must list `70a1adfadba79f97695d821a643a701ebf6e4c20 refs/heads/live`,
`7969ec87f99ffb46d5627f99d6efa6016461adce refs/heads/main` and
`2515c5d07360f04c853faae364bf949fa4d5c584 refs/heads/archive/live-pre-identity`.

## 2. gitlore-memory: `live`, then `main`

```sh
W=/tmp/claude-1000/identity-rewrite-h; U=git@github.com:ddaanet/gitlore-memory.git
git -C "$W/memory-after.git" push --force-with-lease=refs/heads/live:e3f75de2971f71baab38401d9114c0e60e3407e7 "$U" 6a473c94150ba86f573f4953198a36784db9e600:refs/heads/live && git -C "$W/memory-after.git" push --force-with-lease=refs/heads/main:497ac390c253735bf19a4540e92c21d92badb0e9 "$U" a46bdd2f47656fbcd7d897b9c71c90975e371468:refs/heads/main
git ls-remote "$U" refs/heads/live refs/heads/main
```

Must print `6a473c94150ba86f573f4953198a36784db9e600 refs/heads/live` and
`a46bdd2f47656fbcd7d897b9c71c90975e371468 refs/heads/main`.

## 3. gitlore: `main`, then tags

```sh
W=/tmp/claude-1000/identity-rewrite-h; U=git@github.com:ddaanet/gitlore.git
git -C "$W/gitlore-after.git" push --force-with-lease=refs/heads/main:59a4adc8b917b1c3a41a5a14e85fb6bce390688f "$U" 85993397697b3ea98e5bfd4e2fc14039c129a47e:refs/heads/main
git ls-remote "$U" refs/heads/main
```

Must print `85993397697b3ea98e5bfd4e2fc14039c129a47e refs/heads/main`. Then:

```sh
W=/tmp/claude-1000/identity-rewrite-h; U=git@github.com:ddaanet/gitlore.git
git -C "$W/gitlore-after.git" push --force "$U" '+refs/tags/v*:refs/tags/v*'
diff <(git ls-remote "$U" 'refs/tags/*') <(git -C "$W/gitlore-after.git" ls-remote . 'refs/tags/*') && echo tags-identical
```

Must print `tags-identical`. `tier-triage-nudge` stays unpublished.

## 4. The gitlore checkout (after 1–3)

The tracked tree must be clean apart from the `memory` pointer:

```sh
L=/Users/david/code/gitlore
git -C "$L" status --porcelain --untracked-files=no --ignore-submodules=all; git -C "$L/memory" status --porcelain --untracked-files=no --ignore-submodules=all; git -C "$L/memory/ddaanet" status --porcelain
```

All three print nothing; stop otherwise. Then memory, tier, parent:

```sh
W=/tmp/claude-1000/identity-rewrite-h; L=/Users/david/code/gitlore
git -C "$L/memory" fetch "$W/memory-after.git" '+refs/heads/live:refs/heads/live' '+refs/heads/main:refs/heads/main' && git -C "$L/memory" checkout --detach 6a473c94150ba86f573f4953198a36784db9e600 && git -C "$L/memory" fetch origin && git -C "$L/memory/ddaanet" fetch origin && git -C "$L/memory/ddaanet" checkout --detach d8887a4b28b39fa50d253ad20f8529f5d8b91dd8 && git -C "$L/memory/ddaanet" branch -f live d8887a4b28b39fa50d253ad20f8529f5d8b91dd8 && git -C "$L" fetch "$W/gitlore-after.git" '+refs/heads/main:refs/rewrite/main' '+refs/heads/tier-triage-nudge:refs/heads/tier-triage-nudge' '+refs/tags/*:refs/tags/*' && git -C "$L" reset --hard refs/rewrite/main && git -C "$L" update-ref -d refs/rewrite/main && git -C "$L" fetch origin && echo repointed
```

Check:

```sh
L=/Users/david/code/gitlore
git -C "$L" rev-parse HEAD origin/main; git -C "$L/memory" rev-parse HEAD live origin/live HEAD:ddaanet; git -C "$L/memory/ddaanet" rev-parse HEAD live; git -C "$L" status --porcelain --untracked-files=no; git -C "$L" log --all --format='%ae %ce' | grep -c -e t@e.c -e gitlore@local; git -C "$L/memory" log live main --format='%ae %ce' | grep -c -e t@e.c -e gitlore@local; git -C "$L/memory/ddaanet" log live main --format='%ae %ce' | grep -c -e t@e.c -e gitlore@local
```

Must print: `85993397697b3ea98e5bfd4e2fc14039c129a47e` twice; memory
`6a473c94150ba86f573f4953198a36784db9e600` three times then
`d8887a4b28b39fa50d253ad20f8529f5d8b91dd8`; tier
`d8887a4b28b39fa50d253ad20f8529f5d8b91dd8` twice; one status line ` M memory`
(the pending pointer, as before the rewrite); then `0` three times.

## 5. The other twelve consumers

Section 3 of `plans/ddaanet-identity-rewrite/plan.md`, once per clone, before
any session runs there. `MAP` is the stored commit map (tier `main` maps to
itself).
