# Artefact inspection report

Run `tidybrreg-stresstest-bdzqm`, image v5, published to
`gs://sondre_brreg_data/raw/tidybrreg_stresstest/run_date=2026-08-05T125928Z/`.

Every file the run wrote is inspected below and compared against (a) what
`EVALUATION.md` predicted the call would produce, and (b) what the installed roxygen
documentation says. 31 files, 1.41 GB.

---

## 1. Download cache — ETag sidecars

`tmp/cache/R/tidybrreg/*.etag` — five files, 33 bytes each.

| file | content |
|---|---|
| `enheter_bulk.csv.etag` | `2a2531b3371367793dc3043c5a45d9b0` |
| `enheter_bulk.json.etag` | `16445e6cd529f921e58e71d95f37a7f1` |
| `roller_bulk.json.etag` | `bb2e042db656be1ab46ed66c24bfa1c1` |
| `underenheter_bulk.csv.etag` | `9bbc67fcccfee3a863ac43f0e0d03d04` |
| `underenheter_bulk.json.etag` | `74d3ee23fb4787e16146cafc51ea0169` |

**Expected (EVALUATION #89–95):** `brreg_download()` writes an etag sidecar used by
`refresh = "auto"` to decide whether to re-fetch.

**Observed:** all five are bare 32-hex strings with a trailing newline, unquoted and with
no `W/` weak-validator prefix. That matches what the server sends and what the comparison
expects, so the mechanism is coherent. Note this file is written *unconditionally* — it is
present for `underenheter_bulk.json` even though nothing in this run requested a JSON
underenheter download through the caching path, which is consistent with D-24 (`cache =
FALSE` does not suppress cache writes).

**Verdict:** as documented. No new finding.

---

## 2. `snapshot-store/manifest.json` — 2,226 bytes, 3 entries

**Expected (EVALUATION #182–184, #209–211):** one entry per download, unique `id`, resolvable
paths, and per the roxygen "timestamps, HTTP headers, file hashes, and CDC bridge metadata".

**Observed — five findings in one file:**

1. **D-55 confirmed.** Two of the three entries carry the identical `id`
   `underenheter_2026-08-04`. `id` is evidently `{type}_{snapshot_date}`, so a forced
   re-snapshot of the same date cannot produce a unique key.
2. **D-103 confirmed.** All three entries share one `etag`
   (`9bbc67fcccfee3a863ac43f0e0d03d04`), one `file_hash`
   (`6b889ffdb760788804b807532bd6ae72`), one `last_modified`, and one `record_count`
   (854,499) — but are filed under `snapshot_date` 2026-08-05 *and* 2026-08-04. The
   register was downloaded once and stored as two different days.
3. **D-58 confirmed.** Both 2026-08-04 entries point at
   `.../snapshot_date=2026-08-04/data.parquet` and `.../raw/underenheter_bulk.csv.gz`.
   Neither exists — the artefact inventory contains only `snapshot_date=2026-08-05`.
   `brreg_cleanup()` removed the partitions and left the manifest rows behind.
4. **D-102 confirmed.** Every entry has `"cdc_bridge_first_update_id": {}`. The field the
   documentation calls "CDC bridge metadata" is serialised as an empty object in all three.
5. **D-56 confirmed.** `brreg_import()` wrote
   `roller/snapshot_date=2024-01-01/data.parquet` (120 MB, present in the inventory) but
   there is **no manifest entry for it at all**. Only the three `brreg_snapshot()` CSV
   downloads are recorded. Provenance is silently absent for imported data.

**New finding — D-106: the manifest mixes two incompatible time encodings.**
Within a single record, `download_timestamp` is ISO-8601 UTC
(`"2026-08-05T15:04:31Z"`) while `last_modified` is a locale-formatted Java-style string
with a named zone (`"Wed Aug 05 04:30:57 CEST 2026"`). The latter is passed through from
the HTTP header verbatim. `as.POSIXct()` cannot parse it without an explicit format *and* a
matching locale, and "CEST" is not resolvable via `OlsonNames()`, so any consumer trying to
order snapshots by server modification time has to special-case it. `brreg_manifest()`'s
documentation describes the column only as "HTTP headers", so this is under-specified
rather than contradicted — but it makes the field effectively unusable as a timestamp.

---
## 3. `snapshot-store/roller/snapshot_date=2024-01-01/data.parquet` — 120,697,617 bytes

Written by `brreg_import(path_to_roller_json, "2024-01-01", type = "roller")` (check
`IM-07`).

**Expected (EVALUATION #193):** either a parsed roller table or a refusal. The evaluation
predicted `match.arg` would accept `"roller"` while the body always calls
`parse_bulk_csv()`, producing garbage.

**Observed — worse than predicted:**

```
rows: 116,018,041   cols: 1
column names: "["
```

The single column is literally named `[`. Its values are the raw JSON text of the roller
bulk, one line per row:

```
 1 | {
 2 | _links : {
 3 | self : {
 4 | href : https://data.brreg.no/enhetsregisteret/api/enheter/810034882/roller
 5 | },
 6 | enhet : {
 7 | href : https://data.brreg.no/enhetsregisteret/api/enheter/810034882
 8 | }
 9 | },
10 | organisasjonsnummer : 810034882,
11 | rollegrupper : [ {
12 | roller : [ {
```

The CSV reader treated the opening `[` of the JSON array as a header row and every
subsequent line as a single-field record. Commas inside the JSON were consumed as
delimiters, which is why quoting has been stripped from the values. 116 million rows,
116 MB on disk, zero recoverable structure.

**The store does not quarantine it.** It is fully integrated into the public API:

```
brreg_snapshots("roller")
  snapshot_date  file_size    path
  2024-01-01     120697617    .../roller/snapshot_date=2024-01-01/data.parquet

brreg_open("roller")   ->   opened, cols: [ , snapshot_date
```

So `brreg_panel(type = "roller")` or `brreg_series(type = "roller")` over this store would
silently consume 116 M rows of JSON fragments as if they were register records.

**Documentation contradicts itself on this exact point.** `?brreg_import` shows

- *Usage:* `type = c("enheter", "underenheter", "roller")` — so `match.arg()` accepts
  `"roller"`;
- *Arguments:* `type: One of "enheter" or "underenheter"` — which excludes it;
- *Description:* "Read a brreg bulk **CSV** file … and save as a dated Parquet partition".

The signature admits a value the prose forbids and the description cannot honour. D-57 is
therefore both an implementation defect and a documentation defect: no reading of the help
page tells a user that passing the documented-in-Usage value silently produces a
116-million-row artefact.

**Also confirms D-56 from the other direction:** this 120 MB partition has no manifest
entry, so nothing in the provenance record would ever reveal how it got there.

---
## 4. `snapshot-store/underenheter/snapshot_date=2026-08-05/data.parquet` — 56.6 MB

Written by `brreg_snapshot("underenheter")`.

**Expected (EVALUATION #182, #190):** a dated parquet partition, dictionary-mapped column
names, ~824 K rows.

**Observed:** 854,499 rows x 44 columns. Schema is clean and correctly typed —
`date32[day]` for all ten date fields, `int32` for `employees`, `bool` for
`employees_reported` / `vat_registered`, `string` elsewhere. Every column name is a
`field_dict` name; no raw Norwegian API names survive.

Content integrity checks all pass:

- every `org_nr` passes mod-11 (854,499/854,499)
- zero duplicate `org_nr`
- `registration_date` spans 1995-02-20 to 2026-08-04 — plausible, and the upper bound is
  the day before the snapshot, as it should be
- sample rows carry sensible Norwegian establishments with valid `parent_org_nr`

**D-26 is improved but not fully resolved.** The evaluation predicted ~40 all-NA
enheter-only columns stamped onto underenheter rows. That is gone — 44 columns, not 104.
But five columns are still **100 % NA across all 854,499 rows**:
`voluntary_vat_descriptions`, `voluntary_vat_reg_date`, `vat_registration_date`,
`vat_reg_date_er`, `closure_date`. So `c9bd992` scoped emission to columns *present in the
source header* rather than columns that *carry any value*. For underenheter the VAT block
exists in the CSV schema but is never populated. That is defensible under a naive-empiricism
reading (the source declares the field), but it means "the column exists" still cannot be
read as "the register has this attribute for this entity type".

---

## 5. Sync state — small files, and a cross-validation of the two bootstrap paths

### `sync-store/state/roller.parquet` — 2,757 bytes
**0 rows x 17 columns**, full roller schema present. This is exactly what EVALUATION #142
predicted for `roller_method = "cdc"`: an empty typed state written without the 131 MB
totalbestand download. Correct, and the typed-empty is good practice.

Worth noting: check `SY-46` ("roller cdc sync produces roller changelog rows") passed while
this state is empty and no changelog exists at all — the check only asserts
`is.data.frame()`, so it is too weak to mean anything. That is a rig weakness, logged.

### `sync-csv-store/state/historiske_navn.parquet` — 924 bytes, **0 rows x 5 columns**
versus `sync-store/state/historiske_navn.parquet` at **25 MB**.

This is the documented CSV/JSON divergence made concrete: the CSV bulk carries no
`historiskeNavn`, so a CSV bootstrap starts with an empty name history and only accrues
rows as renames arrive over CDC, while a JSON bootstrap backfills 25 MB of history
immediately. Matches the roxygen. Not a defect — but a strong argument that
`format = "json"` should be the default rather than `"csv"`.

### Påtegninger: the expensive path buys nothing

| | rows | distinct orgs |
|---|---|---|
| JSON bootstrap (inline, no extra requests) | 2,754 | 2,747 |
| CSV bootstrap (one API call per flagged entity — D-35) | 2,753 | 2,746 |

Set difference: **1 row** (a single `FADR` entry present in the JSON run, absent in the CSV
run nine minutes later — almost certainly genuine register drift between 15:14 and 15:23,
not a parsing difference). Infotype distributions are otherwise identical across all twelve
codes (`FADR` 974 vs 973, everything else exact).

This is the most useful comparison in the whole inspection: **D-35's per-entity request
storm produces the same påtegninger the JSON path gets for free**, and additionally loses
the entire name history. The cost is not buying fidelity.

Both stores agree on schema (`org_nr`, `position`, `infotype`, `tekst`, `innfoert_dato`),
text is correctly UTF-8 encoded Norwegian, and `innfoert_dato` spans 2005-01-26 to
2026-08-04.

---
## 6. `sync-store/state/enheter.parquet` (171 MB) vs `sync-csv-store/state/enheter.parquet` (156 MB)

**Expected (EVALUATION #134–137):** a full-register state table written by the bootstrap,
identical in population regardless of source format.

**Observed:** both hold exactly **1,170,637 rows** — population agreement is exact, which
is the important result. Schemas differ by two columns, both present only in the JSON
state:

### `response_class` — a constant, and evidence for D-91
Every one of the 1,170,637 rows carries `response_class = "Enhet"`. This is BRREG's
`respons_klasse` type discriminator passed through into state. It carries zero information
in a bulk download (nothing deleted appears in the current register), so it is a wasted
column — but its presence is direct evidence for **D-91**: the API really does use
`respons_klasse` as the entity/deleted discriminator, tidybrreg really does carry it
through the bulk path, and `brreg_entity()` still ignores it on the single-entity path
where it actually matters (`"SlettetEnhet"`).

### `historiske_navn` — the same data stored twice, once untyped
18.74 % of rows (219,397) carry a `historiske_navn` value, and that value is **unparsed
JSON text** inside an otherwise fully typed table:

```
[{"navn":"AKSJESELSKAPET AGDERPOSTEN","fraDato":"1995-03-12 12:27:00","tilDato":"2006-01-07 14:34:39"},...]
```

The same information is *also* written, properly parsed, to
`sync-store/state/historiske_navn.parquet` (635,234 rows x 5 columns). Verified: the
219,397 blob-carrying orgs are a strict subset of the dedicated table's orgs. The dedicated
table additionally covers 346,918 orgs absent from the enheter state — those are
underenheter, so one shared name-history table spans both registries while the JSON blob
column duplicates only the enheter slice.

So a JSON bootstrap persists name history twice: once tidy, once as JSON strings glued into
the entity table. The blob column is redundant, inflates the state file, and reintroduces
exactly the nested structure the parse layer exists to remove.

### `historiske_navn.parquet` quality
Structurally sound: no duplicate `(org_nr, position)` pairs, `position` is 0-based and runs
to 27, `to_date` is never NA. But **`from_date` and `to_date` are `character`**, holding
`"1995-02-19 16:52:00"` — not `Date`, not `POSIXct`, and with no timezone. This matches
`brreg_historical_names()`'s documentation, which does say the dates are returned as
character, so it is documented rather than surprising; it is still the only state table in
the store whose temporal columns are untyped, and it makes the naive-local-time problem
(D-33) permanent in the persisted artefact rather than merely transient.

---

## 7. What the sync stores do *not* contain

Neither `sync-store/state/` nor `sync-csv-store/state/` contains a `changelog/` directory —
not empty, absent — despite both cursors recording real progress:

```
sync-store      enheter_id 25017143  underenheter_id 21207519  roller_id 4577230
sync-csv-store  enheter_id 25017181  underenheter_id 0         roller_id 0
```

This is **D-105**, and the artefacts sharpen it: the CSV store's zero cursors for
underenheter and roller confirm that store only ever synced enheter (it was the budget
probe), while the JSON store advanced all three. Both wrote state, neither wrote a
changelog. `brreg_flows()` consequently aborts on both.

The cursors also show `last_sync` as `"2026-08-05T15:14:27"` — ISO-shaped but with **no
timezone designator**, unlike `manifest.json`'s `download_timestamp` which correctly carries
`Z`. Two persistence formats written by the same package disagree on whether timestamps are
zoned. Another instance of D-33 reaching disk.

---
## 8. `sync-store/state/underenheter.parquet` (70 MB) — and a schema split within one package

854,499 rows x 43 columns. Integrity is clean: every `org_nr` valid mod-11, zero duplicates,
zero NA `parent_org_nr`, `registration_date` spanning 1995-02-20 to 2026-08-04. Row count
matches the snapshot store's underenheter partition exactly (854,499), so both paths agree
on population.

`response_class` is the constant `"Underenhet"` for all 854,499 rows — the same
zero-information discriminator column seen in the enheter state, correctly reflecting the
other side of BRREG's type marker.

**New finding — D-107: the same registry persisted by two different functions on the same
day yields non-unionable schemas.**

| | columns | |
|---|---|---|
| `brreg_snapshot("underenheter")` (CSV path) | 44 | |
| `brreg_sync(format = "json")` | 43 | |
| shared | **41** | |

Only in the snapshot/CSV path: `voluntary_vat_descriptions`, `voluntary_vat_reg_date`,
`closure_date`.
Only in the sync/JSON path: `historiske_navn`, `response_class`.

So `closure_date` — a genuine lifecycle field, and one of the exit dates
`brreg_survival_data()` looks for — **exists in the snapshot store and is absent from the
sync state**, while the sync state carries two fields the snapshot store lacks. Neither is
a superset. A consumer who stitches the two stores together (exactly what the snapshot +
CDC design invites) gets a ragged table whose column set depends on which function last
wrote, and any panel spanning both silently loses `closure_date` for the sync-covered
period.

This is not the batch-scoping behaviour of `c9bd992` doing its job: these are format
divergences (CSV bulk carries the VAT/closure block, JSON bulk carries history and the
response discriminator) propagated straight into persisted state with no reconciliation and
no note in the documentation. `?brreg_sync` and `?brreg_snapshot` both describe their output
simply as the register, with no indication the column sets differ.

---
## 9. Raw bulk payloads — and a correction to D-90

### Field counts reconcile exactly with the parsed output

| bulk | header fields | parsed parquet columns |
|---|---|---|
| `underenheter_bulk.csv.gz` (60.7 MB) | 44 | 44 (`brreg_snapshot`) |
| `enheter_bulk.csv.gz` (154 MB) | 90 | 90 (shared-store enheter) |

One column out per field in, nothing fabricated and nothing dropped. This is the clean
confirmation that `c9bd992` fixed D-26 at the CSV path: the five all-NA columns noted in
section 4 (`closure_date`, the VAT block) are present *in the source header* and simply
empty for every underenhet, so emitting them is faithful to the source rather than
invented.

### D-90 must be downgraded — the collision is a deliberate alias, not data loss

`field_dict` maps two `api_path` values onto `registration_date`
(`registreringsdatoEnhetsregisteret`, `registreringsdatoIEnhetsregisteret`) and two onto
`employee_reg_date_nav` (`...NavAaregisteret`, `...NAVAaregisteret`). I originally
registered this as an S1 silent last-row-wins overwrite. Inspecting the actual headers
settles it:

```
enheter_bulk.csv       field 38: "registreringsdatoenhetsregisteret"
underenheter_bulk.csv  field 35: "registreringsdatoIEnhetsregisteret"

both bulks             field 16: "registreringsdatoantallansatteNAVAaregisteret"
```

The two registration-date spellings are **mutually exclusive by registry** — BRREG spells
the field differently in the enheter and underenheter exports, and the dictionary carries
both so one `col_name` covers both files. No payload ever contains both, so the overwrite
never fires. The NAV pair are pure case-variants of a single real field, and since matching
is case-insensitive (`P-31`) both dictionary rows resolve to the same actual column and the
same `col_name` — the "overwrite" picks between two identical outcomes.

**Corrected verdict on D-90:** the mechanism I demonstrated in `P-03b` is real (constructing
a synthetic payload with both paths populated does silently discard one), but it is
unreachable with real BRREG data, and the duplicate rows exist precisely to normalise a
registry-specific spelling difference. Downgraded from **S1 to cosmetic**: worth a comment
in `field_dict` explaining the aliasing, not a defect to fix. My original inference —
"a live payload carrying both keys would silently lose one" — was explicitly marked
*inferred* at the time and is now disproven by observation.

Also visible in the enheter header and worth noting for anyone mapping the register: BRREG's
own casing is inconsistent within a single file (`registreringsdatoenhetsregisteret` all
lowercase at field 38, `registreringsdatoAntallAnsatteEnhetsregisteret` camelCase at field
15, `registreringsdatoantallansatteNAVAaregisteret` mixed at field 16). tidybrreg's
case-insensitive matching is the right design choice against a source like that.

---
## 10. `cache/R/tidybrreg/roller_bulk.json.gz` — 124 MB

**Structure:** a pretty-printed JSON *array*, not NDJSON:

```
[
  {
  "_links" : { "self" : { "href" : ".../enheter/810034882/roller" }, ... },
  "organisasjonsnummer" : "810034882",
  "rollegrupper" : [ { "roller" : [ { "avregistrert" : false,
      "person" : { "erDoed" : false, "fodselsdato" : "1981-09-27",
                   "navn" : { "etternavn" : "Aarrestad", "fornavn" : "Morten" } },
      "rekkefolge" : 0,
      "type" : { "_links" : {...}, "beskrivelse" : "Daglig leder", ...
```

This single fact explains two separate defects mechanically:

- **D-57** — line 1 of the file is `[`, which `parse_bulk_csv()` reads as a one-field
  header. That is exactly why the imported parquet in section 3 has a column named `[`.
- **D-25 / arrow JSON path** — `arrow::read_json_arrow()` expects newline-delimited JSON.
  A pretty-printed array cannot be read by it at all, so the documented
  `type_output = "arrow"` route is unusable for every JSON bulk, not merely inconsistent.

### D-09 root cause confirmed: `fratraadt` no longer exists
**Zero occurrences** of `fratraadt` in the first 2,000,000 lines. The field BRREG removed in
June 2026 is genuinely gone from the payload. tidybrreg 0.5.0's "stop fabricating resigned"
change is therefore *correct* — it should not invent a column the source no longer provides.
What remains a defect is the consequence: `brreg_roles()`'s column set now depends on
payload content, so two calls against different entities (or the same entity before and
after the API change) return unstackable frames. The fix addressed the fabrication; the
schema-stability problem it created is untouched.

### D-13 conclusively confirmed against real data
`valgtAv` is populated 1,247 times per 2 M lines. Its distinct values:

| code | meaning | count |
|---|---|---|
| `A-AK` | Representative of the A shareholders | 3,761 |
| `AREP` | **Representative of the employees** | 581 |
| `B-AK` | Representative of the B shareholders | 30 |
| `C-AK` | Representative of the C shareholders | 7 |

`brreg_board_summary()` computes `n_employee_elected = sum(!is.na(elected_by))`, which
counts all four. Only `AREP` is employee election — **581 of 4,379 populated values, 13 %**.
The other 87 % are share-class representatives, the opposite constituency. Anyone using
`n_employee_elected` as an employee-representation measure gets a number that is roughly
7.5x too large and dominated by shareholder representatives. Previously graded S1 from code
reading; now quantified from the register itself.

### D-92 is pervasive, not incidental
13,640 `"_links"` occurrences in the first 200,000 lines — nested inside `type`, `person`,
and group objects, not only at the document root. The HAL-stripping logic only handles the
top level, so every one of these nested blocks is a candidate to leak into output as it does
for `organisasjonsform__links_self_href` in section 2 of the evaluation.

---
## 11. `cache/R/tidybrreg/enheter_bulk.json.gz` — 200 MB

First entity, verbatim:

```
[
  {
  "links" : [ ],
  "organisasjonsnummer" : "810034882",
  "navn" : "SANDNES ELEKTRISKE AS",
  "organisasjonsform" : { "links" : [ ], "kode" : "AS", "beskrivelse" : "Aksjeselskap" },
  "historiskeNavn" : [ { "navn" : "SANDNES ELEKTRISKE FORRETNING AS",
                         "fraDato" : "1995-02-19 16:52:00",
                         "tilDato" : "2024-02-15 12:54:30" } ],
  "postadresse" : { ..., "adresse" : [ "Postboks 32" ], ... },
```

**The bulk and single-entity endpoints spell HAL links differently.** In 200,000 lines of
this file there are 7,517 occurrences of `"links"` and **zero** of `"_links"`. The
single-entity endpoint (section 2 of EVALUATION, and the live payload inspected earlier)
uses `"_links"`. That asymmetry is the structural reason D-92 exists: `drop_hal_links()`
matches a `links$` suffix, which is right for the bulk shape; `rename_from_dict()` filters a
leading `_links`, which is right for the top level of the single-entity shape; and
`organisasjonsform._links.self.href` — nested, underscore-prefixed — matches neither. The
two guards each cover one endpoint's convention and the gap between them is exactly where
the leak occurs.

Also confirmed here:

- `respons_klasse` appears once per entity, value `"Enhet"` in all 57,565 sampled
  occurrences — the constant column seen in sync state originates faithfully from the source.
- `historiskeNavn` and `paategninger` are inline on every entity (`paategninger` is usually
  `[ ]`), which is why the JSON bootstrap gets both for free and the CSV bootstrap must pay
  per-entity requests for one and cannot get the other at all.
- `fraDato` / `tilDato` are `"1995-02-19 16:52:00"` — naive local timestamps at source, with
  no zone. tidybrreg preserving them as `character` (section 6) is arguably the honest
  choice; inventing a timezone would be worse.

---

## 12. `shared-store/` — the rig's own fixture series

Four enheter partitions, written by the test rig rather than by tidybrreg, used as
deterministic input for the panel/series/events checks:

| snapshot_date | rows | cols | distinct municipality codes |
|---|---|---|---|
| 2025-07-01 | 49,925 | 90 | 359 |
| 2026-01-17 | 49,950 | 90 | 360 |
| 2026-07-06 | 49,975 | 90 | 360 |
| 2026-08-05 | 50,000 | 90 | 360 |

Population grows by exactly 25 per step and the planted municipality/nace mutations are
present, which is what makes `EV-05`/`EV-06` (entries and exits equal the set differences)
and `EV-07` (planted changes detected) meaningful rather than vacuous. 90 columns matches
the enheter CSV header exactly, so the parse path reproduces the source field-for-field at
this grain too.

`snapshot-store/import-src.csv.gz` (60.7 MB) is likewise a rig artefact — my own test copies
the bulk there before calling `brreg_import()`. Worth noting it lands at the *root* of
`brreg_data_dir()`; it is not inside a type directory so `brreg_open()` does not trip on it,
but the test should place it in a scratch directory rather than in the store being tested.
Logged as a rig hygiene issue, not a package defect.

**Duplication ledger.** The checksum `8ebc97433bf7…` appears three times: the download cache
copy, `import-src.csv.gz`, and the raw copy inside the snapshot partition. Only the first is
tidybrreg's doing plus one from D-54; 60.7 MB of the duplication is mine.

---

## Summary of this inspection

Inspected 24 of 31 files across every store the run produced.

**Confirmed from artefacts (previously code-reading or inference):** D-09 root cause
(`fratraadt` absent from source), D-13 (quantified: only 13 % of `valgtAv` is employee
election), D-25 (arrow cannot read a pretty-printed JSON array at all), D-26 (fixed at the
CSV path — field counts reconcile exactly), D-54, D-55, D-56, D-57 (far worse than
predicted), D-58, D-91 (`respons_klasse` carried faithfully in bulk, ignored where it
varies), D-92 (structural cause identified), D-102, D-103, D-105.

**New this inspection:** D-106 (manifest mixes ISO-8601 and locale-formatted CEST
timestamps), D-107 (snapshot and sync write non-unionable schemas for the same registry;
`closure_date` present in one, absent in the other).

**Corrected against myself:** D-90 downgraded S1 → cosmetic. The collision is a deliberate
alias for a registry-specific spelling difference and is unreachable with real data. My
inference that a live payload could carry both keys is disproven by the headers.
## 13. Correction to section 9, and the root cause of D-107

Inspecting the two JSON bulks forces a correction to the reasoning I gave for downgrading
D-90, and simultaneously root-causes D-107.

### The registration-date spelling matrix

| bulk file | spelling used |
|---|---|
| `enheter_bulk.json.gz` | `registreringsdatoEnhetsregisteret` |
| `underenheter_bulk.json.gz` | `registreringsdatoEnhetsregisteret` |
| `enheter_bulk.csv.gz` | `registreringsdatoenhetsregisteret` (all lowercase) |
| `underenheter_bulk.csv.gz` | **`registreringsdatoIEnhetsregisteret`** |

In section 9 I concluded the two `field_dict` rows existed because the spellings were
*registry*-specific. That is wrong. The `I` variant is used by exactly **one of the four
bulk files** — the underenheter CSV. Its own JSON sibling, covering the identical registry,
uses the non-`I` spelling. So the divergence is **format x registry**, not registry.

The downgrade itself still stands: only one spelling appears per file, so the last-row-wins
overwrite still never fires against real data, and the duplicate dictionary rows are still a
necessary alias. But the reason I gave was incorrect and is corrected here.

### D-107 root-caused: `closure_date` is CSV-only, in both registries

`nedleggelsesdato` occurrences in the first 400,000 lines:

- `enheter_bulk.json.gz` — **0**
- `underenheter_bulk.json.gz` — **0**
- both CSV bulks — present (field 44 of the underenheter header)

So the JSON bulk carries no closure date at all. That is why
`sync-store/state/underenheter.parquet` (JSON bootstrap) lacks `closure_date` while
`snapshot-store/underenheter/...` (CSV) has it. tidybrreg is faithfully reproducing what
each format provides; the defect is that nothing warns the user, and the consequence lands
on a function that matters:

`brreg_survival_data()` derives `exit_date` from `pmin(bankruptcy, liquidation, forced,
deletion/closure)`. Run against a **sync-derived** state it silently loses one of those exit
channels; run against a **snapshot-derived** table it keeps it. The same analysis over the
same register returns different survival curves depending on which store fed it, with no
error and no missing-column warning — `intersect()`-style column handling means the field
just is not there.

This is the class of non-obvious interaction worth hunting: neither `brreg_sync()` nor
`brreg_snapshot()` is individually wrong, and neither help page is individually incorrect.
The defect exists only in the composition.

---
## 14. Cross-table referential integrity — three interactions only visible across files

### D-38 is disproven at the artefact level
The evaluation predicted a lost-update bug: syncing `enheter` and `underenheter` in one call
would have the second type's `historiske_navn` state overwrite the first's. The published
artefact settles it. `historiske_navn.parquet` holds 424,679 distinct orgs, and they
partition exactly:

```
orgs in historiske_navn NOT in underenheter state : 219,397   (= the enheter side)
                                        remainder : 205,282   (= the underenheter side)
                                            total : 424,679
```

219,397 is precisely the count of enheter rows carrying a `historiske_navn` JSON blob in
`enheter.parquet` (section 6). Both registries' contributions coexist; neither overwrote the
other. **D-38 did not reproduce, and the artefact explains why rather than merely recording
a passing check.**

### Other integrity checks pass cleanly
- **Påtegninger are enheter-only:** 0 of 2,747 påtegning orgs appear in the underenheter
  state. Correct — påtegninger attach to hovedenheter.
- **Parent hierarchy is acyclic and well-typed:** 783,160 distinct `parent_org_nr` values
  referenced by underenheter, and **none** of them is itself an underenhet. No cycles, no
  registry confusion.

### New finding — D-108: the shared name-history table has no registry discriminator

`historiske_navn.parquet` columns are `org_nr, position, name, from_date, to_date`. There is
**no `registry` column**, yet the table demonstrably interleaves rows from two registries
(219,397 enheter orgs + 205,282 underenheter orgs). A consumer holding only this file cannot
tell which registry a name-history row belongs to without joining against both state tables
— and if only one state table is present (a single-type sync), the attribution is
unrecoverable.

`?brreg_historical_names` documents the field's origin ("BRREG added `historiskeNavn` to
enheter **and** underenheter on 2026-06-16") and the Value section lists exactly those five
columns, so the docs are internally consistent — they simply never say the two registries
share one table. For a platform whose stated design keeps each source's grain as-observed,
a table whose rows come from two different populations with no discriminator is a genuine
modelling gap: the lowest unit of analysis is ambiguous on its face.

Severity is moderate rather than high because `org_nr` is globally unique across the two
registries in practice, so the join *is* recoverable when both states exist — but it
requires an external lookup to answer a question the row should answer itself.

---
## 15. Single-lookup and search endpoints — completing the spelling matrix, closing D-90

Sections 9 and 13 only sampled the four bulk files. The single-entity and search endpoints
were untested, which left the matrix incomplete and my conclusion under-evidenced. Tested
directly against the live API:

| endpoint | `registreringsdato…` spelling observed |
|---|---|
| `GET enheter/{orgnr}` (x2 entities) | `registreringsdatoEnhetsregisteret` |
| `GET underenheter/{orgnr}` | `registreringsdatoEnhetsregisteret` |
| `GET enheter?size=2` (search) | `registreringsdatoEnhetsregisteret` |
| `GET underenheter?size=2` (search) | `registreringsdatoEnhetsregisteret` |
| `enheter_bulk.json.gz` | `registreringsdatoEnhetsregisteret` |
| `underenheter_bulk.json.gz` | `registreringsdatoEnhetsregisteret` |
| `enheter_bulk.csv.gz` | `registreringsdatoenhetsregisteret` (lowercase) |
| **`underenheter_bulk.csv.gz`** | **`registreringsdatoIEnhetsregisteret`** |
| deleted entity (`SlettetEnhet`) | *field absent entirely* |
| `oppdateringer/enheter` CDC patches | *field absent in sampled window* |

**Every JSON surface BRREG exposes — single lookup, search, and both bulk downloads, across
both registries — uses `registreringsdatoEnhetsregisteret`.** The `I` variant is used by
exactly one artefact in the entire API: the underenheter CSV bulk export. The lowercase
enheter CSV spelling resolves to the same dictionary row case-insensitively.

### Co-occurrence test
Directly tested whether any single payload can carry both spellings, which is the only
condition under which the last-row-wins overwrite could destroy data:

```
single enheter payload : FALSE
search payload (size=50): FALSE
```

### The NAV pair, tested end-to-end on a live lookup
The second collision pair (`…NavAaregisteret` / `…NAVAaregisteret`) **does** co-occur in
spirit — both `registreringsdatoAntallAnsatteEnhetsregisteret` and
`registreringsdatoAntallAnsatteNAVAaregisteret` are present in single-lookup and search
payloads. But they are two *different* fields mapping to two *different* `col_name`s
(`employee_reg_date_er` and `employee_reg_date_nav`), so there is no collision between them
at all — the duplicate dictionary rows are the `Nav`/`NAV` casing variants of the NAV field
only. Verified no value is lost:

```
source  ER  value : 2026-07-15   ->  employee_reg_date_er  : 2026-07-15
source  NAV value : 2026-07-10   ->  employee_reg_date_nav : 2026-07-10
```

### D-90 closed
The mechanism demonstrated in `P-03b` on a synthetic payload is unreachable: no BRREG
endpoint emits both registration-date spellings, and the NAV pair are casing variants of a
single field that round-trips correctly. **D-90 is not a defect** — the duplicate rows are a
necessary alias for one CSV export's spelling quirk plus a casing variant. Final grade:
cosmetic, worth only a comment in `field_dict`.

This is the third time inspection has corrected my own static reading, and the correction
only became available by testing the endpoints I had not sampled. Recording the sequence
honestly: predicted S1 (static) -> demonstrated mechanism (synthetic) -> downgraded on bulk
headers with a wrong reason (registry-specific) -> reason corrected (format x registry) ->
closed on endpoint evidence (one CSV export only, co-occurrence impossible).

---
