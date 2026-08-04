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

