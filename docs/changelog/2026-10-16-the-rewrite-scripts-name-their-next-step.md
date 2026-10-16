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
not a pair of ids, a chain that does not end) prints the
`record-rewrite.sh --rebuild` run that repairs it, with the origin's URL made
absolute. The rebuild needs the rewrite's commit-map, which only the rewritten
mirror holds as `filter-repo/commit-map`; the refusal says to set `MIRROR` to
it. A mapped commit the clone lacks is fetched from the remote's `main` first,
and when it is still absent the refusal says the rewritten history has not
reached the remote, and to run the script again once the force-push has landed;
it never prints a rebuild, since the record may be right. Trees that differ
outside gitlinks and a gitlink the child's record maps elsewhere print the
`git diff` that shows them and say a person decides. A version that is an
integer above 1 says to update gitlore, and any other version is a damaged
record. A dropped commit prints the move of the ref to the remote's tip, and the
`git log` that lists local work to replay first. A commit on neither the
remote's history nor a recorded commit prints the `git log` that compares it
with the remote and says a person decides. The checkout command runs from the
repository holding the gitlink, with a step for each path component not yet
checked out: a tier whose memory store is absent initializes the store first. A
git that cannot report the object format fails with its own message.

**A child's record is fetched once per run.** The script keeps each mounted
child's map by path, so the gitlink checks of every ref and the children scan
share one fetch.

**The record's id length follows the store's object format.** Both scripts read
`git rev-parse --show-object-format`: ids are 40 hex digits in a sha1 store and
64 in a sha256 one, and a dropped commit maps to zeros of that length. A
mismatched line is refused. The record version stays `1`; the length belongs to
the store, not to the record.

**A damaged record is repaired in place (D63).** `record-rewrite.sh --rebuild`
keeps every readable line of the remote's map, drops the rest and reports their
line numbers, writes version 1, merges the commit-map and pushes one commit on
the tip it read: a fast-forward, so the record is never absent from the remote
and never rewritten. The push is leased to that tip, so it overwrites nothing
and refuses a record rolled back or deleted since the read. A map with CRLF line
endings keeps its lines. A record of a newer version is refused. Deleting the
record and recording it again is rejected: the gap reads as no rewrite to every
clone's divergence check, a delete has no lease, and a plain run starts from an
empty map.
