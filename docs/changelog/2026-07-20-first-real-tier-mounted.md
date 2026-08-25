# 2026-07-20 — D17 slice 3-i-a dogfooded — the first real tier is mounted

`ddaanet/ddaanet-memory` (private) seeded with a frontmatter-describing
`MEMORY.md` and mounted as `memory/ddaanet`, with `ddaanet` listed in
`memory/.gitlore-tiers`. The tier remote keeps `main` as its default branch with
`live` alongside it: a mount checks out the default branch, so a `live` default
would be checked out *as a branch* and `fetch origin live:live` would then
refuse to fetch into the current branch — the ff-only propagation-in guarantee
depends on `live` never being the checked-out branch. Private visibility departs
from `gitlore_parent_visibility` (this repo is public) because a tier aggregates
facts from private projects and so takes the stricter of its consumers'. Against
the real mount, `gitlore_tier_paths`, `gitlore_active_tiers`, and
`gitlore_get_frontmatter_description` all resolve, confirming
discovery-by-enclosure and the manifest on non-fixture data. Propagation-in
works with the mount merely staged in the memory index — `gitlore_tier_paths`
reads `memory/.gitmodules` from the working tree, not from a commit — so
mounting needs no commit inside the memory store, keeping the FR11 gate the sole
committer. The manifest's "consumer-local" wording means per-consuming-repo and
tracked, not per-machine: activation and precedence travel with the memory store
to every clone.
