# Identity rewrite (scratch mirrors only) - report

VERDICT: PASS (with 3 anomalies/notes below; no wrong identity remains, no push,
no repo under /Users/david/code modified; only extra write:
/Users/david/code/gitlore/plans/ddaanet-identity-rewrite/commit-map)

## Anomalies and notes (up front)
1. UNMAPPED gitlink in memory history: commit 17ae38c6c6bc, path ddaanet ->
   cabd7c659d77 does not exist in tier-before (nor origin). It exists only in
   the local gitdir
   /Users/david/code/gitlore/.git/modules/gitlore-memory/modules/ddaanet: the
   corrupt unpushed tier compose that the later commit 04635d4 describes as
   discarded. Left unchanged (1 occurrence; the memory commit still gets a new
   id from the mailmap). Reachable from memory live.
2. UNMAPPED gitlinks in gitlore history (2, both the same value 59ed7703924f,
   absent from memory-before): commit f4c6df55f1d9 ("Squashed 'plugin-dev/'
   changes", path memory) and its merge 666ee3a73a57 (path plugin-dev/memory,
   i.e. the only gitlink at a non-"memory" path). Both left unchanged. The
   memory-path one (f4c6df5) is a vendored toolkit snapshot, not a real memory
   pointer. Gitlink counts in gitlore history: 607 at memory, 1 at
   plugin-dev/memory (tree occurrences); log shows 181 changes (179 mapped, 2
   unmapped, 0 identity-mapped).
3. filter-repo also rewrites commit ids embedded in commit messages (full and
   abbreviated, e.g. "Merge commit '<sha>' into HEAD", and short shas in bodies)
   using its own commit-map. So "git log --format='%T %at %ct %s'" is NOT
   byte-identical for tier live (45 messages) , memory (0) and gitlore main (17)
   / tier-triage-nudge (3, bodies included). I verified each differing entry
   equals the old text with embedded ids mapped through the commit-map
   (scripts/normlog.py: 0 "other" differences). Dates are byte-identical
   everywhere. Memory logs with %at %ct %s are byte-identical (cmp). Tier-main
   identical.
4. Mirror clone of the gitlore repo carried refs/remotes/origin/*; removing
   origin dropped them in the after mirrors (memory origin/live = live,
   origin/main 497ac39; gitlore origin/main 59a4adc = tag v0.9.0 commit). Not
   rewritten; not part of any verdict. The tier's main is unchanged by the
   rewrite (all 6 commits already clean): main 7969ec8 -> 7969ec8.

## Step 0 / remotes
Scratch dir
$W=/tmp/claude-1000/identity-rewrite-h created fresh. Tools: git filter-repo; mailmap at $W/mailmap
(3 lines as specified). Scripts in $W/scripts (normlog.py, cb.py, pairs.py,
pairs2.py, stale.py). Tier remote refs at clone: live
2515c5d07360f04c853faae364bf949fa4d5c584, main
7969ec87f99ffb46d5627f99d6efa6016461adce, nothing else - as expected. Memory:
`ls-remote origin`: live e3f75de2971f = local refs/remotes/origin/live; main
497ac390c253 = local refs/remotes/origin/main; HEAD 497ac39. No difference.
Local heads: live e3f75de..., main daf5f59... (main 22 ahead of origin/main, as
expected).

## 1. Tier (ddaanet-memory)
- Refs before: heads/live, heads/main only. No mode-160000 entry in any tree of
  the 350 commits (0).
- Census before (author|committer): 295 ddaa.net|ddaa.net; 55 T
  <t@e.c>|ddaa.net. No tags.
- Census after (heads): 350 David Allouche <david@ddaa.net>|same. Wrong
  identities: 0.
- Counts: live 350 -> 350, main 6 -> 6, rev-list over all refs 350 -> 350.
- Logs: main byte-identical; live differs only in embedded ids in 45 messages
  (note 3); dates and trees identical.
- main is an ancestor of live (after): yes.
- commit-map: 350 pairs; 31 ids kept (old prefix), 319 changed.
- live 2515c5d07360f04c853faae364bf949fa4d5c584 ->
  70a1adfadba79f97695d821a643a701ebf6e4c20
- main 7969ec87f99ffb46d5627f99d6efa6016461adce ->
  7969ec87f99ffb46d5627f99d6efa6016461adce (kept)
- Map at $W/tier-after.git/filter-repo/commit-map, copied to
  /Users/david/code/gitlore/plans/ddaanet-identity-rewrite/commit-map.

## 2. gitlore-memory
- Refs in memory-before: heads/live e3f75de2971f, heads/main daf5f59e663b,
  remotes/origin/live e3f75de2971f, remotes/origin/main 497ac390c253
  ($W/memory-refs.txt). No tags.
- Census before: 126 gitlore<gitlore@local>|same; 73 T <t@e.c>|gitlore@local; 10
  David Allouche <david@ddaa.net>|gitlore@local; 1 ddaa.net|ddaa.net. After: 210
  ddaa.net|ddaa.net (heads/live+main); wrong identities 0.
- Gitlink log $W/gitlink-memory.log: 121 entries, all path ddaanet; 107 remapped
  to a changed id, 13 mapped to identical id (kept tier prefix), 1 UNMAPPED
  (note 1); 0 at other paths.
- Counts: live 210 -> 210, main 65 -> 65, all-refs 210 -> 210; %at %ct %s
  byte-identical (cmp) for live and main. main ancestor of live: yes. commit-map
  210 pairs, 0 ids kept.
- Per pair (210, git diff --raw --no-renames old new in memory-after): 101
  identical trees, 109 differ only at path ddaanet with old/new tier commits
  having identical trees (checked in tier-after via refs/before); 0 other.
- Tip gitlinks: live tip -> tier d8887a4b28b3, main tip -> tier 4eefd91e72be;
  both ancestors of new tier live: yes.
- live e3f75de2971f71baab38401d9114c0e60e3407e7 ->
  6a473c94150ba86f573f4953198a36784db9e600
- main daf5f59e663b067969d4dd5bf9e43b2ac4f1c123 ->
  a46bdd2f47656fbcd7d897b9c71c90975e371468
- Map: \$W/memory-after.git/filter-repo/commit-map.

## 3. gitlore (parent)
- Refs before: heads/main 043c90540cf1, heads/tier-triage-nudge 76f9d8b1fb1,
  remotes/origin/main 59a4adc8b917, 22 annotated tags + lightweight v0.6.0
  (commit). Gitlink log \$W/gitlink-gitlore.log: 181 entries, 179 remapped, 2
  UNMAPPED (note 2), 1 at other path (plugin-dev/memory, the unmapped one).
- Census before (commits): 382 T|T; 254 ddaa.net|ddaa.net; 7
  allouche.net|allouche.net. Taggers: 11 T, 11 ddaa.net, lightweight none.
  After: 636 ddaa.net, 7 allouche.net (643 commits); taggers 22 ddaa.net. Wrong
  identities: 0 (commits and taggers).
- Counts: main 643 -> 643, tier-triage-nudge 297 -> 297, union of branches+tags
  643 -> 643. Dates byte-identical; message differences only embedded-id remaps
  (note 3): main 17, tier-triage-nudge 3, 0 other.
- Tags: 22 annotated tags: target mapped through commit-map, tagger date lines
  identical, tag header lines identical, message bodies identical (modulo
  embedded-id remap), 0 bad. v0.6.0 lightweight target correctly mapped.
- Per pair (643, in gitlore-after via refs/before): 37 identical trees, 606
  differ only at path memory; of those, memory old->new is in memory-after's
  map, and the old/new memory commits are 275 tree-identical and 331 differing
  only at ddaanet with identical tier trees; 0 other. (Unmapped f4c6df5 pair is
  among the tree-identical.)
- Table: \$W/refs-table.md (every branch and tag; memory old->new; all PASS;
  each new memory gitlink is an ancestor of new memory live (branches, v0.4.0+)
  or live and main (v0.2.0-v0.3.0)).
- main 043c90540cf19eb3f4c2fe6f1c4ee6a4bd95575e ->
  85993397697b3ea98e5bfd4e2fc14039c129a47e
- tier-triage-nudge 76f9d8b1fb1213881feb54ffd02838460e743d62 ->
  17a1bb3a2dadc64c808bbe49f5e213970f11a917
- tags old->new gitlore commit and memory commit: see refs-table.md (short ids);
  annotated tag object ids change too:

| ref | gitlore old | gitlore new | memory old | memory new | verdict |
|---|---|---|---|---|---|
| refs/heads/main | 043c90540c | 8599339769 | 7974778f9e | 437539a84f | PASS map-ok=True ancestor-of=live |
| refs/heads/tier-triage-nudge | 76f9d8b1fb | 17a1bb3a2d | 38125043a8 | 47dabec311 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.2.0 | f949885481 | 6aebf6e8ec | 12aa664fa9 | f1d71cf252 | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.1 | 5ab5e87da2 | 55f4d59a0e | 12aa664fa9 | f1d71cf252 | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.2 | a9e6689517 | dbb997b243 | e886c61ae2 | da8fc8312e | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.3 | 743619fcef | c10c20c787 | 9ba042a467 | 3fcf55290c | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.4 | cfa7a31bd7 | a1b56d9c6d | 928301adeb | 3116e4aae2 | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.5 | fb0014e323 | 3402f11411 | 928301adeb | 3116e4aae2 | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.6 | 10cfa67e77 | 7e6a984e43 | 1d1f6250f5 | 3ce97b245f | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.7 | ca349d100e | fd16b86c2e | 387e7bf08d | ab6767cb91 | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.8 | 8a33a787b3 | 27354400e1 | 90b100e88c | ce5f2d9f4e | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.2.9 | 88e51da971 | b61c644903 | e6b12d24bc | e7882d459b | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.3.0 | 75a8df5009 | cbfe223751 | ff36437d75 | b861935016 | PASS map-ok=True ancestor-of=live,main |
| refs/tags/v0.4.0 | de80af79d6 | ca8a60858b | 88209ab38a | d5cb1c21d1 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.4.1 | c75ef069bd | 2417718a25 | 6fc5290129 | ed5c0c8a13 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.4.2 | 7a6f73c855 | ccf8f33858 | 1a2b22e893 | 29aa7b3907 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.4.3 | 1d21031b45 | 82fe200e9a | 8ae5e98fa8 | 5d4b1ae4b1 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.4.4 | ea54b143dc | f9b567f663 | c7fae11062 | 47bf9c07a0 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.4.5 | cf8253da85 | 72ae72abb1 | e77aeb965d | f23d61e7d5 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.5.0 | 5aa2d0f336 | 3aeb2f31a6 | 7e6f1cd182 | b9d3f06dd9 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.6.0 | f65f5564ff | 08473de8a4 | e23c14c03c | 4325b3dcf8 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.7.0 | 224591c707 | 1d3b5a703e | 8c96c0554c | ec1dbf8196 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.7.1 | 1477975922 | 2d15e04892 | 26f261241f | 7ab3f09cd3 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.8.0 | fead8a6b6d | 6b4eca950a | cb388e84ce | 489759b7d9 | PASS map-ok=True ancestor-of=live |
| refs/tags/v0.9.0 | 59a4adc8b9 | aeafedf5c0 | 51877ba1d8 | 3b8f945376 | PASS map-ok=True ancestor-of=live |

## 4. Stale ids in tracked files
Table: $W/stale.md (433 rows, 111 files). Scanned: gitlore main tip (new),
memory live tip (new, 5 tracked files), tier live tip (new, 85 files).
Tokens >=7 hex that are a prefix of an OLD id whose new id differs, from any of
the three commit-maps. By top-level directory: plans 427, docs 4, tests 2;
memory/ (memory store) 0; memory/ddaanet (tier) 0. By repo of the id: gitlore
409, tier 24, memory 0. Largest: plans/index-edit-propagation 118,
plans/unadoptable-tier-arrival 111, plans/tier-arrival-review-minors 108,
plans/batch-retry-approval-freshness 37.
