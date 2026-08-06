# Artefact ledger

Every file produced by the run, the call that produced it, where it is stored, whether it
has been inspected, and what inspecting it showed. Updated as inspection proceeds.

Run `tidybrreg-stresstest-bdzqm`, `run_date=2026-08-05T125928Z`. 31 files, 1.41 GB.

Legend: **Y** inspected in full · **P** partial (hash/identity only) · **N** not yet.

| # | producing call | artefact | bytes | sha256 | ins | findings |
|---|---|---|---|---|---|---|
| 1 | brreg_download("enheter") -> ETag sidecar | `cache/R/tidybrreg/enheter_bulk.csv.etag` | 33 | `d79ba54fab75` | Y | Bare 32-hex, unquoted, no `W/`. Written unconditionally (D-24). |
| 2 | brreg_download("enheter", format="csv") | `cache/R/tidybrreg/enheter_bulk.csv.gz` | 154,280,254 | `f600bd60a0d7` | Y | 90 header fields -> 90 parquet cols, exact. Spelling `registreringsdatoenhetsregisteret` (lowercase). |
| 3 | brreg_download("enheter") -> ETag sidecar | `cache/R/tidybrreg/enheter_bulk.json.etag` | 33 | `ff33283c638a` | Y | As above. |
| 4 | brreg_download("enheter", format="json") | `cache/R/tidybrreg/enheter_bulk.json.gz` | 209,611,159 | `290a1c2e5aa6` | Y | Pretty-printed array. `links` not `_links` (D-92 cause). `respons_klasse`=Enhet, `historiskeNavn`+`paategninger` inline. **No `nedleggelsesdato`** (D-107 cause). |
| 5 | brreg_download("roller") -> ETag sidecar | `cache/R/tidybrreg/roller_bulk.json.etag` | 33 | `2535d76de2d9` | Y | As above. |
| 6 | brreg_download("roller", format="json") | `cache/R/tidybrreg/roller_bulk.json.gz` | 129,572,899 | `d935b66a9c5d` | Y | Line 1 is `[` -> D-57 cause. No `fratraadt` (D-09 cause). `valgtAv`: only 13% AREP (D-13 quantified). 13,640 nested `_links`/200k lines. |
| 7 | brreg_download("underenheter") -> ETag sidecar | `cache/R/tidybrreg/underenheter_bulk.csv.etag` | 33 | `541e2dfa3a7b` | Y | As above. Value matches manifest `etag` for all 3 entries. |
| 8 | brreg_download("underenheter", format="csv") | `cache/R/tidybrreg/underenheter_bulk.csv.gz` | 60,724,372 | `8ebc97433bf7` | Y | 44 header fields -> 44 parquet cols, exact. **Only file using `registreringsdatoIEnhetsregisteret`.** |
| 9 | brreg_download("underenheter") -> ETag sidecar | `cache/R/tidybrreg/underenheter_bulk.json.etag` | 33 | `9de48fe0e8f7` | Y | As above; no consumer in this run. |
| 10 | brreg_download("underenheter", format="json") | `cache/R/tidybrreg/underenheter_bulk.json.gz` | 87,956,073 | `df625f591271` | N | `respons_klasse`=Underenhet. `historiskeNavn` inline. **No `nedleggelsesdato`** -> D-107. Uses `registreringsdatoEnhetsregisteret`, NOT the `I` variant its CSV sibling uses. |
| 11 | rig fixture: write_parquet_safe(enheter snapshot_date=2025-07-01) | `shared-store/enheter/snapshot_date=2025-07-01/data.parquet` | 7,672,238 | `5f79aed90da3` | Y | 49,925 rows x 90 cols; planted mutations present. Fixture integrity OK. |
| 12 | rig fixture: write_parquet_safe(enheter snapshot_date=2026-01-17) | `shared-store/enheter/snapshot_date=2026-01-17/data.parquet` | 7,669,938 | `99c26c1e45a4` | Y | 49,950 rows x 90 cols; planted mutations present. Fixture integrity OK. |
| 13 | rig fixture: write_parquet_safe(enheter snapshot_date=2026-07-06) | `shared-store/enheter/snapshot_date=2026-07-06/data.parquet` | 7,672,367 | `df6eb45aedac` | Y | 49,975 rows x 90 cols; planted mutations present. Fixture integrity OK. |
| 14 | rig fixture: write_parquet_safe(enheter snapshot_date=2026-08-05) | `shared-store/enheter/snapshot_date=2026-08-05/data.parquet` | 7,675,302 | `60c3409d1879` | Y | 50,000 rows x 90 cols; planted mutations present. Fixture integrity OK. |
| 15 | rig fixture: write_parquet_safe(underenheter snapshot_date=2025-07-01) | `shared-store/underenheter/snapshot_date=2025-07-01/data.parquet` | 1,619,639 | `78de2efe8386` | N |  |
| 16 | rig fixture: write_parquet_safe(underenheter snapshot_date=2026-08-05) | `shared-store/underenheter/snapshot_date=2026-08-05/data.parquet` | 1,603,575 | `80eb86777a19` | N |  |
| 17 | RIG test artefact (32-snapshot.R file.copy) | `snapshot-store/import-src.csv.gz` | 60,724,372 | `8ebc97433bf7` | P | RIG artefact; byte-identical 3rd copy. Rig hygiene: sits in store root. |
| 18 | brreg_snapshot() -> manifest append | `snapshot-store/manifest.json` | 2,226 | `c9f7ae1c3209` | Y | D-55 dup ids, D-103 same hash 2 dates, D-58 dangling paths, D-102 empty cdc bridge, D-56 no import entry, D-106 mixed time encodings. |
| 19 | brreg_import(type="roller") (D-57) | `snapshot-store/roller/snapshot_date=2024-01-01/data.parquet` | 120,697,617 | `68f1d585dab7` | Y | 116,018,041 rows x 1 col named `[`. Listed by `brreg_snapshots()`, opens via `brreg_open()`. D-57 worse than predicted. |
| 20 | brreg_snapshot("underenheter") | `snapshot-store/underenheter/snapshot_date=2026-08-05/data.parquet` | 56,602,751 | `018a724a5be6` | Y | 854,499 x 44. All org_nr valid, 0 dup. 5 cols 100% NA (present-but-empty in source). Has `closure_date`. |
| 21 | brreg_snapshot() -> raw payload copied into partition (D-54) | `snapshot-store/underenheter/snapshot_date=2026-08-05/raw/underenheter_bulk.csv.gz` | 60,724,372 | `8ebc97433bf7` | P | 44 header fields -> 44 parquet cols, exact. **Only file using `registreringsdatoIEnhetsregisteret`.** |
| 22 | brreg_sync(format="csv") -> enheter.parquet | `sync-csv-store/state/enheter.parquet` | 163,292,160 | `8e9b3d68a7f5` | Y | 1,170,637 x 90. Same population as JSON path. No blob, no response_class. |
| 23 | brreg_sync(format="csv") -> historiske_navn.parquet | `sync-csv-store/state/historiske_navn.parquet` | 924 | `77fcfb42485e` | Y | **0 rows** - CSV bulk carries no `historiskeNavn`. Documented divergence. |
| 24 | brreg_sync(format="csv") -> paategninger.parquet | `sync-csv-store/state/paategninger.parquet` | 38,530 | `ee157392637b` | Y | 2,753 rows / 2,746 orgs - matches JSON path to 1 row despite per-entity fetches (D-35 buys nothing). |
| 25 | brreg_sync(format="csv") -> sync_cursor.json | `sync-csv-store/state/sync_cursor.json` | 109 | `d20ff07a265b` | Y | enheter only; underenheter/roller ids = 0. No timezone. |
| 26 | brreg_sync(format="json") -> enheter.parquet | `sync-store/state/enheter.parquet` | 178,344,294 | `d1d1f04326b8` | Y | 1,170,637 x 92. Extra `response_class` (const "Enhet") + `historiske_navn` JSON blob (18.74%, duplicates dedicated table). |
| 27 | brreg_sync(format="json") -> historiske_navn.parquet | `sync-store/state/historiske_navn.parquet` | 25,088,191 | `e4317ccdbe72` | Y | 635,234 x 5 across 424,679 orgs (spans BOTH registries). `from_date`/`to_date` are character. |
| 28 | brreg_sync(format="json") -> paategninger.parquet | `sync-store/state/paategninger.parquet` | 38,570 | `eb0fcd6f078d` | Y | 2,754 rows / 2,747 orgs. |
| 29 | brreg_sync(format="json") -> roller.parquet | `sync-store/state/roller.parquet` | 2,757 | `0044e2424a53` | Y | 0 rows x 17 cols - correct typed-empty for `roller_method="cdc"`. |
| 30 | brreg_sync(format="json") -> sync_cursor.json | `sync-store/state/sync_cursor.json` | 122 | `17482724fb85` | Y | All 3 ids non-zero. `last_sync` has NO timezone (D-33 on disk). |
| 31 | brreg_sync(format="json") -> underenheter.parquet | `sync-store/state/underenheter.parquet` | 70,009,726 | `de490830a2e6` | Y | 854,499 x 43. `response_class`="Underenhet". **Lacks `closure_date`** -> D-107. |
