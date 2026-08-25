## Remaining

- `memory/MEMORY.md` sits past the 25600-byte budget and Claude Code's 24.4KB loader cutoff, so tail entries are silently dropped every session and the index hook flags every write. Fix by retiring and merging entries, never by shortening lines to hit the number.
