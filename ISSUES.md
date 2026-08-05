# Issues log

Running log of everything found while executing the suite: environment problems, rig bugs
(my mistakes), and confirmed package defects that weren't already tagged. Entries are
appended in the order discovered. Each entry says what happened, what I changed (if
anything), and why.

Format: `[timestamp UTC] SEVERITY area — description`

---

## 2026-08-04

### [23:03] ENV — background processes do not survive across tool-call boundaries
`bash setup.sh &` followed by a later tool call polling the log found the process gone
after ~20s of apt output. The execution environment tears down child processes between
tool invocations unless they're detached from the controlling session. Fix: launch
long-running commands with `setsid nohup CMD > log 2>&1 < /dev/null &` and poll the log
file in subsequent calls. Applied to `setup.sh` and will apply to every `run_all.R`
invocation from here on. Not a defect in tidybrreg or the test rig; a property of the
sandbox.

### [23:03] ENV — single core, 3.9 GB RAM, ~10 GB free disk
The plan assumed multi-core parallelism (`STRESS_CORES`). Hardware has 1 core. Tiers 1 and
3 will run with `mc.cores = 1`, i.e. serially within the tier — `mclapply` handles this
correctly (falls back to sequential `lapply`-like behavior), so no code change is needed,
only the environment variable. Per direction, running serially rather than reducing test
scope.

### [23:03] PACKAGE — installed tidybrreg is not the commit I evaluated
`install.R` pulls from r-universe HEAD, which now serves commit `c9bd992`
("Harmonize array collapse and stop fabricating absent columns"), pushed today at
15:40 UTC — after the static evaluation (`316610b`) that seeded this suite's defect tags,
before this run's install at 23:03 UTC. The new commit:

- Fixes **D-28** (array-valued fields joined with `"; "` in `flatten_cell()` vs `", "` in
  `flatten_json()`): both now join on `"\n"`.
- Fixes **D-26** (`rename_and_coerce()` stamping every `field_dict` column, including
  ~12 underenheter-only columns, onto every enheter row): columns are now batch-scoped —
  present only if observed anywhere in the batch, matching the `resigned` precedent from
  0.5.0.
- **Breaking change not previously evaluated**: `brreg_entity()` on a single entity now
  returns ~61–63 columns instead of a fixed ~104. Several checks in this suite
  (`E-04`, `E-32`, `P-13`, `P-14`, `S-04`, `DL-17`) assert the *old* full-schema contract
  as correct behavior. That assertion is no longer valid — the new contract is arguably
  closer to the package's own naive-empiricism principle (report what was observed, not a
  padded superset). These checks will need rewriting to test the new contract rather than
  the old one; that is a rig correction, not a defect finding, and is logged as such below
  when I get to `12-entity.R` / `11-parse-internals.R` / `13-search.R`.

Decision: run the suite as specified against whatever is actually installed (this *is*
"latest tidybrreg" per the brief). Do not pin to `316610b`. Reconcile check-by-check as
failures surface, distinguishing three outcomes explicitly in this log:
1. **rig bug** — my check encoded a wrong assumption; fixed, noted here.
2. **stale defect tag** — a `D-xx` tag predicted a failure that the new commit fixed;
   the run classifies this as `pass_unexpected`, which is the harness working as designed,
   not an error. Left as-is; noted in the summary.
3. **new confirmed defect** — a genuine failure with no prior tag; added to the defect
   register addendum below with a new `D-9x` id.

---
### [23:08] RIG BUG — `10-validate.R` V-13 used an invalid fixture
`isFALSE(brreg_validate("999999999"))` was asserted as the "check digit computes to 10"
case. Verified by hand and independently in R: `999999999` has mod-11 remainder 2, check
digit 9, which **matches** its own last digit — it is a valid number
(`brreg_validate("999999999")` returns `TRUE`). This was carried over from the earlier
static evaluation without verifying the arithmetic. Fixed by generating a genuine
check-digit-10 fixture (`90770209` + any final digit, confirmed programmatically to be
unmatchable for all ten possible check digits) and asserting rejection across all ten.
Cross-checked the other two org-number fixtures used in `12-entity.R`
(`923609017` invalid, `889640782` valid-but-nonexistent) — both correct, no further
action. `10-validate.R` now: 19 pass, 1 confirmed defect (D-02).

### [23:15] NEW DEFECT — D-90: `field_dict` maps two distinct api_paths to one `col_name`
`field_dict$col_name` has two duplicate pairs: `registration_date`
(`registreringsdatoEnhetsregisteret` / `registreringsdatoIEnhetsregisteret`) and
`employee_reg_date_nav` (`registreringsdatoAntallAnsatteNavAaregisteret` /
`registreringsdatoAntallAnsatteNAVAaregisteret`, a pure casing variant). Demonstrated
concretely: constructing a payload with both api_paths present under different values
causes `rename_from_dict()` to silently keep whichever field_dict row is processed last,
discarding the other (verified: `registration_date` resolves to the second row's value
when both are supplied). For the NAV pair this is at worst a casing-robustness gap; for
`registration_date` the two api_paths look like genuinely distinct upstream fields (the
"I" variant), not a casing accident, so a live payload carrying both would silently lose
one — this part is **inferred**, not yet confirmed against a live payload carrying both
keys, since I have not observed that combination on the actual API. Added `P-03` (raw
duplicate check) and `P-03b` (mechanistic demonstration) to `11-parse-internals.R`, tagged
`D-90`.

### [23:15] RIG BUG — three checks in `11-parse-internals.R` needed correction

- **P-13** asserted `all(field_dict$col_name %in% names(m))` for a single small payload —
  this is exactly the pre-`c9bd992` full-schema contract that today's upstream commit
  deliberately removed. Rewritten to assert the new contract: the emitted column count is
  smaller than the full dictionary, and every emitted name is either a known dictionary
  name or a valid auto-snake passthrough.
- **P-16** iterated over *every* `field_dict` Date/integer column unconditionally and
  indexed `m[[c]]` even for columns the (now batch-scoped) parse never emitted, so
  `inherits(NULL, "Date")` failed for the always-absent ones. Fixed to intersect the
  declared-type columns with the columns actually present before asserting their class.
- **P-32** was inverted: it asserted `setequal(output columns, full field_dict)` as the
  *correct* result and tagged the check `D-26` — i.e. it treated the old stamping bug as
  the thing a correct package should do. That was backwards from the start (a
  pre-existing bug in the previous turn's test authoring, not something the upstream
  commit caused) and would have measured the wrong thing even against the originally
  evaluated commit. Rewritten to assert the actually-correct behavior (no columns beyond
  what's observed) and split off `P-32b` to confirm a field *is* still emitted once
  observed anywhere in a multi-row batch. The `D-26` tag is removed from this file — D-26
  (underenheter carrying all-NA enheter-only columns) is specifically and correctly
  covered by `DL-18` in `31-download.R` against a real underenheter bulk parse, which is
  where it belongs.

`11-parse-internals.R` now: 56 pass, 7 confirmed defects (D-90, D-09, D-05×2, D-27, D-17,
D-18), 0 unexplained.

### [23:35] NEW DEFECT — D-91: BRREG's live deletion signal has moved past 410, and `brreg_entity()` never adapted
`brreg_entity()`'s deletion handling is written entirely around HTTP 410. Empirically,
across 25 sampled real deletions (20 within the last 14 days via CDC discovery, 5 more
from a 180-day CDC window), **0/25 returned 410**. Every one resolves at HTTP 200 with an
inline signal in the JSON body: `respons_klasse: "SlettetEnhet"` plus a populated
`slettedato`. `brreg_entity()` has no code path that inspects either field — the payload
just flows through the ordinary `parse_entity()` path, batch-scoped to whatever the
(sparse) response happens to contain. Net effect: a definitively deleted entity is
returned indistinguishable from an ordinary sparse one — no `deleted` flag, no warning —
unless the caller independently knows to check `deletion_date`. This is a live-API
characterization (confirmed empirically, not from source alone) layered on top of the
originally-catalogued D-01 (which describes the *never-reached-live* HTTP 410 branch's own
narrow 4-column collapse). Registered both: D-01 confirmed via `httr2::with_mocked_responses`
(the only way to actually reach that branch given the API's current behavior), D-91
confirmed against live traffic.

### [23:35] NEW DEFECT — D-92: nested HAL `_links` blocks are not stripped
`organisasjonsform._links.self.href` (a nested link inside the legal-form sub-object)
survives into `brreg_entity()` output as a real column, `organisasjonsform__links_self_href`,
with the raw BRREG-internal URL as its value. Two independent guards exist in the
codebase and neither catches it: `rename_from_dict()`'s unmapped-field filter only drops
keys that literally start with `_links` (top-level only); `drop_hal_links()` (used only in
the bulk-parse path, not by `brreg_entity()` at all) matches on a `links$` suffix, which
doesn't match this path's actual leaf (`...self.href`). Confirmed live (value observed:
`https://data.brreg.no/enhetsregisteret/api/organisasjonsformer/ASA`) and reproduced with a
minimal synthetic payload against the internal `rename_from_dict()` directly.

### [23:35] RIG BUG — three assertions in `12-entity.R` had the direction inverted
Caught the same mistake as P-32 in `11-parse-internals.R`, in three places: the first-draft
mocked-410 checks (`E-15`, `E-17`) and the live-deletion checks (`E-19c`, `E-19d`, `E-19e`)
asserted the *actual observed defective behavior* as the thing to confirm, rather than
asserting *correct* behavior and letting the assertion fail to confirm the defect. Under
the suite's own classification rules this would have miscoded every one of these as
`pass_unexpected` (implying the defect didn't reproduce) when the opposite was true. Fixed
by rewriting each to assert what a correct package would do (preserve more than 4 columns
on a definitive deletion; have `type = "label"` produce an observable effect; set an
explicit `deleted` flag; warn the caller) so they now fail-to-confirm D-01/D-91 the same
way every other tagged check in the suite does. Also detagged two checks (`E-19a`, `E-19b`)
that were mislabelled as tidybrreg defects when they're actually just characterizations of
BRREG's own current API behavior — a precondition for D-91 to be meaningful, not a claim
about the package.

`12-entity.R` now: 35 pass, 5 confirmed defects (D-01 ×2, D-91 ×3), 0 unexplained.

### [23:50] METHOD CORRECTION — a rigid assertion licensed by the docs is a RESULT, not a rig bug
I had been reclassifying doc-licensed assertions as "rig bugs" and softening them whenever
the installed build disagreed. That is backwards: if the function signature and its
documentation led to the assertion, a failure is a finding about the package, not about the
test. Reverted the softening of `E-04`, `E-26`, `E-27`, `E-28`, `E-30` and `S-04`.

`brreg_entity()`'s own Value section states: "Key columns include 'org_nr', 'name',
'legal_form', 'employees', 'founding_date', 'nace_1', 'municipality_code', 'bankrupt', and
'parent_org_nr'." Empirically, ENK entities carry neither `founding_date` nor `employees`,
and NUF entities carry no `municipality_code`. The documented contract is violated →
registered as **D-93** rather than absorbed into the tests. The `c9bd992` NEWS entry
documents the new batch-scoped behavior but the function's own Value section was never
updated to match, so the two now contradict each other inside the same installed build.

Rewrites that stand (internal, undocumented machinery, not doc-licensed): `P-13`, `P-16`,
`P-32` in `11-parse-internals.R` target unexported helpers with no roxygen contract, and
`P-32`'s original form asserted the defective behavior itself, which was a genuine authoring
error independent of any upstream change.

### [08:10] NEW DEFECT — D-97: `type_output = "arrow"` is broken on the real bulk CSV
`brreg_download(type = "enheter", type_output = "arrow")` fails outright:
`Invalid: CSV parse error: Expected 90 columns, got 63`. Reproduced independently outside
the harness by calling `arrow::read_csv_arrow()` on the cached file directly. The same file
parses cleanly via `readr::read_csv()` (200,000 rows x 90 columns), so the file is not
corrupt — arrow's CSV reader and readr disagree on embedded newlines inside quoted address
fields (the failing record is a Tromsø street address). The documented arrow path is
therefore unusable against the live register, not merely inconsistent in column naming as
D-25 described. D-25 (arrow path returns unrenamed columns) cannot even be reached, since
the read itself aborts. Affects `DL-10`, `DL-11`, `DL-12`.

### [08:10] ENV — OOM at 3.9 GB on JSON bulk parse and JSON sync bootstrap
`parse_bulk_json()` on the 200 MB enheter JSON, and `brreg_sync(format = "json")`
bootstrap, are both killed by the OOM reaper on this box (3.9 GB RAM, single core). Not a
tidybrreg defect per se, but a real capacity finding: the JSON path materialises the whole
register in memory. Recorded rather than worked around, per instruction not to reduce
scope.

### [08:10] RIG FIX — results were lost entirely when a process was killed
`stress_flush()` only wrote at end-of-file, so the three OOM kills (31-download,
32-snapshot, 34-sync) produced no results at all despite dozens of checks having already
run. Added `stress_flush_incremental()` called from `stress_record()`, writing
`{file}.partial.rds` atomically after every check, and taught `summarise_results()` to fold
in partials for files with no completed result (flagged as incomplete). Re-running
31-download now captures 12 checks up to the OOM point where previously it captured zero.
This is a genuine mechanical rig defect, not an assertion change.

### [08:10] DOC ADJUDICATION (partial)
- **D-95** (label leaves a mutating `names` attribute): `brreg_label()` Value states "the
  same tibble with code columns replaced by English labels". A column carrying a stray
  `names` attribute whose value changes between passes (`"ASA"` then `NA`) is not that.
  → tidybrreg issue.
- **D-96** (`lang = "no"` returns English): the `lang` argument is documented as
  '"no" (Norwegian original from brreg API)'. Returns English for both `nace_1` and
  `legal_form`. Unambiguous documented-contract violation. → tidybrreg issue.
- **D-94** (RFC 6902 `move` emits no source removal): `brreg_update_fields()` docs are
  silent on `move` semantics — they only document the synthetic-NA-row behaviour for Ny /
  Sletting / Fjernet. Not doc-licensed, so the check is an RFC-derived expectation rather
  than a documentation violation. Still filed, because the consequence is real (a replay
  applying only the destination row leaves the source field stale), but flagged as
  spec-derived. → tidybrreg issue, lower confidence.

### [09:20] RIG BUG — `run_all.R` could not be sourced without executing a full run
The bottom-of-file dispatcher was guarded by `if (!interactive())`, which is TRUE under
`source()` as well as under `Rscript run_all.R`. Sourcing the file to reach
`summarise_results()` or `stress_manifest()` therefore kicked off a complete 19-file run.
Found while wiring CI, where the report job needs the aggregation functions without
re-running anything. Replaced with `stress_invoked_as_script()`, which additionally
requires `run_all.R` to appear in `commandArgs(trailingOnly = FALSE)`. Verified both paths:
`source()` now loads 19 manifest rows and runs nothing; `Rscript run_all.R summarise` still
aggregates.

### [09:20] CI — GitHub Actions and Cloud Run job added
Both exist because the OOM kills recorded earlier are an artifact of this 3.9 GB sandbox,
not of the suite. GitHub runners give 16 GB and Cloud Run is configured for 32 GB / 8 CPU,
so the JSON bulk parse and the JSON `brreg_sync()` bootstrap that were killed here should
complete there — which is the only way to get a real result for `DL-13`..`DL-17`, the
`32-snapshot` tail, and all of `34-sync`.

- `.github/workflows/stresstest.yml` — three jobs: `light` (tiers 0-1), `heavy` (tiers 2-3,
  needs the fixtures artifact from `light`), `report` (merges artifacts, aggregates, writes
  a job summary, and exits non-zero **only** on unexplained regressions — confirmed defects
  do not fail the build, which is the whole point of the outcome taxonomy). Weekly cron plus
  `workflow_dispatch` with the STRESS_* knobs as inputs.
- `Dockerfile` + `cloudrun/entrypoint.sh` + `cloudrun/deploy.sh` — built on the project's
  own `r-images/r-base:latest`, deployed via the Cloud Build REST API with the context
  tarball in `gs://sondreskarsten-d7d14_cloudbuild/`, image pinned by SHA256 digest rather
  than `:latest`, job in `europe-north1`, scheduler in `europe-west1`. Results and the code
  that produced them are published together to
  `gs://sondre_brreg_data/raw/tidybrreg_stresstest/run_date=.../`.
- `setup.sh` made sudo-aware so it works both as root (container) and as a normal user
  (GitHub runner).

Caveat carried into both: parallelism multiplies request rate against a public register.
tidybrreg throttles 5 req/s **per process**, so `STRESS_CORES` workers means 5N req/s.
Defaults are deliberately low (2 on Actions, 4 on Cloud Run) rather than matching core count.

### [10:55] INFRA DEFECT (recurring) — R ABI break inside the Cloud Run image, second occurrence
Fixed `rlang`'s `undefined symbol: SETLENGTH` by upgrading `r-base-core` alongside the
packages I named explicitly. The full Cloud Run pass then failed on
`vroom.so: undefined symbol` — the identical fault in a package I had *not* named. `readr`
pulls `vroom`, which stayed compiled against the base image's older R while `r-base-core`
moved forward.

Root cause is structural, not a typo: `FROM r-images/r-base:latest` + `apt-get install
r-cran-*` mixes two R ABIs whenever r2u has moved ahead of the pinned base image, and it
surfaces only at *runtime*, disguised as test failures. Fixed properly by running
`apt-get upgrade -y` so every pre-existing r-cran binary is rebuilt against the new R,
plus a build-time assertion that `requireNamespace()`-loads all 18 packages the suite
touches and fails the build listing any that don't.

**This is worth checking across the project's other pipeline images** — anything built
`FROM r-base:latest` that then apt-installs additional R packages is exposed to the same
silent break.

Impact on the results already collected: of the 29 "unexplained regressions" from the
first complete Cloud Run pass, the large majority are this ABI break, not tidybrreg
defects — `BW-11`, `DL-09`, nine `SN-*`/`IM-*` checks, and then `PN-00` and
`SY-14`/`SY-37`..`SY-41` as downstream cascade (prewarm and sync partially failed, so the
snapshot store and changelog those checks depend on were never written). They must be
re-run on v4 before any of them is characterised. Treating that 29 as a defect count would
have been wrong.

### [10:55] RIG BUG — GCS publish silently dropped by a malformed copy
`entrypoint.sh` published with
`gcloud storage cp -r tests R run_all.R Dockerfile "${DEST}/code/"`, but the Dockerfile was
never `COPY`d into the image, so the whole invocation failed with "URLs matched no objects
or files". The results copy had actually succeeded — the failure was cosmetic but looked
total, and the earlier v2 image had no `gcloud` at all and skipped publishing with only an
`echo`. Fixed three ways: `COPY` the Dockerfile into the image, copy each code artefact in
its own invocation guarded by `[ -e ]`, and verify with `gcloud storage ls` afterwards,
setting a failure flag if zero objects were published.

### [10:55] CI — GitHub runner reclaimed mid-tier
The `heavy` job received "The runner has received a shutdown signal" 19 minutes into
tier 3 and was hard-cancelled, which skips even `if: always()` steps, so the artifact was
lost. Restructured tier 3 into a per-file matrix with `fail-fast: false`: a reclaimed
runner now costs one file instead of five.

### [11:40] RIG BUG — matrix restructure broke cache locality (tier 3 read another runner's paths)
Splitting tier 3 into a per-file matrix fixed the runner-reclaim problem but introduced a
worse one: each matrix job restored `prewarm.rds` (which records absolute paths to the
warm download cache) without restoring the cache itself. Every tier-3 job therefore
pointed at `/home/runner/work/.../tmp/cache/...` on a *different, already-destroyed*
runner. Symptoms looked like package defects and were not:

- `DL-13`, `DL-14`, `DL-15`, `DL-17` — `lexical error: invalid char in json text`, i.e.
  jsonlite reading a path that isn't the JSON bulk.
- `IM-01`, `IM-02`, `IM-03`, `IM-05`, `IM-06` — `brreg_import()` failures, because the
  test's `file.copy()` of the underenheter bulk silently produced nothing to import.

Fixed by keying an `actions/cache` entry on `github.run_id`, saved by `prewarm` and
restored by every tier-3 job, plus an explicit guard step that fails the job outright if
`enheter_bulk.csv.gz` is absent rather than letting the file run against phantom paths.
Nine "regressions" were this, and would have been mischaracterised as tidybrreg defects.

### [11:40] RIG BUG — committed results contaminated CI artifacts
`results/` is git-tracked (deliberately, so each run is mappable to its file). But every CI
job checks the repo out *including* my sandbox results, then uploads `results/*.rds`
wholesale — so each artifact carried stale sandbox copies of files that job never ran, and
`merge-multiple: true` resolved collisions by upload order. This is why `EV-13` still
showed as an untagged regression in the merged artifact even though `D-98` was tagged in
the repo: an older sandbox `33-panel-series-events.rds` won the merge. Fixed with a
post-checkout step in every job that clears tracked results before anything runs.

### [11:40] RIG BUG — `RP-04` tag never applied
The earlier bulk retag matched `identical(out, "err")\\n  })` for `EV-13` but the
corresponding `RP-04` pattern didn't match, so `D-99` was never attached. Applied
directly and verified by grep rather than by pattern replacement.

### [11:40] CONFIRMED — arrow CSV failure reproduces on a clean 16 GB runner
`DL-16` and `DL-20` fail on GitHub with the same
`Expected 90 columns, got 63` at the Tromsø address as in the sandbox, so **D-97 is not a
memory artefact** — `arrow::read_csv_arrow()` genuinely cannot read the live enheter bulk.
Both checks now tagged `D-97`.

### [12:20] FILE-OUTPUT INSPECTION — new test file `36-file-outputs.R` (25 checks)
Everything so far judged tidybrreg by its return values. This file judges it by the
artefacts it leaves on disk: partition layout, parquet contents, `manifest.json`, the sync
cursor, and the changelog tree. Findings from inspecting the real stores:

**D-54 confirmed end to end, at runtime.** The raw `.gz` really is written *inside* the
hive partition (`underenheter/snapshot_date=2026-08-05/raw/underenheter_bulk.csv.gz`), and
`brreg_open("underenheter")` consequently fails with
`Invalid: Could not open Parquet input source '.../raw/underenheter_bulk.csv.gz'`.
`brreg_snapshot()` writes a store layout that tidybrreg's own reader cannot open. It also
doubles storage: 54 MB parquet + 58 MB raw per snapshot. This was *inferred* in the
original static evaluation; it is now observed. (`FO-04`, `FO-05`, `FO-06`.)

**D-55 confirmed on disk.** `manifest.json` holds three entries with two sharing the id
`underenheter_2026-08-04`. (`FO-11`.)

**D-102 (new) — the documented CDC bridge metadata is never populated.**
`brreg_manifest()`'s docs promise the manifest records "CDC bridge metadata", and
`build_manifest_entry()` takes a `cdc_bridge_first_update_id` argument, but a scan of every
function in the namespace shows only `build_manifest_entry` (which defines it) and
`brreg_manifest` (which reads it) mention the field — **no caller ever passes it**. Every
entry on disk carries `"cdc_bridge_first_update_id": {}`. The consequence matters for this
platform specifically: without it there is no recorded join point between a bulk snapshot
and the CDC stream, which is exactly the gap that makes D-36 (the bootstrap blind window)
unrecoverable after the fact. (`FO-14`.)

**D-103 (new, low severity) — identical content stored under two different dates.**
Three manifest entries share one `file_hash`, one `etag`, and one server `last_modified`,
but are filed under `snapshot_date` 2026-08-04 and 2026-08-05. `brreg_snapshot(date=)` is
documented as a label, so this is legitimate per the docs, but nothing flags that two
differently-dated "snapshots" are byte-identical, so a panel built over the store will
silently show zero change across a boundary that never existed. (`FO-15`.)

**D-104 not confirmed — hypothesis was wrong.** After the partial `enheter_bulk.json.gz`
incident I assumed `brreg_download()` would silently serve truncated cache as valid data.
`FO-25` tests this directly by truncating a cached payload to 5 MB: the download layer
*does* reuse it without comment (`Using cached file (4.8 MB)`), but the parse layer errors
out, so corrupt data does not reach the caller. The reuse-without-validation is real; the
data-integrity failure I predicted is not. Recording the check as passing rather than
quietly dropping it.

Checks `FO-17`..`FO-22` skip locally because `brreg_sync()` has never completed on this
box (OOM), so no cursor, state, or changelog exists to inspect. They are the reason this
file is registered as tier 4 and included in the CI matrix — the sync artefacts only exist
on a runner with enough memory.

### [12:40] GAP CLOSED — artefacts produced by function calls were never saved
Until now only `results/` (the check records) and `code/` were published. Every file the
functions under test actually *wrote* — snapshot parquet partitions, the copied raw `.gz`,
`manifest.json`, sync state parquet, `sync_cursor.json`, changelog partitions, the download
cache — lived in the container or runner and was destroyed with it. So `36-file-outputs.R`
could only ever inspect artefacts on whichever machine happened to still have them, and the
Cloud Run runs (the only ones where `brreg_sync()` completes) left nothing behind at all.

Added `cloudrun/capture_artifacts.sh`, invoked from the Cloud Run entrypoint and from every
tier-3 CI job. It walks the `tmp/` tree and writes:

- `results/artifact_inventory.tsv` — one row per file with size, mtime, and SHA-256, so a
  run's outputs are content-addressable and comparable across runs.
- `results/artifact_summary.txt` — per-store counts and byte totals plus a depth-4 tree.
- `results/artifacts/` — every file at or under 50 MB copied verbatim.

Files above the cap (the four bulk payloads: 154 MB enheter CSV, 210 MB enheter JSON,
130 MB roller JSON, 61 MB underenheter CSV) are catalogued with a `head1m:` fingerprint
rather than uploaded, so they stay identifiable without moving ~550 MB per run into GCS.

Measured on the local sandbox tree: 20 files, 883,482,947 bytes on disk, 11 published
verbatim. The inspectable artefacts — `manifest.json`, the etags, the sync cursor, the
changelog partitions, and the snapshot parquet where small enough — are exactly the ones
that fit under the cap, which is what makes the file-output checks meaningful off-machine.

