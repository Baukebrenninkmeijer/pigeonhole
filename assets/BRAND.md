# pigeonhole brand

## Palette

| Swatch | Hex | Name | Role |
|---|---|---|---|
| ██ | `#1f1b16` | walnut | Ink / dark-mode ground. The cabinet the slots are cut into. |
| ██ | `#f2e9d8` | parchment | Paper / light-mode ink. The open cubby, and the note in it. |
| ██ | `#d9642c` | stamp | The single accent — marks the one thing that's state, not structure: mail waiting. |

Two neutrals plus one accent, on purpose: the tool has exactly one piece of dynamic
information (do you have mail), so the palette shouldn't offer a second thing to look
at. No blue, no gradient — nothing that reads as "software" rather than "cabinet."

## Type

System monospace stack (`ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`)
for wordmark and tagline. pigeonhole is a shell script and a folder of files; the type
should look like it came out of a terminal, not a deck. This is **live text**, not
path outlines — a known tradeoff: glyphs vary slightly by OS font substitution, but
there's zero embedded-font risk and the SVG stays legible as plain text if opened raw.

## The mark

A 3×3 grid of open cubbies, no fill implying depth or shine — that grid *is* the
architecture: one directory per agent, sitting flat in a shared store, nobody
notified. One cubby carries a small tab over its top edge, the only asymmetry in the
mark: a note someone left, sitting there until you come get it. That's pull delivery,
drawn. No envelope (says email), no bird (says carrier pigeon), no bell (says push).

## Don't

- Don't fill all nine cubbies or make the grid uneven — one occupied slot against
  eight empty ones is the point.
- Don't add a gradient, drop shadow, or glossy highlight to the cubbies.
- Don't recolor the accent to blue/purple, or use it on more than one slot.
- Don't swap the mark for a literal envelope, pigeon, or bell — those mean push,
  which is the opposite of this tool.
- Don't set the wordmark in a non-monospace or decorative typeface.
