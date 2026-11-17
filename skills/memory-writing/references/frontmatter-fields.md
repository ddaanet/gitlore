# The metadata fields Claude Code stamps

A memory file's `metadata:` block — `node_type: memory`, `originSessionId`,
`modified` — is written by Claude Code, not by gitlore. gitlore's index sync
rewrites the first `description:` line and passes every other line through.

One function in the Claude Code bundle writes the block (its log messages call
it `stampNewMemoryContent`). It transforms the content synchronously inside
three tool handlers, before the bytes reach disk: `Edit`, `Write`, and the
memory-store `write` tool, that one only for a `personal` store. Nothing else
emits the block: no file watcher, no post-write pass.

- **A `Bash` write never stamps** — a subprocess (`sed -i`, a `python3`
  heredoc) or Claude Code's in-process simulated `sed` edit alike.
- **`originSessionId` is written only when the key is absent.**
- **`modified:` is a lower bound.** Besides every `Bash` write, the stamper
  returns the content untouched — logging `not stamping provenance` or
  `not dating` at warn, or silently — when the file is not `.md`; its path is
  not a lexical prefix match under the memory root (no realpath, so a
  symlinked memory dir is skipped); the new content does not open with a
  `---` fence at byte 0; the frontmatter carries a `rewriteHazard`; the
  `metadata:` mapping is inline (`{…}`) rather than block-style; or the
  rewrite fails its own re-parse. A file carrying none of the fields can pass
  through an `Edit` under the memory root and acquire none of them.
- **`<memory>/team/` files** get the `modified:` rewrite but never
  `originSessionId` or `node_type`. **`MEMORY.md`** is inside the stamping
  scope and is spared only for lacking a frontmatter fence; given one, it is
  stamped.

To learn who last changed a memory file, read its git history, not
`modified:`.

Read from the Claude Code 2.1.261 bundle; the same stamper is in
2.1.258–2.1.260.
