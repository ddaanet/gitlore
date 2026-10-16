## Brief: gitlore writes https urls into `.gitmodules`

2026-10-13

### Goal

A repo that gitlore installs into, or mounts a tier into, must end up with https urls in its tracked `.gitmodules` files, so that anyone can clone it with its submodules without a GitHub SSH key. Today gitlore writes SSH urls there, and every ddaanet plugin repo inherited them.

### Why it matters

Claude Code's `/plugin install` clones a plugin repo with `--recurse-submodules`. A user with no SSH key registered on GitHub gets `Permission denied (publickey)` on the `memory` submodule, or on the tier nested inside it, and the whole install aborts. My human partner's requirement: installing through `/plugin` must never need a GitHub SSH key. Verified on Claude Code 2.1.296 with sandbox-lies: a keyless real install succeeds once both urls are https and both repos are public.

A structural scan of my human partner's checkouts on 2026-10-13 found SSH urls in the root `.gitmodules` of eleven plugin repos and in `memory/.gitmodules` of nine. Each has its own `inbox/brief-https-submodule-urls.md` for the one-off fix; this brief is about the generator, so new installs stop producing them. The sibling brief in this inbox, `brief-https-submodule-urls.md`, covers gitlore's own tier url.

### Where the SSH url comes from (read on 2026-10-13, verify before editing)

- `scripts/install/create-remote.sh`: after `gh repo create`, it reads `gh repo view "$full_name" --json sshUrl -q .sshUrl` into `remote_url`, then uses that one value twice: `git -C "$mempath" remote set-url origin "$remote_url"` and `git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.url" "$remote_url"`.
- `scripts/add-tier.sh`: after `gh repo create "$full_name" --private`, it reads `sshUrl` the same way for the tier url.
- `commands/add-tier.md`: its example mounts the tier with `url=git@github.com:ddaanet/ddaanet-memory.git`.
- `tests/install_remote.bats` stubs the `sshUrl` query, so it pins the current behaviour.

### The requirement, and what is open

Required: the url recorded in a tracked `.gitmodules` (the parent's for `memory`, the memory repo's for a tier) is the https form, `https://github.com/<owner>/<repo>.git`.

Decided by my human partner on 2026-10-13:

1. Pushes keep SSH. `.gitmodules` records the https url; the submodule's own remote, the one pushes go through, stays SSH so existing push authentication is untouched. The one-off fixes in the sibling repos did the same by editing only `.gitmodules` and leaving `.git/config` alone.
2. Existing installs are fixed through the per-repo briefs only. No SessionStart or install-time repair rewrites an existing `.gitmodules`.
3. Private repos get a warning. `add-tier.sh` creates the tier `--private`, and a private repo anywhere in the chain aborts an anonymous recursive clone whatever the url form, so gitlore warns when a public parent gets a private memory or tier. Where the warning fires and what it says is yours to design.

4. A url the person passes in themselves is rewritten for `.gitmodules`. This covers the cases where gitlore does not create the repo: install given an explicit remote url, and a tier mounted by url as in the `commands/add-tier.md` example. An SSH GitHub url is recorded in `.gitmodules` in its https form, and the remote keeps the SSH url that was given, so pushes stay on SSH as in decision 1.

### Constraints

- A guard elsewhere compares urls: check every reader of `submodule.<name>.url` and `remote.origin.url` (placeholder detection, the "remote already wired" test in `create-remote.sh`, divergence and push routing) so a `.gitmodules` url that differs from the remote url does not read as a mismatch. A tier fact in memory, `submodule-url-arrives-rewritten`, records one earlier failure of this kind.
- The memory repo's own `.gitmodules` is inside the memory submodule, so a tier url change there lands through the gitlore commit path and needs a publish.
- Do not change repository visibility from an agent; that is my human partner's call.

### Verification

For a fresh install in a scratch repo and a fresh tier mount, `git config --file .gitmodules --get-all submodule.gitlore-memory.url` and `git config --file memory/.gitmodules --get-all submodule.<tier>.url` each print an `https://github.com/` url. End to end, once pushed and public:

`HOME="$TMPDIR/anon" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false git -c credential.helper= clone --recurse-submodules https://github.com/<owner>/<repo>.git "$TMPDIR/anon-clone"`

Expected exit 0 with `memory/` and its tier directory populated. To simulate a keyless machine for a real `claude plugin install`, put a stub `ssh` that exits 255 first on `PATH`: a scratch `HOME` alone does not hide the real keys.
