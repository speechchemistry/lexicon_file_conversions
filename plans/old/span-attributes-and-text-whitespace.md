# Span attributes and whitespace inside `<text>` (issue #6)

## Problem

Two bugs, both from issue #6, both seen in a real Zhire round trip into FLEx:

- **`lang="NA"`.** `multitext_value()` (`R/entry_helpers.R`) always rebuilds a span as `<span lang="%s">`. FLEx exports spans with no `lang` — a hyperlink (`href` + `class="Hyperlink"`) and a character style (`class="Default Paragraph Characters"`) — so the cell gets `lang="NA"` and loses `href`/`class`. FLEx then adds a "Nauru (na)" writing system on import.
- **Whitespace inside `<text>`.** `csv2lift.R` writes with libxml2's pretty-printer, which indents the children of any element that has no text-node child. A `<text>` that holds only a span is therefore written across three lines, and FLEx imports that indentation as data (exported back as `U+2028` plus spaces). Existing approved snapshots (e.g. `sena3-inline-span-markup.lift`) already contain this shape.

## Decisions (agreed with the user)

- **CSV cell:** a span keeps exactly the attributes it had in the LIFT, in source order: `<span class="Default Paragraph Characters">283</span>`, `<span href="…" class="Hyperlink">paws pag 1.1</span>`. No `lang` is added when there wasn't one. Spans that have a `lang` are unchanged, so existing CSVs don't change.
- **Output layout:** everything stays indented as now except a `<text>` element's content, which is always written on one line: `<text><span …>…</span></text>`.
- Attribute values containing `"` are not supported (none in real data); this is recorded in SPEC.md's [Not Yet Specified](../../SPEC.md#not-yet-specified) list rather than designed for.

## Fixture

`zhi-span-without-lang.lift`: two real entries from `zhi-flex_lift_2026-10-13.lift` (the export from *before* the damaging round trip — the later `-1607` export already has the whitespace in pər), extracted with `scripts/copy-lift-entries.R`:

- kpiob — a `class` span in the middle of a sense `note[source]`.
- gbɛr — a hyperlink span that is the whole of an example `note[reference]`, so it also exercises the whitespace bug.

Placed in `lift2csv_entry-table/`, `lift2csv_sense-table/`, `lift2csv_example-table/`; their CSV output becomes `fixtures/csv2lift/zhi-span-without-lang/`.

## TDD

1. **Red (read):** hand-edit the auto-created sense/example CSV snapshots to the agreed cell form; the tests fail on `lang="NA"`.
2. **Red (write):** hand-write `_snaps/csv2lift/zhi-span-without-lang.lift` with the original spans, each `<text>` on one line. Hand-fix the existing snapshots that have the three-line `<text>` shape. Add unit cases to `test-multitext-span-markup.R` for a `class` span and a hyperlink span.
3. **Green (read):** `multitext_value()` builds the tag from `xml_attrs(child)`.
4. **Green (write):** widen `SPAN_MARKUP_PATTERN` to any number of `name="value"` attributes (or none) and re-emit them as captured, escaping `&`/`<` in values. When a `<text>` contains a span, give it an empty text-node child first: libxml2 does not indent the children of an element that has a text-node child, and an empty one serialises to nothing.
5. **SPEC.md:** update the Data Handling span bullet and the Not Yet Specified span bullet.
