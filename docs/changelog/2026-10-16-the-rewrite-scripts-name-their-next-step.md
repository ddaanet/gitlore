# 2026-10-16 — The rewrite scripts name their remote and their next step

**A record-rewrite message names the remote it used.** The no-op message and the
unreadable-version and unreadable-map refusals of `scripts/record-rewrite.sh`
name `$remote`: the URL when the third argument is one, `origin` by default.

**A crossing refusal says what resolves it.** `scripts/cross-rewrite.sh`
refusals the reader can act on end in the act: a store or child that is not
checked out prints the `git submodule update --init` command for it; a fetch
failure says to run again once the remote is reachable; a remote with no record
prints the `record-rewrite.sh` command that publishes it; a record that cannot
be read (no version file, a version that is not a number, no map, a line that is
not a pair of ids, a chain that does not end) prints the from-scratch rebuild
(D63). The command that publishes a first record needs the rewrite's commit-map,
which only the rewritten mirror holds as `filter-repo/commit-map`; its refusal
says to set `MIRROR` to it. A mapped commit the clone lacks is fetched from the
remote's `main` first, and when it is still absent the refusal says the
rewritten history has not reached the remote, and to run the script again once
the force-push has landed; it never prints a rebuild, since the record may be
right. Trees that differ outside gitlinks and a gitlink the child's record maps
elsewhere print the `git diff` that shows them and say a person decides. A
version that is an integer above 1 says to update gitlore, and any other version
is a damaged record. A dropped commit prints the move of the ref to the remote's
tip, and the `git log` that lists local work to replay first. A commit on
neither the remote's history nor a recorded commit prints the `git log` that
compares it with the remote and says a person decides. The checkout command runs
from the repository holding the gitlink, with a step for each path component not
yet checked out: a tier whose memory store is absent initializes the store
first. A git that cannot report the object format fails with its own message.

**A child's record is fetched once per run.** The script keeps each mounted
child's map by path, so the gitlink checks of every ref and the children scan
share one fetch.

**The record's id length follows the store's object format.** Both scripts read
`git rev-parse --show-object-format`: ids are 40 hex digits in a sha1 store and
64 in a sha256 one, and a dropped commit maps to zeros of that length. A
mismatched line is refused. The record version stays `1`; the length belongs to
the store, not to the record.

**A damaged record is rebuilt from scratch (D63).** The refusal for a record
that cannot be read prints, with the store's absolute path and the script's: the
`git push origin --delete gitlore/rewrites` that removes it, a
`record-rewrite.sh` line for the commit-map, and the `git ls-remote` that shows
the branch is back. When the store holds a `filter-repo/commit-map` its path is
printed; otherwise the refusal says the file is in `.git/filter-repo/commit-map`
of the clone that ran the rewrite and `<commit-map>` is the one placeholder. A
rewrite whose commit-map is no longer at hand drops out of the record; each
further commit-map takes one more `record-rewrite.sh` line, oldest rewrite
first. An in-place salvage is rejected: it costs more than it buys for a record
only `record-rewrite.sh` writes. Between the delete and the first record the
remote has no record, which the divergence check reads as no rewrite.
