# The memory remote — decisions D8, D64, D65

How the memory submodule's remote is named, created and recorded: the creation
methods and the install-time disclosure, why creating it waits for explicit
confirmation (D8), which url `.gitmodules` records and which the submodule's
remote keeps (D64), and the warning for a private remote under a public parent
(D65). Read it while creating or debugging a memory remote or a clone that
cannot reach one. The install command's own steps are in
[installation.md](installation.md).

- The remote — **D8** remote creation requires explicit user confirmation ·
  **D64** `.gitmodules` records the https url while the remote keeps the one
  given · **D65** a private remote under a public parent is warned about, never
  changed

---

## Remote Repository

The memory submodule is pushed to a dedicated remote, matching the parent repo's
provider, ownership, and visibility where possible.

**Naming**

- Default: `<parent-remote-name>-memory`, derived from `origin` on the parent
  (e.g., `github.com/org/project.git` → `project-memory`).
- If a repo with the default name exists in the target namespace, prompt for an
  alternative.

**Ownership**

- Default: same owner as parent `origin` (user account or org).
- Overridable at creation time.

**Visibility**

- Default: match parent repo (public parent → public memory; private parent →
  private).
- Rationale: memory is auxiliary to the project; no reason to split access
  control.
- User can override the default.

**Install-time disclosure (informational)**

Before creating the remote, display proposed name, owner, and visibility
(inherited from parent), along with:

> Memory pushed to this remote may contain any context Claude has recorded —
> project details, decisions, or incidental session content. Each memory commit
> is reviewed and confirmed before it's pushed, so you control what goes up.

This is orientation, not a clearance gate. The effective gate is the per-commit
review (FR 11).

**Creation method**

1. **GitHub + `gh` CLI available** →
   `gh repo create <owner>/<name> [--public|--private]` matching parent
   visibility.
2. **Other providers** → emit copy-paste instructions: "Create a repository at
   `<detected-provider>` named `<name>` with matching visibility, then paste the
   clone URL here." Wait for URL.
3. **Parent has no remote** → skip memory remote creation. Memory stays
   local-only. Informational message; user can add a remote later.

**On creation failure** (auth, quota, network, name collision): fall back to
method 2 (copy-paste). Do not abort install.

**The url `.gitmodules` records (D64, D65)**

The submodule's `remote.origin.url` keeps the url it was wired with — the one
`gh repo view --json sshUrl` returned, or the one the person supplied — so
pushes stay on that transport. The tracked `.gitmodules` records the https form
(`https://github.com/<owner>/<repo>.git`), so a recursive clone, including
Claude Code's `/plugin install`, needs no GitHub SSH key. Only a GitHub ssh url
(`git@github.com:o/r[.git]`, `ssh://git@github.com/o/r[.git]`) is rewritten; an
https url, another host and a local path are recorded as given.

No script compares `.gitmodules`'s url with the remote's, so the two may differ
in protocol. Every reader of `remote.origin.url` tests only for empty or the
local-only placeholder (`gitlore_is_placeholder_url`); the placeholder is the
one `.gitmodules` value that is matched, by basename, because
`git submodule sync` absolutizes it on the way into `remote.origin.url`. A
`git submodule sync` or a fresh clone sets the submodule's remote to the https
`.gitmodules` url; that is the clone's own remote, and pushing from it needs
https credentials, which an SSH key does not supply and a passing
`gh auth status` does not imply. The push-failure hint, for memory and for each
tier, names the two fixes: `gh auth setup-git`, which registers gh as git's
credential helper, or
`git -C <path> remote set-url origin git@github.com:<owner>/<repo>.git`, which
puts that clone back on SSH and is printed only when the store's origin is a
GitHub https url, with the store's absolute path and the owner and repo read
from that url filled in. Nothing rewrites a clone's remote automatically.
Existing installs keep the url they have; nothing rewrites a `.gitmodules` after
the install that wrote it.

A private repository anywhere in the chain aborts an anonymous recursive clone
whatever the url form. When the person supplies the memory remote (url mode) and
`gh` confirms the parent public and that remote private, install prints one
stderr line naming the remote. Auto mode creates the remote with the parent's
visibility, so it cannot produce the pair while `gh` can read the parent's
visibility; when it cannot (an SSH host alias as the parent origin, no auth for
the org, the network down) the parent reads as private, the memory remote is
created private, and no warning is printed. A visibility `gh` cannot read prints
nothing, and install never changes a repository's visibility.

**Push semantics**

Per NFR5 (double-commit semantics): memory `live` is pushed before parent push
on every `git push`. Parent remote always points at a submodule SHA reachable on
the memory remote.

## Decisions — D8, D64, D65

Why creating the memory remote asks first, and which url the tracked
`.gitmodules` records.

**D8 — Remote creation requires explicit user confirmation**

Creating a remote repository is a visible external action with side effects
outside the local machine (namespace occupancy, provider-side records,
potentially public visibility). Even when `gh` CLI is available and parameters
are straightforward, the agent presents the full proposal — name, owner,
visibility, creation method — and waits for explicit approval before executing.

This confirmation is distinct from the install-time disclosure, which is
informational orientation. D8 gates the specific external action. Rationale:
external actions are not covered by the per-commit review gate and require their
own opt-in.

**D64 — `.gitmodules` records the https url; the remote keeps the one given**

The tracked `.gitmodules` (the parent's for memory, memory's for a tier) records
`https://github.com/<owner>/<repo>.git` for any GitHub ssh url, given or
resolved, so an anonymous recursive clone, including `/plugin install`, needs no
SSH key. The submodule's own `remote.origin.url` keeps the url as given, so
pushes stay on their transport. The mechanism and its residuals are in
[The url `.gitmodules` records](#remote-repository) above. Recording the ssh url
aborts an anonymous clone on a publickey error; rewriting the remote to https as
well breaks existing push auth; rewriting an existing install's `.gitmodules`
from `SessionStart` or install touches repos that were never asked, so those are
fixed through per-repo briefs only.

**D65 — A private remote under a public parent is warned about, never changed**

A private repository anywhere in the chain aborts an anonymous recursive clone
whatever the url form, so no url choice repairs it. Install in url mode and
`/gitlore:add-tier` print one stderr line when `gh` confirms the parent public
and the memory or tier remote private; visibility is the repository owner's call
and is never changed. An unknown visibility (no `gh`, no auth, non-GitHub, a
local path) is silent, because a warning on a guess is a false alarm every time.
Creating tiers public by default decides the owner's question for them; refusing
the mount strands a legitimate private tier; a flag or command for the check
adds surface for a one-line report.

## Rejected alternatives

**`gh repo create` as the only remote-creation method.** Locks out non-GitHub
users; the provider-agnostic copy-paste flow covers them.

**Making the memory push optional in v1.** Gitlore without shared memory is a
diminished product. An opt-out can be added later as a preference.
