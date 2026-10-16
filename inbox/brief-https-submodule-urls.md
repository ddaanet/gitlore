## Brief: https submodule urls for keyless /plugin install (gitlore)

2026-10-13

### Goal

Installing the `gitlore` plugin through `/plugin` must never need a GitHub SSH key. Claude Code's `/plugin install` clones with `--recurse-submodules`. The nested tier url inside the `memory` submodule is in SSH form, so a user with no registered key gets `Permission denied (publickey)` and the whole install aborts.

### Decisions

- Change only `.gitmodules` url values to `https://github.com/...`. Local `.git/config` urls stay SSH, so my human partner's pushes are unaffected.
- Worked example: the `sandbox-lies` repo, `dev` branch, commit "https submodule urls, so a marketplace install needs no access to the memory repos". A keyless real install of it succeeded once both urls were https (Claude Code 2.1.296).

### Edits for this repo

- `.gitmodules` (repo root): already `url = https://github.com/ddaanet/gitlore-memory.git`. No change.
- `memory/.gitmodules`: `url = git@github.com:ddaanet/ddaanet-memory.git` becomes `url = https://github.com/ddaanet/ddaanet-memory.git`.
- This edit lives inside the memory submodule, so it lands through the gitlore commit path (a commit in the memory repo), and the memory must be published afterwards (`/gitlore:push`) so the parent's recorded memory commit exists on the remote.
- Since this repo is gitlore itself, consider whether the tool writes SSH urls when it mounts a tier or creates a store; that is the source of the SSH form in every other repo. Surface it to my human partner as a separate item rather than changing it under this brief.

### Target visibility (checked 2026-10-13, anonymous GitHub API)

- `ddaanet/gitlore-memory`: 200, public.
- `ddaanet/ddaanet-memory`: 200, public.

### Constraints

- Only `.gitmodules` files change. Do not touch `.git/config`.
- Use the Read tool for `.gitmodules`, not `cat` in Bash: the command sandbox masks it.

### Verification

After the change is pushed:

`HOME="$TMPDIR/anon" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false git -c credential.helper= clone --recurse-submodules https://github.com/ddaanet/gitlore.git "$TMPDIR/anon-clone"`

Expected exit 0 with `memory/ddaanet/` populated. A credential-less clone fails on any SSH submodule url, and fails on any private repo in the chain.
