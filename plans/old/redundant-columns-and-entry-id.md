# Plan: sharpen the repo's stance on redundant columns

## Context

Two places in the repo argue for carrying redundant data in the CSVs:

- [SPEC.md's Example table](../../SPEC.md#example-table) keeps `example_source` **and** `note_reference_<lang>` as separate columns, even though FLEx's exporter writes the same "Reference" field twice, and cites [Data handling](../../SPEC.md#data-handling)'s `Plural_seh`/`Plural_en` case as precedent.
- [remaining-lift-fields.md](../remaining-lift-fields.md)'s A2 recommends storing `entry/@id` verbatim even though it is fully derivable, citing the `@source` case as precedent.

That stance was questioned: is carrying redundant columns actually a good idea? Re-examining it found that the word covers three unrelated situations, and that the `@id` question turned on whether FLEx treats `@id` as authoritative on import — which **the [Technical Notes on LIFT used in FLEx](https://downloads.languagetechnology.org/fieldworks/Documentation/Technical%20Notes%20on%20LIFT%20used%20in%20FLEx.pdf) answers directly** (already cited under [SPEC.md's LIFT model references](../../SPEC.md#lift-model-references)). This plan records the sharpened reasoning and the changes that follow.

Section numbers below (§1, §2, §3) refer to that PDF, not to any file in this repo.

## What the FLEx documentation settles

From "Id, Guid" (§3), verbatim:

> Entries and senses require id fields. There is an exception where the entry id is not needed if you have a guid attribute instead. **Id fields can have any text as long as it is unique in the LIFT file.** […] **Any non-guid id will be converted to a guid during import.** The WeSay entry id used the lexeme form and a guid as the ID, FLEx continued that tradition.
> […] Entries also have a guid attribute which is used in FLEx as the primary ID.
> The sense id has always been a guid
> References to entries and senses within the LIFT file use the id string.

And from the entry-attribute list: "**id**: unique id used for referencing entries in the LIFT file. It *normally* consists of the lexeme form and guid for the entry."

Consequences:

- **`entry/@id` is an opaque within-file handle, not data.** Its only stated requirement is uniqueness in the file; FLEx converts it to a guid on import. The headword+guid shape is a WeSay convention FLEx inherited ("normally"), not a rule FLEx validates.
- **The update-anomaly objection largely dissolves.** A stored `@id` that no longer matches its edited headword is not *wrong* — nothing downstream compares the two. The case against storing it was weaker than it looked.
- **Synthesizing is clearly the worst option**, not merely a tie-break loser: it regenerates a string whose content the consumer discards, and it builds the LT-21075 exposure below in by construction.
- **A2 really is a prerequisite for C3**, and the rule is uniform rather than per-level. The per-relation subsections say refs carry "the guid (for sense) or id (for entry)", but §3 states the general rule — "References to entries and senses within the LIFT file use **the id string**" — and separately that "the sense id has always been a guid". So both levels do the same thing: a ref is the target's `@id` value; at sense level that value simply *is* a guid (verified: 1717/1717). An entry therefore needs an `@id` for a ref to point at, which is why C3 cannot ship without A2. There is no residual question about whether FLEx would accept a bare guid as an entry ref: under the design below, csv2lift always emits a ref equal to the target's actual `@id`, so the case never arises.
- Two doc caveats worth capturing: the entry-attribute list says "All of these attributes are optional except the id", contradicting §3's "not needed if you have a guid" — the repo follows §3, which matches observed FLEx behaviour. And **LT-21075**: FLEx "will get error messages when finding main entries if the entry id contains most Unicode characters, such as U+0331 diacritic. In some cases this causes the import to simply hang." Re-verified against `Sena3.lift`: 5 of 1462 ids carry precomposed `á`/`ú`, **0** carry combining marks, and none of the 31 relation refs are non-ASCII — so it is inherited-not-created risk, and nobody should "fix" it by rewriting ids.

Other measurements, re-derived against `tests/testthat/fixtures/lift2csv_entry-table/Sena3.lift`:

- `@id` = headword + (`@order` or `""`) + `"_"` + `@guid` on **1462/1462**; all 1462 ids unique. Citation and lexical-unit each carry exactly one `<form>`, always `lang="seh"` — so the "needs a writing-system choice" cost of synthesizing is latent, not exercised.
- `example/@source` vs `note[@type="reference"]`: 744 have both, **0** mismatch, **0** one-sided.
- All **31** `entry/relation/@ref` resolve as `@id`, none as `@guid`, all 31 carry the target guid as the after-last-underscore suffix — so guid⇄`@id` translation is lossless both ways.
- All **1717** `sense/@id` are guid-shaped and unique, confirming the doc's "the sense id has always been a guid" and validating the existing `sense_guid` column name.

## The three cases are not the same thing

1. **`Plural_seh` / `Plural_en` — not redundancy at all.** Two cells hold *different* values; the rule is "don't normalise variation the source makes". Citing it as precedent for the other two is a category error and should stop.
2. **`example_source` / `note_reference_<lang>` — redundancy that exists in the source file.** The tool mirrors FLEx rather than inventing duplication, and collapsing would require inventing a `lang` on write. Keeping both is right; the defect is that a user desyncing them is *silent*.
3. **`entry/@id` — a derived value, now settled as an opaque handle.** Store it. Not because "it's the only option where refs resolve" (guid-keyed refs remove that argument), but because there is no semantic content to keep in sync and nothing worth regenerating.

## The same doc also settles D2 (`<header>` passthrough)

[remaining-lift-fields.md](../remaining-lift-fields.md)'s D2 proposed a `--header-from` flag copying `<header>` verbatim, with decision 4 asking "does FLEx need `<header>` to import?" Answered, and the answer splits the element in two:

> §2 Header: **The header element is optional in a LIFT file.** It provides a place to define fields that are not built into the basic LIFT structure.

The doc's own minimal importable file (§1) has no `<header>` at all — just `<lift version="0.13"><entry id="e1">…`. So the flag is never needed for import to *succeed*. But the two halves differ in what they cost to drop:

- **`<ranges>` is genuinely droppable.** "On import into FLEx, any references to range elements in senses and entries will try to find an existing item in the FLEx list. If not found, a new item will be added to the FLEx list, and the Import Log file will list the fact." Nothing is lost but log noise. Copying it verbatim is arguably *worse* than dropping it: the 27 `href`s in `Sena3.lift` are absolute paths to one machine's `.lift-ranges` file (`file://C:/Users/zook/Desktop/…` in the doc's own example).
- **`<fields>` matters, but only for custom-field typing.** "The fields element is not used during import, **except for FLEx custom fields**. Without a field definition for a custom field, the import will create a custom field in the target project, but it defaults to a MultiUnicode field with `kwsAnalVerns` as the selector. With a field element for the custom field, it will add missing custom fields with the desired types." The payload is the `qaa-x-spec` pseudo-writing-system carrying `Class=`/`Type=`/`WsSelector=`. So dropping `<fields>` keeps all *data* and degrades the *schema* — Sena3's 11 declarations would import as MultiUnicode/`kwsAnalVerns` regardless of what they were.

So D2 narrows from "pass the header through verbatim" to "**pass `<fields>` through; drop `<ranges>`**", and it only earns its keep if importing into a *fresh* project is a goal. That second half of decision 4 — is import-into-FLEx a goal for this tool at all? — the PDF cannot answer, and it is the only thing still gating D2.

## The option A2 never listed

A2 weighs store-vs-synthesize *assuming* C3 copies `relation_ref` verbatim as the `@id` string. That assumption is the worst redundancy in the set — cross-table, embedding another row's headword and guid in a text field, while every other FK in the repo is a guid ([SPEC.md's Structural rules](../../SPEC.md#structural-rules-csv2lift-direction)).

**Key `relation_ref` on the target's guid** and translate to the target's stored `entry_lift_id` on write. Then refs use the CSV's one key discipline, csv2lift owns internal consistency regardless of user edits, the doc's entry-uses-id/sense-uses-guid asymmetry is hidden where it belongs, and `entry_lift_id` stops being idle — it becomes the stored guid→`@id` mapping the write pass needs.

## Changes

**1. `SPEC.md`, [Data handling](../../SPEC.md#data-handling) — add a "Redundant columns" bullet** stating the three-way distinction: preserve variation (not redundancy); mirror source-level duplication without reconciling it, but warn when it disagrees; and decide a *derived* column on what the consumer does with the value, citing the "any text as long as it is unique" / "converted to a guid during import" quotes. Correct the `Plural` citation in [Example table](../../SPEC.md#example-table) to point here instead.

**2. Warn when redundant columns disagree** (`R/csv2lift_example.R`, using the classifier in `R/example_helpers.R`): on write, if `example_source` and any `note_reference_<lang>` are both non-blank and unequal, warn on stderr naming the sense — same shape as `extract_example_translation()`'s existing duplicate-translation warning (`R/example_helpers.R`). Both values still emit unchanged. TDD per [AGENTS.md's Testing Approach](../../AGENTS.md#testing-approach): red first via a hand-edited `_examples.csv` fixture with the two cells disagreeing.

**3. Amend [remaining-lift-fields.md](../remaining-lift-fields.md)** — done in the same change as this plan file:
- A2: replace the cost table's reasoning with the doc findings — recommendation stays "store verbatim", now settled rather than argued. Drop the proposed guid-suffix consistency check (the suffix is a convention the doc calls "normal", not a rule) and replace it with a **uniqueness check** across `entry_lift_id`, which *is* a documented requirement and is what a ref needs to resolve unambiguously. Remove the "is `@id` authoritative?" open question — answered.
- A2/C3: record that the doc makes A2 a hard prerequisite for C3 — a ref is the target's `@id` string at both levels, so an entry needs an `@id` to point at.
- C3: change `relation_ref` to hold the target guid, note the write-time translation via `entry_lift_id`, record the 31/31 lossless measurement, and add the doc's warning that "the import process will try to unify the relation sets" for Collection-type relations.
- D2 and decision 4: narrow to `<fields>`-only passthrough per the section above.
- Decisions to settle: item 1's store-vs-derive-vs-skip half is now settled by the documentation rather than pending a judgement call — only the column-name choice (`entry_lift_id` suggested) is still open.

**4. `SPEC.md`, [Not yet specified](../../SPEC.md#not-yet-specified) — add the LT-21075 note** so the inherited non-ASCII-id import hazard is recorded rather than rediscovered, with the 5-of-1462 / 0-combining-marks figures and an explicit "do not rewrite ids to work around this".

No A2/C3/D2 implementation here — Phase A is still unstarted.

## Side findings (recorded, not in scope)

Two things surfaced while reading the doc that are worth a note somewhere but are *not* part of this change:

- **Embedded newlines in a text node are untested in the write direction.** The doc says "Any actual CR/LF in the middle of a string will be converted to a LINE SEPARATOR on import" (FLEx's Shift+Enter, U+2028). `Sena3.lift` has exactly **1** such text node of 9742, on entry `1ba747b1-…` (`subenza`). It appears in the read-direction snapshots (`_snaps/sense-table_end-to-end/Sena3.csv`, `_snaps/join-sense-entry-table_end-to-end/Sena3.csv`) but in **no** `csv2lift` fixture or snapshot — so no test covers a CSV cell containing a literal newline surviving back into LIFT. `readr` should quote and re-read it correctly, which is exactly why it deserves one cheap fixture rather than an assumption.
- **The doc confirms the span-drop behaviour [SPEC.md's Data handling](../../SPEC.md#data-handling) already documents** as a limitation: "If a LIFT file has embedding in a Unicode field, on import into FLEx, the text will be kept, but all span hierarchy will be lost including styles, writing systems, etc." That is FLEx's loss on import, not this tool's on round-trip — worth a pointer from the inline-span bullet so the two are not confused.

## Verification

- `Rscript -e 'devtools::test(filter = "csv2lift_end-to-end")'` — the new disagreement fixture warns; review the `.lift` diff and confirm both values still emit unchanged.
- `Rscript -e 'devtools::test()'` green with no existing snapshot moving, since no fixture currently has the two columns disagreeing (0 of 744).
- `grep -n "Plural_seh" SPEC.md` — confirm the Example table no longer cites it as the redundancy precedent.
