# 2026-07-22 — D17 slice 3-iii built — mounting a tier is a command, and the agent still runs no git

`/gitlore:add-tier` writes a one-shot `key=value` intent file
(`.claude/gitlore-add-tier`: `mode`, `name`, `url`, `description`) and
`scripts/cc-hooks/add-tier-batch.sh` on `PostToolBatch` runs
`scripts/add-tier.sh` for it. The trigger-file route was already the FR11
pattern, but a **second, independent** reason forced it here: mounting a tier
*clones*, and the agent's command sandbox has no network — so even with the
classifier satisfied, an agent-run `submodule add` could not reach the remote.
`mode=create` seeds the tier's `MEMORY.md` (frontmatter `description:` = its
routing guidance), pushes `main` **then** `live` so the remote's default branch
settles on `main`, and then takes the identical mount path; a `live` default
would be checked out as a branch and the ff-only `fetch origin live:live` would
refuse forever. Both modes end **mounted but INACTIVE** and make no commit
inside memory — activation stays the agent's deliberate manifest edit (which
retriggers 3-ii composition), and the staged `.gitmodules` is already
discoverable because `gitlore_tier_paths` reads the working tree. Validation
refuses a name with whitespace up front: it would mount fine but the
line-oriented manifest could never list it. The url is bounded to a scheme
allowlist (`http`/`https`/`ssh`/`git`/`file`, scp-like `[user@]host:path`, or a
local path), which refuses the `helper::address` transport form outright. Not a
shell-injection guard — the url is a quoted argument after `--`, never
interpolated — but a transport bound: git's own `protocol.ext.allow` already
defaults to `never` (2.47.3 refuses `ext::` in a submodule clone with
`fatal: transport 'ext' not allowed`), and the allowlist makes that hold
regardless of the user's git config. It earns its keep because this runs from a
**hook**, outside the agent's command sandbox and with network, so a url the
agent supplies would otherwise reach further than one the agent could use
itself. 40 cases in `tests/add_tier.bats` + `tests/cc_hook_add_tier.bats`,
including the hook exiting 0 on failure so its JSON report is not discarded
(D14).
