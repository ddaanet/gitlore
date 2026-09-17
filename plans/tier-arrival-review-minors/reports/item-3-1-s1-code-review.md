# Code review: Item 3.1 slice 1 (a631b6e)

Scope: `gitlore_repair_index` tag arrays and final write, and the M8 comment in
`scripts/lib/index-compose.sh`.

## Verdict

The function follows the rule. The output ends unterminated only when the input
was unterminated and the last output element is the input's last line, or that
line's tail after a weld split. No critical or major findings. Two minor fixes
applied.

## Tag alignment trace

- **p1 build:** every `p1+=` has a matching `p1last+=(0)`, both for the weld
  head in the inner loop and for the final `cur`. The tag goes on
  `p1[${#p1[@]}-1]` after the empty-array guard. That element is the last line
  read, or its final tail after a split.
- **Stray pass:** `n` is incremented before the element is used, so
  `p1last[n - 1]` is the element's own tag in both branches. `straylast` follows
  `stray` one for one, and the splice of `straylast` sits under the same
  `${#stray[@]} -gt 0` guard. A stray lies strictly before `last`, so it can
  never carry the tag. The splice only places untagged elements after the tagged
  bullet, which clears termination as intended.
- **Duplicate pass:** `drop` is keyed by the p2 index, and `p3`/`p3last` are
  appended together from the same `i`. The survivor is the first copy the pin
  lacks, or the first copy when the pin has them all. When the kept copy is the
  input's last line (the earlier copy is in the pin and gets dropped), the tag
  goes with it and the output stays unterminated. Probed: kept-last-copy.
- **p3 non-empty:** at least one bullet exists past the `first` guard, and
  deduplication keeps one line per group, so `p3last[last_i]` is always set
  under `set -u`.

## Edge inputs (probed with a direct `source` and `cmp` in a `$TMPDIR` scratch dir, mode 640)

All 14 cases matched byte for byte and kept mode 640:

| Case | Result |
|---|---|
| empty file | no write |
| single unterminated bullet | no write |
| no repair needed, unterminated | returns before writing |
| dropped duplicate, input ends in a blank line | stays terminated |
| dropped duplicate, unterminated whitespace-only last line | stays unterminated |
| later copy kept because the pin holds the earlier one | stays unterminated |
| CRLF lines, unterminated `\r` last line survives | stays unterminated |
| CRLF lines, last line dropped | new last line keeps `\r\n` |
| weld tail dropped as a duplicate | head is written with `\n` |
| weld tail kept | tail stays unterminated |
| stray moved to the end (slice 2's shape) | bullet `\n`, stray `\n` |
| stray moved with an unterminated trailer after the region | trailer stays unterminated |
| weld split and stray move together | bullet `\n`, stray `\n` |
| stray kept in place after a dropped duplicate | stray `\n` |

Byte handling is intact. `IFS= read -r … || [ -n "$line" ]` is unchanged. The
mode still comes from `cp -p` onto the scratch file. The no-repair path returns
before `mktemp`.

## Fixes applied

1. **Minor, bash 3.2 hardening.** `p1last[${#p1[@]} - 1]=1` became
   `p1last[${#p1[@]}-1]=1`. An assignment subscript that contains spaces depends
   on how the parser recognises assignment words, and no bash 3.2 binary is
   available here to confirm older versions accept it. The spaceless form works
   on every version. Nothing else in `scripts/` uses a spaced subscript in an
   assignment. Read expansions such as `${p1last[n - 1]}` are inside `${}` and
   are safe as they are. This change is hardening, not a reproduced defect.
2. **Minor, comment accuracy.** The comment above the termination check said the
   new last element "gains the newline it never had a chance to lose". A weld
   head whose tail is dropped never had a newline in the input, so it gains one;
   every other new last element already had one. The comment now reads "…can
   retire that element or put another after it; either way the element that ends
   up last is written with a newline."

The M8 wording is exactly "a defect no take can adopt past". The comments use
the present tense and cite no plan, slice or line number.

## Not fixed / design calls

None. No test added, because neither fix changes behaviour. Slice 2's case
(moved stray at the end) was probed and already passes against this
implementation.

## Verification

- `shellcheck scripts/lib/index-compose.sh`: clean.
- `scripts/run-bats.sh tests/index_compose.bats`: 82 passed, 0 failed.
- Probe script re-run after the fixes: 14/14 ok.

## Files changed

- `scripts/lib/index-compose.sh` (uncommitted)
