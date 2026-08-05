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
