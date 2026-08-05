# tidybrreg 0.5.0 — permutation-level critical evaluation

Source: `sondreskarsten/tidybrreg` @ `316610b`, 43 exported functions across 31 files (6,652 lines R).
Evaluation is static: code and roxygen read line by line, no execution (no R in this container).
Every claim is tagged `verified-from-code` (traceable to the source above), `inferred`
(depends on runtime behaviour of a dependency or the live API), or `unverifiable`.

## Restatement of the request

Enumerate every exported function and every materially distinct argument configuration of
each; for each, state the literal call, what it should do, and what it persists (disk,
session environment, network). Judge each against the code and its own documentation.

**Permutation policy.** The full cartesian product is not enumerable in useful form —
`brreg_search()` alone has ~1,024 argument combinations and `brreg_sync()` has 56. A
*materially distinct* permutation is one that changes at least one of: the return schema,
a disk write, a session-environment write, the number or target of HTTP calls, or the
code path taken. Argument values that only vary a filter predicate are collapsed into one
row and noted. Response-branch variants (200/404/410, empty payload, state present/absent)
are enumerated as permutations because they change the return schema.

**"What it saves"** is read as all persistence: files under `brreg_data_dir()`, files under
`tools::R_user_dir("tidybrreg","cache")`, and bindings written into the package's session
environment `.brregEnv` (which persists across calls within a session and is invisible to
the user).

---

## 0. Structural verdict before the enumeration

| Dimension | Verdict |
|---|---|
| API-surface coverage | Good. enheter, underenheter, roller, oppdateringer (×3), juridiskeroller, konsernstruktur, fullmakt signatur/prokura, bulk lastned (×3), SSB KLASS. |
| Schema stability of returns | **Poor.** At least 6 functions return a different column set depending on the *data*, not the arguments. |
| Persistence model | Three uncoordinated stores: download cache, snapshot store, sync state — with no shared lock, no transaction, and one confirmed lost-update path. |
| Naive-empiricism fit | **Weak.** The sync engine mutates state in place and deletes rows on exit; the changelog is the only immutable artifact and it is written *after* the events are computed but *before* the state, with no atomic pairing. |
| Error discipline | Inconsistent. Some functions abort, some warn and return `tibble()`, some `break` silently and return partial results with no signal. |
| Dead code / dead parameters | 4 confirmed (see D-14, D-15, D-21, D-24). |

---

## 1. Entity lookup — `R/entities.R`

### 1.1 `brreg_entity()`

Cartesian: 3 registries × 2 types = 6, times 3 response branches = 18. All 18 enumerated.

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 1 | `brreg_entity("923609016")` | Validate mod-11, GET `enheter/923609016`, 200 → 1-row tibble, ~103 field_dict cols + unmapped passthrough + `registry="enheter"` | nothing | OK |
| 2 | `brreg_entity("923609016", registry="enheter")` | Same, single registry, no fallback | nothing | OK |
| 3 | `brreg_entity("923609016", registry="underenheter")` | GET `underenheter/…`; 404 for a hovedenhet → **abort** | nothing | OK, message names the searched registry |
| 4 | `brreg_entity("923609016", type="label")` | As #1 then `brreg_label()` | **`.brregEnv$nace_en`, `.brregEnv$sector_en`** | ⚠ silently issues 2 extra HTTP calls to `data.ssb.no` on first use; undocumented at this level (D-11) |
| 5 | `brreg_entity(x, registry="enheter", type="label")` | As #4 | same | ⚠ D-11 |
| 6 | `brreg_entity(x, registry="underenheter", type="label")` | As #4 for a BEDR | same | ⚠ D-11 |
| 7 | `brreg_entity("974760673")` where entity is deleted → **410** | Warn, return 4-col tibble `org_nr, registry, deleted, deletion_date` | nothing | ⚠ **D-01** schema switch on data |
| 8 | `brreg_entity(deleted, type="label")` | 410 branch returns *before* labelling | nothing | ⚠ `type` silently ignored |
| 9 | `brreg_entity("999999999")` (mod-11 fails) | Abort with examples | nothing | OK |
| 10 | `brreg_entity("123456789")` (valid mod-11, prefix 1) | **Abort** — rejected by the `^[89]` prefix rule before any call | nothing | ⚠ **D-02** |
| 11 | `brreg_entity(923609016)` (numeric) | `as.character()` coerces | nothing | OK |
| 12 | `brreg_entity(NA)` | `"NA"` fails regex → abort | nothing | OK |
| 13 | `brreg_entity(c("923609016","984851006"))` | **Not vectorised.** `brreg_validate` returns length-2; `if()` takes the first → builds URL `enheter/c("…","…")`? No — `paste0(reg,"/",org_nr)` is vectorised, `req_url_path_append` takes the first. Silent wrong-entity return | nothing | ⚠ **D-03** |
| 14 | `brreg_entity(x)` where enheter=404, underenheter=200 | Loop falls through, `matched_registry="underenheter"` | nothing | OK — the one genuinely good branch |
| 15 | `brreg_entity(x)` where enheter=500 | `status != 404` → break; abort "API error: HTTP 500" | nothing | OK |
| 16 | `brreg_entity(x)` both 404 | Abort naming both registries | nothing | OK |
| 17 | `brreg_entity(x)` enheter=410 | Break on 410, warn, deleted tibble | nothing | OK given D-01 |
| 18 | `brreg_entity(x)` 429 | `req_retry` 3 tries, then whichever status | nothing | OK |

### 1.2 `brreg_search()`

Cartesian ≈ 1,024. Materially distinct: 21.

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 19 | `brreg_search()` | No filters, `size=100`, page 0..1, returns first 200 entities of the whole register | nothing | OK but a 200-row arbitrary slice of 1.1M is rarely what anyone wants |
| 20 | `brreg_search(name="Equinor")` | `navn=` partial match, ≤200 rows, `attr(,"total_matches")` | nothing | OK |
| 21 | `brreg_search(legal_form="AS")` | `organisasjonsform=AS` | nothing | OK |
| 22 | `brreg_search(municipality_code="0301")` | `kommunenummer=` (enheter branch) | nothing | OK |
| 23 | `brreg_search(municipality_code="0301", registry="underenheter")` | Switches key to `beliggenhetsadresse.kommunenummer` | nothing | OK — good branch |
| 24 | `brreg_search(nace_code="64.190")` | `naeringskode=` | nothing | OK |
| 25 | `brreg_search(min_employees=500)` | `fraAntallAnsatte=` | nothing | OK |
| 26 | `brreg_search(max_employees=10)` | `tilAntallAnsatte=` | nothing | OK |
| 27 | `brreg_search(min_employees=500, max_employees=1000)` | Both bounds | nothing | OK |
| 28 | `brreg_search(bankrupt=TRUE)` | `konkurs=true` | nothing | OK |
| 29 | `brreg_search(bankrupt=TRUE, registry="underenheter")` | **`bankrupt` silently dropped** — no warning | nothing | ⚠ documented, still silent (D-04) |
| 30 | `brreg_search(parent_org_nr="923609016")` | `overordnetEnhet=` | nothing | OK |
| 31 | `brreg_search(max_results=10)` | `size=min(100,10)=10`, one page, break on `length>=max_results` | nothing | OK |
| 32 | `brreg_search(max_results=1000)` | `size=100`, 10 pages, 10 sequential HTTP calls at 5 req/s | nothing | OK |
| 33 | `brreg_search(max_results=50000)` | Warns at the 10,000 ceiling, returns ≤10,000 | nothing | OK |
| 34 | `brreg_search(name="zzzznotfound")` | `_embedded` absent → break → `tibble()` (0 cols) with `total_matches=0` | nothing | ⚠ **D-05** zero-column tibble breaks any downstream `$name` |
| 35 | `brreg_search(name="x")` when API returns 500 | `break` on first page → empty tibble, `total_matches` NULL→0 | nothing | ⚠ **D-06** network failure indistinguishable from no matches |
| 36 | `brreg_search(name="Equinor", type="label")` | Labels legal_form/nace/sector; `total_matches` attr survives (`label_df` mutates in place) | `.brregEnv` dicts | OK |
| 37 | `brreg_search(…) |> brreg_label(code="legal_form")` | Adds `legal_form_code`; `x[, c(...)]` reorder **drops `total_matches`** | `.brregEnv` dicts | ⚠ **D-07** |
| 38 | `brreg_search(registry="underenheter")` | `_embedded$underenheter` key | nothing | OK |
| 39 | `brreg_search(legal_form="AS", municipality_code="0301", min_employees=500, max_results=10)` | All filters ANDed server-side | nothing | OK |

### 1.3 `brreg_underenheter()` / 1.4 `brreg_children()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 40 | `brreg_underenheter("923609016")` | `brreg_search(parent_org_nr=, registry="underenheter", max_results=200)` | nothing | ⚠ **D-08** default 200 silently truncates large parents |
| 41 | `brreg_underenheter(x, max_results=10000)` | 100 pages, ~20 s at 5 req/s | nothing | OK |
| 42 | `brreg_underenheter(x, type="label")` | Passes `type` through | `.brregEnv` dicts | OK |
| 43 | `brreg_underenheter(x)` with no sub-units | 0-col tibble | nothing | ⚠ D-05 |
| 44 | `brreg_children("971524960")` | Same on `registry="enheter"` — ORGL hierarchy | nothing | OK |
| 45 | `brreg_children(x, max_results=10000)` | As #41 | nothing | OK |
| 46 | `brreg_children(x, type="label")` | As #42 | `.brregEnv` dicts | OK |
| 47 | `brreg_children(x)` for an AS | Always 0 rows (AS parents use konsern, not `overordnetEnhet`) | nothing | OK, documented |

---

## 2. Roles and governance — `R/roles.R`, `R/governance.R`, `R/konsern.R`, `R/signatur.R`

### 2.1 `brreg_roles()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 48 | `brreg_roles("923609016")` | GET `enheter/x/roller`, flatten rollegrupper→roller, 17–18 cols, `person_id` = `birth_date_last_first_middle` | nothing | OK |
| 49 | `brreg_roles(x)` post-2026-06-16 payload | `fratraadt` absent → all-NA → **`resigned` column dropped entirely** | nothing | ⚠ **D-09** schema depends on data |
| 50 | `brreg_roles(x)` replayed pre-June payload | `resigned` present, NAs → FALSE | nothing | OK |
| 51 | `brreg_roles(x)` entity with no roles | `rollegrupper` empty → `tibble()` 0 cols | nothing | ⚠ D-05 |
| 52 | `brreg_roles("999999999")` → 404 | Warn, `tibble()` | nothing | ⚠ no validation before the call, unlike `brreg_entity` |
| 53 | `brreg_roles(deleted_org)` → 410 | Same warn+empty; **deletion information lost** | nothing | ⚠ D-10 |
| 54 | `brreg_roles(x)` with >200 roles | `vector("list",200)` overflows; R grows the list — correct, O(n) copies | nothing | OK (perf only) |
| 55 | `brreg_roles(x)` auditor firm role | `entity_org_nr`/`entity_name` populated, `person_id` NA | nothing | OK; `extract_entity_name` handles both jsonlite and yyjsonr shapes — good |

### 2.2 `brreg_roles_legal()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 56 | `brreg_roles_legal("923609016")` | GET `roller/enheter/x/juridiskeroller`, one row per role held elsewhere | nothing | OK |
| 57 | `brreg_roles_legal(x)` no roles | `tibble()` | nothing | ⚠ D-05 |
| 58 | `brreg_roles_legal(x)` HTTP ≥400 | `tibble()` **with no warning** | nothing | ⚠ **D-06** inconsistent with `brreg_roles` which warns |
| 59 | `brreg_roles_legal(x)` post-June | `resigned` dropped | nothing | ⚠ D-09 |

### 2.3 `brreg_board_summary()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 60 | `brreg_roles("923609016") |> brreg_board_summary()` | 1-row tibble, 11 cols, STYR members only, active filter | nothing | OK |
| 61 | `bind_rows(lapply(orgs, brreg_roles)) |> brreg_board_summary()` | **Silently wrong**: `org_nr = roles$org_nr[1]` but counts pool every org | nothing | ⚠ **D-12** the obvious vectorised use is unguarded and returns plausible garbage |
| 62 | `brreg_board_summary(tibble())` | `roles$role_group_code` is NULL → subsetting error | nothing | ⚠ no empty guard, and #51/#57 make empty input routine |
| 63 | `brreg_board_summary(roles_without_resigned)` | Column-tolerant filter (0.5.0 fix) → `resigned_flag=FALSE` scalar, recycles | nothing | OK — fix is correct |
| 64 | `brreg_board_summary(roles)` — `n_employee_elected` | `sum(!is.na(elected_by))` counts **any** `valgtAv`, not just employee election | nothing | ⚠ **D-13** mislabelled covariate |

### 2.4 `brreg_konsern()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 65 | `brreg_konsern("923609016")` | GET `konsernstruktur/x`, recursive flatten, root synthesised `KKKK`/"Øverste mor" at level 0 | nothing | OK — the recursion is the cleanest code in the package |
| 66 | `brreg_konsern(x)` not in a group → 404 | **Warn** + `tibble()` | nothing | ⚠ **D-16** the modal case for ordinary AS emits a warning; `lapply` over 1,000 orgs produces 1,000 warnings |
| 67 | `brreg_konsern("999999999")` | Same warn+empty — indistinguishable from #66 | nothing | ⚠ documented, mitigation requires a second call |
| 68 | `brreg_konsern(x)` 6-level ASA group | One row per node, `level` from observed `nivaa` | nothing | OK |
| 69 | `brreg_konsern(x)` where `dato` is `"24.06.2026"` | `as.Date()` with no format → **error**, whole call fails | nothing | ⚠ **D-17** *inferred* — depends on the live payload's date format; `brreg_signatur` parses `%d.%m.%Y` for the sibling Fullmakt service, so the risk is real |

### 2.5 `brreg_signatur()` / 2.6 `brreg_prokura()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 70 | `brreg_signatur("923609016")` | GET fullmakt `enheter/x/signatur`, one row per person per combination, 12 cols, `signature_type="signature"` | nothing | OK |
| 71 | `brreg_signatur(x)` combination with no persons | One row, person fields NA | nothing | OK — good, preserves the rule |
| 72 | `brreg_signatur(x)` 404 | Warn + `tibble()` | nothing | ⚠ D-16 (common for ENK) |
| 73 | `brreg_signatur(x)` `rule_status="RI"` | `rule` is the statutory default; the *registered* rule is `rule_text` | nothing | OK — documented precisely; genuinely good doc work |
| 74 | `brreg_prokura("923609016")` | Identical shape, `signature_type="procuration"` | nothing | OK |
| 75 | `brreg_prokura(x)` no prokura | Warn + `tibble()` | nothing | ⚠ D-16 |
| 76 | any | `birth_date` parsed `%d.%m.%Y`; if Fullmakt returns ISO → **all NA, silently** | nothing | ⚠ **D-18** *inferred*; the format differs from `brreg_roles`, so one of the two is wrong for a join |

### 2.7 `brreg_board_network()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 77 | `brreg_board_network(c("923609016","984851006"))` | 2 `brreg_roles` calls, bipartite **undirected** `tbl_graph` | nothing | ⚠ direction convention differs from `brreg_network` (directed) |
| 78 | `brreg_board_network(roles_data=roles)` | `org_nrs` ignored, no HTTP | nothing | OK |
| 79 | `brreg_board_network(org_nrs=x, roles_data=y)` | `roles_data` wins silently | nothing | ⚠ minor |
| 80 | `brreg_board_network()` | Abort "Provide org_nrs or roles_data" | nothing | OK |
| 81 | `brreg_board_network(x)` where roles empty | Abort "No role data" | nothing | OK |
| 82 | any | Entity nodes joined to `entity_name`, which is the **role-holding** entity (the auditor firm), not the subject | nothing | ⚠ **D-19** entity nodes carry an unrelated firm's name |

### 2.8 `brreg_survival_data()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 83 | `brreg_survival_data(firms)` | `entry_date=founding_date`, `exit_date=pmin(bankruptcy,liquidation,forced,deletion)`, `event`, `duration_years` | nothing | ⚠ **D-20** |
| 84 | `brreg_survival_data(firms, entry_var="registration_date")` | Registry entry instead of founding | nothing | OK — and this should be the default, per `brreg_flows`' own reasoning |
| 85 | `brreg_survival_data(firms, censoring_date="2025-12-31")` | Fixed censoring | nothing | OK |
| 86 | `brreg_survival_data(firms, entry_var="nope")` | Abort | nothing | OK |
| 87 | `brreg_survival_data(bulk_download)` | Input is the *current* register → deleted firms absent → **`event=1` only for firms that failed but were not yet deleted** | nothing | ⚠ **D-20** survivorship bias; no warning |
| 88 | `brreg_survival_data(panel)` | Multiple rows per org → duration computed per row, no dedupe | nothing | ⚠ silently produces a panel-shaped "survival" table |

---

## 3. Bulk download and parsing — `R/download.R`, `R/parse.R`

Cartesian: 3 types × 2 formats × 3 refresh × 2 cache × 3 outputs = 108. Materially distinct: 24.

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 89 | `brreg_download()` | enheter/csv/tibble; GET `enheter/lastned/csv` → `~/.cache/R/tidybrreg/enheter_bulk.csv.gz`; `readr::read_csv` all-character; rename+coerce; ~1.1M × ~103 | **cache file, etag file, `.brregEnv$last_download_resp`, `$last_download_url`** | OK |
| 90 | `brreg_download()` second call | `needs_download=FALSE` → parses the cached file, prints size+mtime | nothing new | OK |
| 91 | `brreg_download(refresh=TRUE)` | Force re-download | cache + etag | OK |
| 92 | `brreg_download(refresh="auto")` with etag file | HEAD (no throttle, no retry, no UA consistency) → compare → conditional download | cache + etag | ⚠ **D-22** if the server sends no ETag, `server_etag` is NULL → never refreshes, silently |
| 93 | `brreg_download(refresh="auto")` with no etag file | Condition `file.exists(etag_file)` fails → uses cache forever | nothing | ⚠ D-22 |
| 94 | `brreg_download(refresh="always")` | Not validated; behaves as `FALSE` | nothing | ⚠ **D-23** no `match.arg` on a 3-valued argument |
| 95 | `brreg_download(cache=FALSE)` | **Still writes the 152 MB payload to the cache dir**; `cache` only gates the etag file | cache file written anyway | ⚠ **D-24** argument does not do what it says |
| 96 | `brreg_download(type_output="path")` | Returns the `.gz` path, no parse | cache | OK — the only memory-safe option |
| 97 | `brreg_download(type_output="arrow")` | `read_csv_arrow(as_data_frame=FALSE)` → **raw Norwegian column names, no field_dict, no coercion** | cache | ⚠ **D-25** contradicts "Results from both paths use the same column names via field_dict" |
| 98 | `brreg_download(format="json")` | GET `enheter/lastned`; `jsonlite::fromJSON(flatten=TRUE)`; flatten list-cols; drop HAL; rename+coerce. Carries `historiskeNavn` and inline `paategninger` | cache | OK |
| 99 | `brreg_download(format="json", type_output="arrow")` | `read_json_arrow` on a `.gz` | cache | ⚠ D-25, plus arrow's JSON reader expects NDJSON, not a JSON array — *inferred* failure |
| 100 | `brreg_download(type="underenheter")` | ~59 MB, ~824K rows | cache | ⚠ **D-26** `rename_and_coerce` injects every field_dict column, so the result carries ~40 all-NA enheter-only columns |
| 101 | `brreg_download(type="underenheter", format="json")` | As #98 | cache | ⚠ D-26 |
| 102 | `brreg_download(type="roller")` | Format forced to json with an info message; GET `roller/totalbestand`; `read_roles_json` → yyjsonr if installed | cache | OK — the yyjsonr dispatch is well done |
| 103 | `brreg_download(type="roller", format="csv")` | Coerced to json, message | cache | OK |
| 104 | `brreg_download(type="roller")` without yyjsonr | `jsonlite::fromJSON(simplifyVector=FALSE)` on 131 MB gz → documented 32 GiB requirement | cache | ⚠ info message only; should be a hard warning |
| 105 | `brreg_download(type="roller", type_output="arrow")` | `read_json_arrow` — same *inferred* NDJSON problem | cache | ⚠ D-25 |
| 106 | `brreg_download(type="roller", type_output="path")` | Path only | cache | OK |
| 107 | any csv path where an integer column has >20 unparseable values | `tibble(column=len 1, row=len n, expected=len 1, actual=len 20)` → **vctrs recycling error, whole parse aborts** | cache written, no return | ⚠ **D-27, confirmed from code** |
| 108 | any csv path with ≤20 such values | Attaches `brreg_parse_problems`, warns | cache | OK |
| 109 | any json path | Unnamed lists joined with `"; "`; the single-entity path (`flatten_json`) joins with `", "` | — | ⚠ **D-28** the same field has different separators depending on which function fetched it |
| 110 | any | Two API paths that snake to the same name → second **silently dropped** (`if (!col_name %in% names(result))`) | — | ⚠ **D-29** violates the stated zero-drop policy |
| 111 | `brreg_download(type="enheter", format="json", refresh="auto", cache=FALSE, type_output="arrow")` | Compound of #92, #95, #97, #99 | cache | ⚠ four defects compose silently |
| 112 | any | `.brregEnv$last_download_resp` holds a full httr2 response for the session | `.brregEnv` | minor leak; only read by `brreg_snapshot` |

---

## 4. CDC feed — `R/updates.R`

### 4.1 `brreg_updates()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 113 | `brreg_updates()` | `since=yesterday`, `size=100`, `max_pages=1` → **at most 100 events**, 4 cols | nothing | ⚠ **D-30** the default silently returns a truncated feed with no signal |
| 114 | `brreg_updates(size=10000, max_pages=50)` | Cursor pagination `oppdateringsid = max+1`, stop when a page is short | nothing | OK — exclusive cursor is correct against the inclusive endpoint |
| 115 | `brreg_updates(since="2026-03-01")` | `dato=2026-03-01T00:00:00.000Z` on page 1 only, cursor thereafter | nothing | OK |
| 116 | `brreg_updates(since=as.POSIXct("2026-03-01 14:00"))` | Time-of-day **discarded** — hardcoded `T00:00:00.000Z` | nothing | ⚠ **D-31** |
| 117 | `brreg_updates(since=Sys.Date())` run in UTC−5 | `format(as.POSIXct(date))` renders in local tz → date can shift back one day | nothing | ⚠ D-31 |
| 118 | `brreg_updates(include_changes=TRUE)` | Adds `changes` list-column of `operation/field/new_value` | nothing | OK |
| 119 | `brreg_updates(type="underenheter")` | `_embedded$oppdaterteUnderenheter` | nothing | OK |
| 120 | `brreg_updates(type="roller")` | **Delegates to `brreg_updates_roller(since,size)`**: ignores `max_pages`, `include_changes`, `verbose`; uses `afterTime`, one page | nothing | ⚠ **D-32** three arguments silently ignored |
| 121 | `brreg_updates(type="roller", max_pages=50)` | Same single page | nothing | ⚠ D-32 |
| 122 | `brreg_updates(verbose=TRUE)` | Per-page cli line with cursor | nothing | OK |
| 123 | `brreg_updates(size=99999)` | Capped at 10000 | nothing | OK |
| 124 | `brreg_updates()` mid-pagination 503 | `break` → partial result, **no warning** | nothing | ⚠ D-06; a truncated CDC read is indistinguishable from a complete one |
| 125 | any | `timestamp` parsed `as.POSIXct(x, format="%Y-%m-%dT%H:%M:%OS")` with **no `tz=`** → a UTC instant is reinterpreted as local | nothing | ⚠ **D-33** systematic; affects updates, sync, replay, flows |

### 4.2 `brreg_update_fields()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 126 | `brreg_update_fields()` | `includeChanges=true` forced, flat 7-col output, synthetic NA row per patch-less event | nothing | OK — the synthetic row is a good design decision |
| 127 | `brreg_update_fields(max_pages=50, size=10000)` | Cursor pagination on `max(flat$update_id)` | nothing | OK |
| 128 | `brreg_update_fields(type="underenheter")` | Correct `_embedded` key | nothing | OK |
| 129 | `brreg_update_fields(type="roller")` | **`match.arg` rejects it** | nothing | OK — correctly narrower than `brreg_updates` |
| 130 | `brreg_update_fields()` with a 3-level nested patch value | `flatten_page_patches` bottoms out at `as.character(child)` on a named list → length >1 assigned into `r_val[k]` → **error** | nothing | ⚠ **D-34** *inferred*; `parse_patch`/`flatten_value_into` recurses correctly, so the two flatteners disagree |
| 131 | `brreg_update_fields()` where all `update_id` are NA | `max(..., na.rm=TRUE)` on empty → `-Inf` + warning → cursor corrupt | nothing | ⚠ low likelihood |
| 132 | `brreg_update_fields()` `op="move"` | Emits destination row **and** a synthetic `remove` at `$from` | nothing | OK — RFC 6902 handled properly |
| 133 | `brreg_update_fields()` empty feed | Typed 7-col empty tibble | nothing | OK — the only function that returns a *typed* empty |

---

## 5. Sync engine — `R/sync.R`, `R/state.R`

Cartesian: 7 type-subsets × 2 methods × 2 formats × 2 verbose = 56. Materially distinct: 18.

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 134 | `brreg_sync()` first run | Bootstrap all 3 from csv bulk → extract påtegninger → extract historiske_navn → write 5 state parquets → init cursors from CDC tip → sync | `state/{enheter,underenheter,roller,paategninger,historiske_navn}.parquet`, `state/sync_cursor.json`, `state/changelog/sync_date=D/batch-HHMMSS.parquet`, cache files, `.brregEnv$state_*` | ⚠ **D-35, D-36, D-37** |
| 135 | `brreg_sync()` bootstrap, csv format, påtegninger | `extract_paategninger` finds the boolean flag → **one `brreg_req` per flagged entity, sequential, 5 req/s** | as above | ⚠ **D-35** ~100K flagged entities ⇒ ~5.5 h of blocking HTTP inside what reads like a parse step |
| 136 | `brreg_sync(format="json")` bootstrap | Inline arrays parsed, **no per-entity fetches**, `historiskeNavn` backfilled | as above | OK — and strictly better than the default |
| 137 | `brreg_sync()` bootstrap cursor init | Bulk downloaded at T0, `get_cdc_tip()` queried at T1 → **events in (T0,T1] are never applied** | cursor | ⚠ **D-36** silent gap of minutes-to-hours on every bootstrap |
| 138 | `brreg_sync()` bootstrap when the feed has no events today | `get_cdc_tip` returns `0L` → cursor 0 → next sync warns and replays from the head of the feed, capped at 5 pages | cursor | ⚠ **D-37** |
| 139 | `brreg_sync(types=c("enheter","underenheter"))` | Both read `historiske_navn` state from disk **before** either writes → the second overwrites the first's additions | state files | ⚠ **D-38 lost update, confirmed from code** |
| 140 | `brreg_sync(types="enheter")` | Single type, no lost update | state, changelog, cursor | OK |
| 141 | `brreg_sync(types="roller")` | Cursor poll bounded at 5 pages, then **full 131 MB totalbestand download** + `diff_roller_state` over 3.4M rows | `roller.parquet` replaced wholesale, changelog | ⚠ **D-39** |
| 142 | `brreg_sync(roller_method="cdc")` bootstrap | Writes an **empty** roller state, skips the 125 MB download | `roller.parquet` (0 rows) | OK — good, and well documented |
| 143 | `brreg_sync(roller_method="cdc")` incremental | One `brreg_roles()` call per affected org; per-org `diff_roller_state`; per-event timestamps | state, changelog | OK; slow but correct attribution |
| 144 | `brreg_sync(roller_method="bulk")` incremental | `rows_update(changelog, event_map, by="org_nr")` rewrites timestamps to the per-org CDC max; orgs changed in the bulk with **no** CDC event keep `updates$timestamp[nrow(updates)]` — an arbitrary last row, not a max | state, changelog | ⚠ **D-40** timestamp attribution is fictional for the residual set |
| 145 | `brreg_sync()` with >50K roller events | `paginate_cdc_bounded` caps at 5 pages; cursor advances only to event 50,000 while the bulk diff already applied everything → next run re-downloads 131 MB to find nothing | as above | ⚠ D-39 |
| 146 | `brreg_sync()` daily, 500 `Ny` events | `apply_ny_events`: 500 sequential `brreg_entity()` calls **plus** 500 full copies of a 1.1M-row tibble (`state[state$org_nr != x,]` then `bind_rows`) | state | ⚠ **D-41** O(n·m); minutes-to-hours |
| 147 | `brreg_sync()` daily, 30K `Endring` events | `which(state$org_nr == org)` per event → 30,000 × 1.1M scans | state | ⚠ **D-41** |
| 148 | `brreg_sync()` `Endring` on an unmapped field | `find_state_column` returns NULL → **patch silently dropped**, no changelog row | state | ⚠ **D-42** the hand-maintained 70-entry map is the drift surface; a new brreg field is invisible |
| 149 | `brreg_sync()` `Sletting` | Row removed from state, `change_type="exit"` in changelog, påtegninger and name history for that org **deleted** | state | ⚠ **D-43** destroys the historical record the changelog claims to preserve; directly contravenes the immutability premise |
| 150 | `brreg_sync(verbose=FALSE)` | Same work, no cli | as above | OK |
| 151 | `brreg_sync()` crash between state and cursor write | Next run replays from the old cursor; upserts idempotent | partial | OK for enheter; **not** for påtegninger, where `apply_paategning_patches` appends unconditionally → duplicate annotation rows on replay | ⚠ **D-44** |

### 5.1 `brreg_sync_status()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 152 | `brreg_sync_status()` after sync | cli block: last sync, 3 cursors, 5 state file sizes, changelog partition/file counts; invisible list | creates `state/` and `state/changelog/` **as a side effect of a status call** | ⚠ minor |
| 153 | `brreg_sync_status()` before any sync | `cursor$last_sync` is `NA_character_`, and `%||%` only catches NULL → prints `Last sync: NA` instead of `never` | dirs created | ⚠ **D-45** |

---

## 6. Changelog queries — `R/changes.R`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 154 | `brreg_changes()` | All partitions, 8 cols, ordered by character timestamp | nothing | OK |
| 155 | `brreg_changes(from=Sys.Date()-30)` with arrow installed | `open_dataset(partitioning="sync_date")` infers a **string** partition column; `filter(sync_date >= from)` compares string to Date | nothing | ⚠ **D-46** *inferred* arrow kernel error `(string, date32)` |
| 156 | `brreg_changes(from=…)` without arrow | String comparison on directory names — works | nothing | OK |
| 157 | `brreg_changes()` arrow vs non-arrow | Arrow path returns an **extra `sync_date` column** | nothing | ⚠ **D-47** return schema depends on which Suggests are installed |
| 158 | `brreg_changes(track="nace_1")` | Keeps `field %in% track` **or `field` is NA** → all entry/exit rows come back too | nothing | ⚠ **D-48** undocumented and surprising |
| 159 | `brreg_changes(registry="roller")` | Partition-level filter passthrough | nothing | OK |
| 160 | `brreg_changes(change_type=c("entry","exit"))` | OK | nothing | OK |
| 161 | `brreg_changes(org_nr="923609016")` | Post-filter in R after reading everything | nothing | ⚠ no pushdown; reads all partitions to return one org |
| 162 | `brreg_changes(from=a, to=b)` | Filters on **partition (sync) date**, not event `timestamp` | nothing | ⚠ **D-49** a late-arriving event dated D lands in partition D+3 and is filtered as D+3 |
| 163 | `brreg_changes()` with no changelog | `empty_changelog()` — typed, 8 cols | nothing | OK |
| 164 | `brreg_change_summary()` | Counts by registry × change_type × field | nothing | OK |
| 165 | `brreg_change_summary(from=, to=, registry=)` | Same, filtered | nothing | OK |
| 166 | `brreg_change_summary(track=…)` | **Not an argument** despite `@inheritParams brreg_changes` | nothing | ⚠ doc noise |
| 167 | `brreg_change_summary()` empty | Returns `registry/change_type/field/n` | nothing | OK |

---

## 7. Flows — `R/flows.R`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 168 | `brreg_flows()` with a changelog present | Changelog path; joins nace/kommune from **current** enheter state | nothing | ⚠ **D-50, D-51** |
| 169 | `brreg_flows()` — exits | Exited orgs were **deleted from state** by `apply_slett_events` → the join yields NA for every exit → exits form NA-keyed groups and never offset entries | nothing | ⚠ **D-50 confirmed**; `net` is wrong at every non-NA key |
| 170 | `brreg_flows()` — entries | Historical entries carry **present-day** nace/kommune | nothing | ⚠ **D-51** attribute anachronism |
| 171 | `brreg_flows()` no changelog, no data | Abort with instructions | nothing | OK |
| 172 | `brreg_flows(entities)` | Bulk-only: entries from `registration_date`, `exits=0` | nothing | ⚠ **D-52** the bulk contains only survivors ⇒ historical entry counts are survivor-filtered |
| 173 | `brreg_flows(entities, updates=cdc)` | Adds CDC entries and exits, `flow_source=c("registration_date","cdc")` | nothing | ⚠ double-counts recent `Ny` events already carrying a `registration_date` in the bulk |
| 174 | `brreg_flows(entities, by=NULL)` | National totals | nothing | OK |
| 175 | `brreg_flows(entities, by="legal_form")` | `intersect(by, names(data))` | nothing | OK |
| 176 | `brreg_flows(entities, by="nope")` | Silently drops to no grouping | nothing | ⚠ silent |
| 177 | `brreg_flows(entities, legal_form="AS")` | Pre-filter | nothing | OK |
| 178 | `brreg_flows(legal_form="AS")` on the changelog path | **`legal_form` and `updates` silently ignored** | nothing | ⚠ **D-53** |
| 179 | `brreg_flows(entities, from=, to=)` | Post-filter on date | nothing | OK |
| 180 | `brreg_flows(data_without_registration_date)` | Abort naming missing columns | nothing | OK |
| 181 | any | `attr(,"flow_source")`, `attr(,"by")`, `attr(,"brreg_panel_meta")` set | nothing | OK |

---

## 8. Snapshot store — `R/snapshot.R`, `R/manifest.R`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 182 | `brreg_snapshot()` | Prompt (interactive), `brreg_download(refresh=TRUE)`, **copy the raw .gz into the partition**, parse, write parquet, append manifest | `{data_dir}/enheter/snapshot_date=D/data.parquet`, `…/raw/enheter_bulk.csv.gz`, `manifest.json`, cache file, `.brregEnv` | ⚠ **D-54** |
| 183 | `brreg_open()` after #182 | `open_dataset(base, hive_partition(snapshot_date=date32()))` recurses into `snapshot_date=D/raw/` and tries to read a `.gz` as parquet | — | ⚠ **D-54** *inferred but high-probability*: the raw copy sits inside the dataset root; arrow does not filter by extension |
| 184 | `brreg_snapshot(force=TRUE)` | Overwrite partition; append a **second** manifest entry with the same `id` | as #182 | ⚠ **D-55** manifest is append-only with non-unique ids |
| 185 | `brreg_snapshot(ask=FALSE)` | No prompt | as #182 | OK |
| 186 | `options(brreg.allow_download=TRUE); brreg_snapshot()` | Prompt bypassed | as #182 | OK |
| 187 | `brreg_snapshot(date="2026-01-01")` | Partition key is the argument, but the payload is **today's** register | as #182 | ⚠ documented; still a mislabelling footgun |
| 188 | `brreg_snapshot(format="json")` | Carries `historiskeNavn` + inline påtegninger | as #182 | OK |
| 189 | `brreg_snapshot(type="roller")` | `format` forced json, `parse_roles_bulk` | `roller/snapshot_date=D/…` | OK |
| 190 | `brreg_snapshot(type="underenheter")` | ~59 MB | as #182 | OK |
| 191 | `brreg_snapshot()` when the partition exists, `force=FALSE` | Info + early return of the path, **no manifest entry** | nothing | OK |
| 192 | `brreg_import(path, snapshot_date="2024-12-31")` | `parse_bulk_csv` → parquet partition | `enheter/snapshot_date=…/data.parquet` | ⚠ **D-56** no manifest entry, no raw copy — provenance asymmetry with `brreg_snapshot` |
| 193 | `brreg_import(path, d, type="roller")` | `match.arg` **accepts roller**, body always calls `parse_bulk_csv` → a roller JSON is parsed as CSV | garbage parquet | ⚠ **D-57 confirmed** |
| 194 | `brreg_import(json_path, d)` | No `format` argument exists → JSON bulk cannot be imported | garbage | ⚠ D-57 |
| 195 | `brreg_import(path, d, force=TRUE)` | Overwrite | parquet | OK |
| 196 | `brreg_snapshots()` | Scans `snapshot_date=*` dirs, returns date/size/path | nothing | OK |
| 197 | `brreg_snapshots("roller")` / `("underenheter")` | Same per type | nothing | OK |
| 198 | `brreg_snapshots()` with none | Typed empty tibble | nothing | OK — good |
| 199 | `brreg_open()` with no snapshots | Abort with instructions | nothing | OK |
| 200 | `brreg_open()` without arrow | `check_installed("arrow")` | nothing | OK |
| 201 | `brreg_cleanup(keep_n=12)` | Deletes all but the 12 newest partition dirs (**including their raw copies**) | deletes dirs | OK |
| 202 | `brreg_cleanup(max_age_days=365)` | Age criterion | deletes dirs | OK |
| 203 | `brreg_cleanup(keep_n=12, max_age_days=365)` | **Union** of both criteria (`|`), not intersection | deletes dirs | ⚠ deletes more than a reader expects |
| 204 | `brreg_cleanup()` | Abort | nothing | OK |
| 205 | `brreg_cleanup(keep_n=1, type="roller")` | Per-type | deletes | OK |
| 206 | any cleanup | Manifest entries for deleted snapshots are **not** removed → manifest points at absent files | — | ⚠ **D-58** |
| 207 | `brreg_data_dir()` | Returns the path, **creating it** | creates a directory | ⚠ getter with a side effect |
| 208 | `options(brreg.data_dir="/x"); brreg_data_dir()` | Honoured | creates `/x` | OK |
| 209 | `brreg_manifest()` no file | Typed 13-col empty tibble | nothing | OK |
| 210 | `brreg_manifest()` with entries | One row per download, `file_hash` via `rlang::hash_file` | nothing | OK |
| 211 | `brreg_manifest()` with a file whose `downloads` is empty | `if (length(entries)==0) return(brreg_manifest())` → **infinite recursion** | stack overflow | ⚠ **D-59 confirmed from code** |

---

## 9. Panel construction — `R/panel.R`, `R/series.R`, `R/events.R`, `R/tsibble.R`

### 9.1 `brreg_panel()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 212 | `brreg_panel()` | Yearly targets (Dec 31), LOCF to nearest prior snapshot, inner_join many-to-many, `add_entry_exit` | nothing | ⚠ **D-60** |
| 213 | `brreg_panel("quarter")` | Quarter-end targets | nothing | OK |
| 214 | `brreg_panel("month")` | Month-end targets | nothing | OK |
| 215 | `brreg_panel("custom", dates=c(...))` | Supplied targets | nothing | OK |
| 216 | `brreg_panel("custom")` with `dates=NULL` | `as.Date(NULL)` → zero targets → mapping 0 rows → abort | nothing | ⚠ unhelpful message |
| 217 | `brreg_panel(cols=c("employees","nace_1"))` with arrow | `select_cols` is **computed and never used**; the dataset is collected in full, then subset in R | nothing | ⚠ **D-61** dead variable, no projection pushdown, full 1.1M × 103 read |
| 218 | `brreg_panel(cols=…)` without arrow | Per-file read then subset; `needs_dates[match(files[i], …)]` relies on two sort orders coinciding | nothing | ⚠ fragile, currently correct |
| 219 | `brreg_panel(max_gap=2)` | Drops periods whose LOCF gap exceeds `max_gap × period_days` | nothing | OK |
| 220 | `brreg_panel("custom", max_gap=2)` | `period_days = max(gap)` ⇒ threshold `2 × max(gap)` ⇒ **filter is a no-op** | nothing | ⚠ **D-62** |
| 221 | `brreg_panel(type="roller")` | Allowed; roller has many rows per org → the "firm × period panel" is a role × period panel with duplicated keys | nothing | ⚠ **D-63** |
| 222 | `brreg_panel(label=TRUE)` | `brreg_label` on the whole panel | `.brregEnv` dicts, KLASS HTTP | OK |
| 223 | `brreg_panel()` with <2 snapshots | Abort | nothing | OK |
| 224 | any | `is_entry = period == min(period)`, `is_exit = period == max(period)` **per firm** → every firm present at the panel start is "entry" and every firm alive at the end is "exit" | nothing | ⚠ **D-60 confirmed**: both indicators are left/right-censoring artifacts, not events |
| 225 | any with `bankrupt` present | `is_exit` additionally ORs in `bankrupt==TRUE` → a firm bankrupt in 3 periods is "exit" 3 times | nothing | ⚠ D-60 |

### 9.2 `brreg_series()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 226 | `brreg_series()` | Counts entities per yearly period | nothing | OK |
| 227 | `brreg_series(.vars="employees")` | `employees_total` per period | nothing | OK |
| 228 | `brreg_series(.vars="employees", .fns=list(avg=mean, sd=sd))` | `employees_avg`, `employees_sd`; **`mean` without `na.rm`** → NA whenever any firm is NA | nothing | ⚠ default asymmetry with the package default `\(x) sum(x, na.rm=TRUE)` |
| 229 | `brreg_series(by="legal_form")` | Grouped | nothing | OK |
| 230 | `brreg_series(by=c("legal_form","municipality_code"))` | Multi-group | nothing | OK |
| 231 | `brreg_series(by="nope")` | `read_cols` intersect drops it → `all_of(grp)` errors on a missing column | nothing | ⚠ opaque error |
| 232 | `brreg_series(frequency="quarter"/"month")` | Different targets | nothing | OK |
| 233 | `brreg_series(from=, to=)` | Bounded | nothing | OK |
| 234 | `brreg_series(type="roller")` | Counts role rows, not entities | nothing | ⚠ D-63 |
| 235 | `brreg_series(label=TRUE, by="nace_1")` | Labels group codes | KLASS HTTP | OK |
| 236 | `brreg_series(label=TRUE, by=NULL)` | Guarded — no-op | nothing | OK |
| 237 | any | Reads each period's **entire** parquet via `read_parquet_safe` (no arrow pushdown even when arrow is present) | nothing | ⚠ **D-64** |
| 238 | any | `period` is the raw snapshot date string (`"2024-12-31"`), not a period label; `format_period()` exists and is **never called** | nothing | ⚠ **D-65** dead function + doc mismatch ("character label for the period") |

### 9.3 `brreg_events()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 239 | `brreg_events(d1, d2)` | Set-diff for entry/exit, per-column character comparison for change | nothing | OK — logic and operator precedence are correct |
| 240 | `brreg_events(d1, d2, cols=c("employees"))` | Tracks one column | nothing | OK |
| 241 | `brreg_events(d1, d2)` `cols=NULL` | ~103 columns × ~1M rows, all cast to character in R | nothing | ⚠ slow; no arrow path |
| 242 | `brreg_events(d_missing, d2)` | Abort naming the date | nothing | OK |
| 243 | `brreg_events(d2, d1)` (reversed) | Runs happily; "entry" now means "disappeared" | nothing | ⚠ no ordering check |
| 244 | `brreg_events(d1, d2, type="underenheter")` | Same | nothing | OK |
| 245 | `brreg_events(d1, d1)` | Zero events | nothing | OK |
| 246 | any | `old_common`/`new_common` aligned by **sort position**, not by join — a duplicated `org_nr` in either snapshot silently misaligns every subsequent row | nothing | ⚠ **D-66** holds today (org_nr unique) but is undefended |
| 247 | any | Returns typed empty when nothing changed | nothing | OK |

### 9.4 `as_brreg_tsibble()`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 248 | `as_brreg_tsibble(series_out)` | index `period`, key from meta, `regular=FALSE` | nothing | OK |
| 249 | `as_brreg_tsibble(panel_out)` | index `snapshot_date`, key `org_nr` — but LOCF duplicates the same snapshot across periods ⇒ **duplicate (key,index) ⇒ tsibble aborts** | nothing | ⚠ **D-67** the documented example is the failing case |
| 250 | `as_brreg_tsibble(x, key="legal_form")` | Explicit key | nothing | OK |
| 251 | `as_brreg_tsibble(x, index="period")` | Explicit index | nothing | OK |
| 252 | `as_brreg_tsibble(x)` with `period="2024"` | Regex branch → Jan 1 | nothing | dead in practice (D-65) |
| 253 | `as_brreg_tsibble(x)` with `period="2024-Q1"` | Quarter branch | nothing | dead (D-65) |
| 254 | `as_brreg_tsibble(x)` no meta, no `org_nr` | `key=NULL` → single series | nothing | OK |
| 255 | `as_brreg_tsibble(flows_out)` | meta index is `"date"` but the function only ever picks `snapshot_date` or `period` → wrong index | nothing | ⚠ **D-68** `brreg_flows` sets `brreg_panel_meta` that this function cannot honour |

---

## 10. Replay — `R/replay.R`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 256 | `brreg_replay(base, updates)` | Apply chronologically to `target_date=today` | nothing | ⚠ |
| 257 | `brreg_replay(base, updates, target_date=d)` | `as.POSIXct(as.Date(d))` = **midnight** ⇒ everything on day `d` is excluded | nothing | ⚠ **D-69** off by one day |
| 258 | `brreg_replay(base, updates_without_changes)` | `Endring` counted in `n_update` but nothing changes | nothing | ⚠ **D-70** silent no-op; `include_changes=TRUE` is required but unchecked |
| 259 | `brreg_replay(base, u, cols=c("employees"))` | Restricts tracked columns | nothing | OK |
| 260 | `brreg_replay(base, u)` `Ny` events | New row is `org_nr` + all NA (CDC carries no patches for Ny) | nothing | ⚠ documented; still emits skeleton rows into the state |
| 261 | `brreg_replay(base, u)` `Sletting`/`Fjernet` | Row removed | nothing | OK |
| 262 | `brreg_replay(base, u)` address patch | `lookup_patch_field` does `gsub("_",".")` → `forretningsadresse.adresse.0`, absent from field_dict; `to_snake` → `forretningsadresse_adresse_0`, absent from state ⇒ **NULL ⇒ dropped** | nothing | ⚠ **D-71** address and every array-valued change never replays |
| 263 | `brreg_replay(base, u)` `op="remove"` | `new_value` NA assigned → column set NA | nothing | OK by accident |
| 264 | `brreg_replay(1M_base, 100K_updates)` | Row-at-a-time `which()` over the full frame | nothing | ⚠ D-41-class |
| 265 | any | `attr(,"replay_info")` with counts | nothing | OK — good provenance |

---

## 11. Network — `R/network.R`, `R/bulk-check.R`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 266 | `brreg_network("923609016")` | depth 1: seed + underenheter + children + roles + legal_roles ⇒ 5–7+ HTTP calls; directed `tbl_graph` | nothing | OK |
| 267 | `brreg_network(x, depth=0)` | Seed node only — still 1 HTTP call | nothing | OK |
| 268 | `brreg_network(x, include="roles")` | Only role collectors | nothing | OK — the collector registry is well designed |
| 269 | `brreg_network(x, include=c("roles","legal_roles"))` | Two collectors | nothing | OK |
| 270 | `brreg_network(x, include="underenheter")` | `max_results=10000` inside | nothing | OK |
| 271 | `brreg_network(x, include="nope")` | `match.arg` aborts | nothing | OK |
| 272 | `brreg_network(c(o1,o2,o3), depth=1)` | Union graph; node dedupe by `node_id`, edges **not** deduped | nothing | OK (parallel edges are meaningful) |
| 273 | `brreg_network(x, depth=2)` with bulk present | roller → filter to seed persons → drop known orgs → early exit → enheter/underenheter name resolution | `.brregEnv$bulk_*` (Arrow Table or full tibble) | OK — the laziest path in the package |
| 274 | `brreg_network(x, depth=2)` without bulk, non-interactive | `require_bulk_data` aborts with instructions | nothing | OK |
| 275 | `brreg_network(x, depth=2, download=TRUE)` interactive | Prompts, then `brreg_snapshot()` per missing type | full snapshot side effects ×3 | ⚠ **D-72** demands all three (~342 MB) when only roller is needed for the person lookup |
| 276 | `brreg_network(x, depth=2)` no person nodes | Early exit, empty expansion | nothing | OK |
| 277 | `brreg_network(x, depth=3)` | `depth>=2L` only ⇒ silently identical to depth 2 | nothing | ⚠ no upper-bound check |
| 278 | any | Edge direction is inconsistent: person→org, org→sub, org→target | nothing | ⚠ **D-73** any centrality measure on the directed graph is meaningless |
| 279 | `brreg_status()` | Per-type availability from snapshots or cache | nothing | OK |
| 280 | `brreg_status(quiet=TRUE)` | List only | nothing | OK |
| 281 | `brreg_status("roller")` | Single type | nothing | OK |
| 282 | `brreg_status("nope")` | `match.arg` aborts | nothing | OK |
| 283 | `resolve_bulk()` via depth 2, no arrow | Loads the **full** roller tibble (~2 GB) into `.brregEnv` for the session | `.brregEnv` | ⚠ **D-74** unbounded session memory growth, never evicted |

---

## 12. Labels and harmonisation — `R/label.R`, `R/harmonize.R`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 284 | `brreg_label(entity_tbl)` | Replaces `legal_form`, `nace_1..3`, `sector_code`, `role_code`, `role_group_code` with English | `.brregEnv$nace_en`, `$sector_en`; 2 KLASS HTTP calls on first use | OK |
| 285 | `brreg_label(x, code="legal_form")` | Adds `legal_form_code` before the column | as above | ⚠ D-07 drops attributes |
| 286 | `brreg_label(x, code=c("legal_form","nace_1"))` | Two code columns | as above | OK |
| 287 | `brreg_label(x, code="employees")` | `intersect(code, labelable)` → no-op | as above | OK |
| 288 | `brreg_label(x, lang="no")` | Fetches Norwegian labels, stored in a column still named `name_en` | `.brregEnv$nace_no` | ⚠ **D-75** misleading internal naming |
| 289 | `brreg_label(c("AS","ASA"), dic="legal_form")` | Vector path | nothing (uses bundled `legal_forms`) | OK |
| 290 | `brreg_label(codes, dic="nace")` | Vector path via KLASS | `.brregEnv` | OK |
| 291 | `brreg_label(codes, dic="sector"/"role"/"role_group")` | Respective maps | `.brregEnv` | OK |
| 292 | `brreg_label(codes)` no `dic` | Abort | nothing | OK |
| 293 | `brreg_label(codes, dic="nope")` | Abort listing options | nothing | OK |
| 294 | `brreg_label(tibble())` | Early return | nothing | OK |
| 295 | any | The 40-entry `skip` denylist subtracts names that are **not in `lkp`** (which has 8 keys) ⇒ entirely dead | nothing | ⚠ **D-76** dead code implying protection that isn't operative |
| 296 | any | `nace_1_desc` is mapped through the *code* lookup — a description string is never a code ⇒ silent passthrough | nothing | ⚠ dead mapping |
| 297 | `get_brreg_dic("nace")` | KLASS classification 6 `codesAt` today; on error falls back to `nace_codes` from `R/sysdata.rda` (**present** — verified) | `.brregEnv$nace_en` | OK |
| 298 | `get_brreg_dic("sector")` | Classification 39 | `.brregEnv$sector_en` | OK |
| 299 | `get_brreg_dic("nace", lang="no")` | Separate cache key | `.brregEnv$nace_no` | OK |
| 300 | `get_brreg_dic("nace")` twice | Second is cache-only | nothing | OK; **no way to force a refresh** within a session |
| 301 | `get_brreg_dic("nope")` | `match.arg` aborts | nothing | OK |
| 302 | `.onLoad` | Overrides `nace_codes`/`sector_codes` from `R_user_dir("tidybrreg","data")/*.rds` — files **nothing in the package ever writes** | namespace bindings | ⚠ **D-77** dead path; a stale user-placed RDS would silently override bundled data |
| 303 | `brreg_harmonize_kommune(df)` | Documented: remap across the 2020 reform. Actual: `lkp_code <- setNames(corr$code, corr$code)` — an **identity map** | `.brregEnv$kommune_corr_D` | ⚠ **D-78 confirmed**: `{col}_harmonized` always equals the input; only `{col}_target_name` is new. `GetKlass(131, date=)` returns a *classification*, not a *correspondence*; old codes (the entire point) pass through with an NA name |
| 304 | `brreg_harmonize_kommune(df, target_date="2019-01-01")` | Separate cache key | `.brregEnv` | ⚠ D-78 |
| 305 | `brreg_harmonize_kommune(df, col="postal_municipality_code")` | Different column | `.brregEnv` | ⚠ D-78 |
| 306 | `brreg_harmonize_kommune(df)` when KLASS is down | `return(data)` **inside the error handler** returns from the handler, so `corr <- data`; the user's own tibble is then **cached under the date key** and returned by every later call in the session | `.brregEnv` poisoned | ⚠ **D-79 confirmed** |
| 307 | `brreg_harmonize_nace(df)` | `GetKlass(klass=6, correspond=274)`; target column taken **positionally** as `names(corr)[2]` | `.brregEnv$nace_corr_SN2007_SN2025` | ⚠ **D-80** *inferred*: klassR correspondence output is `sourceCode, sourceName, targetCode, targetName`, so position 2 is the **source name**, and `{col}_harmonized` would receive a Norwegian description |
| 308 | `brreg_harmonize_nace(df, from="SN2025", to="SN2007")` | Reverse ids | `.brregEnv` | ⚠ D-80 |
| 309 | `brreg_harmonize_nace(df, from="SN1994")` | `klass_ids["SN1994"]` NA → abort | nothing | OK |
| 310 | `brreg_harmonize_nace(df, col="nace_2")` | Different column | `.brregEnv` | ⚠ D-80 |
| 311 | `brreg_harmonize_nace(df)` one-to-many | `{col}_ambiguous=TRUE`, first match used | `.brregEnv` | OK — the flag is the right design |
| 312 | `brreg_harmonize_nace(df)` KLASS down | Same handler bug as #306 | `.brregEnv` poisoned | ⚠ D-79 |

---

## 13. Annotations and name history — `R/annotations.R`, `R/historical-names.R`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 313 | `brreg_annotations()` | Reads `paategninger` state (session-cached) | `.brregEnv$state_paategninger` | OK |
| 314 | `brreg_annotations(org_nr=x)` | Filter | as above | OK |
| 315 | `brreg_annotations(infotype="FADR")` | Filter | as above | OK |
| 316 | `brreg_annotations(active_only=FALSE)` | Documented: include cleared annotations from the changelog. Actual: **the argument is never referenced in the body** | as above | ⚠ **D-81 confirmed** dead parameter |
| 317 | `brreg_annotations(translate=TRUE)` | Adds `infotype_desc` after `infotype` | as above | OK |
| 318 | `brreg_annotations()` before sync | Warn + typed empty | nothing | OK |
| 319 | `brreg_annotation_summary()` | `infotype`, `n_entities`, `n_annotations` | `.brregEnv` | ⚠ docs promise `infotype` and `n` |
| 320 | `brreg_annotation_summary()` before sync | Warn + typed empty | nothing | OK |
| 321 | `brreg_historical_names()` | Reads `historiske_navn` state | `.brregEnv` | OK |
| 322 | `brreg_historical_names("923609016")` | Filter | as above | OK |
| 323 | `brreg_historical_names()` after a csv bootstrap | Empty until renames accrue via CDC | nothing | OK — documented clearly |

---

## 14. Roller diff — `R/roller-diff.R`

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 324 | `diff_roller_state(old, new)` | Key `(org_nr, role_group_code, role_code, holder_id)`; entry/exit/change rows in changelog schema | nothing | OK — the cleanest algorithm in the package |
| 325 | `diff_roller_state(NULL, new)` | All roles as `entry` | nothing | OK |
| 326 | `diff_roller_state(tibble(), new)` | Same | nothing | OK |
| 327 | `diff_roller_state(old, tibble())` | `add_role_key` handles 0 rows; everything `exit` | nothing | OK |
| 328 | `diff_roller_state(old, new, timestamp=t)` | Passthrough, cast to character | nothing | OK |
| 329 | `diff_roller_state(old, new, update_id="batch-7")` | Docs say "Integer or character"; `as.integer("batch-7")` → **NA + warning** | nothing | ⚠ **D-82** doc/impl mismatch |
| 330 | `diff_roller_state(legacy_state, new)` | `backfill_roller_cols` adds the four post-0.3.4 columns | nothing | OK — good compatibility handling |
| 331 | `diff_roller_state(old_with_resigned, new_without)` | `intersect` of present columns ⇒ diffs cleanly | nothing | OK — the 0.5.0 claim holds |
| 332 | any | `tidyr::pivot_longer` called with **no `check_installed`**, and tidyr is only in Suggests ⇒ an exported function fails on a minimal install | nothing | ⚠ **D-83 confirmed** |
| 333 | any | `distinct(role_key, .keep_all=TRUE)` silently drops genuine duplicate role rows | nothing | ⚠ documented as conservative, but it is a real erasure |
| 334 | any | `birth_date` is in the key but **not** in `value_cols` ⇒ a birth-date correction produces an exit+entry pair, never a `change` | nothing | ⚠ acceptable, undocumented |

---

## 15. Utilities

| # | Call | Expected behaviour | Persists | Verdict |
|---|---|---|---|---|
| 335 | `brreg_validate("923609016")` | TRUE | nothing | OK |
| 336 | `brreg_validate(c("923609016","123456789"))` | Vectorised, `c(TRUE, FALSE)` | nothing | OK |
| 337 | `brreg_validate("12345678")` | FALSE (length) | nothing | OK |
| 338 | `brreg_validate("999999999")` | FALSE (check digit → 10) | nothing | OK |
| 339 | `brreg_validate(NA)` | `"NA"` → FALSE | nothing | OK |
| 340 | `brreg_validate(923609016)` | Numeric coerced | nothing | OK |
| 341 | `brreg_validate("312345678")` | FALSE by the `^[89]` prefix rule even if mod-11 passes | nothing | ⚠ **D-02** the 8/9 prefix is an allocation convention, not a statutory invariant; when the series is exhausted this rejects valid numbers, and `brreg_entity` inherits the rejection |

---

## 16. Defect register

Severity: **S1** wrong results silently · **S2** fails or misleads under a common path · **S3** performance/usability · **S4** doc/hygiene.

| ID | Sev | Defect | Evidence |
|---|---|---|---|
| D-01 | S2 | `brreg_entity` returns a 4-column tibble on HTTP 410 | verified-from-code |
| D-02 | S2 | `brreg_validate` hardcodes the `^[89]` prefix | verified-from-code |
| D-03 | S1 | `brreg_entity` is not vectorised and does not guard against it | verified-from-code |
| D-04 | S4 | `bankrupt` silently dropped for underenheter | verified-from-code |
| D-05 | S2 | Six functions return a **zero-column** `tibble()` on empty | verified-from-code |
| D-06 | S1 | HTTP ≥400 mid-pagination `break`s and returns partial results with no signal | verified-from-code |
| D-07 | S3 | `brreg_label(code=)` drops `total_matches` | verified-from-code |
| D-08 | S3 | `max_results=200` default silently truncates children/sub-units | verified-from-code |
| D-09 | S1 | `resigned` present or absent depending on payload content | verified-from-code |
| D-10 | S2 | `brreg_roles` collapses 410 into "no roles" | verified-from-code |
| D-11 | S4 | `type="label"` silently issues SSB KLASS calls | verified-from-code |
| D-12 | S1 | `brreg_board_summary` on multi-org input returns plausible garbage | verified-from-code |
| D-13 | S1 | `n_employee_elected` counts any `valgtAv` | verified-from-code |
| D-16 | S3 | 404-on-normal-case warnings (konsern, signatur, prokura) | verified-from-code |
| D-17 | S2 | `flatten_konsern` parses `dato` with no format | inferred |
| D-18 | S1 | Fullmakt `birth_date` parsed `%d.%m.%Y` vs roles' ISO | inferred |
| D-19 | S1 | `brreg_board_network` labels entity nodes with the auditor's name | verified-from-code |
| D-20 | S1 | `brreg_survival_data` defaults to `founding_date` and inherits survivorship bias unwarned | verified-from-code |
| D-22 | S2 | `refresh="auto"` never fires without a prior etag file or a server ETag | verified-from-code |
| D-23 | S4 | `refresh` not validated | verified-from-code |
| D-24 | S2 | `cache=FALSE` still writes the payload | verified-from-code |
| D-25 | S1 | `type_output="arrow"` returns unrenamed, uncoerced columns | verified-from-code |
| D-26 | S3 | underenheter output carries ~40 all-NA enheter-only columns | verified-from-code |
| D-27 | S2 | >20 integer parse failures in one column abort the parse (vctrs recycling) | verified-from-code |
| D-28 | S1 | `", "` vs `"; "` separators between the entity and bulk paths | verified-from-code |
| D-29 | S1 | snake_case collisions silently drop the second field | verified-from-code |
| D-30 | S2 | `brreg_updates()` default returns ≤100 events | verified-from-code |
| D-31 | S1 | `since` time-of-day discarded; tz-dependent date shift | verified-from-code |
| D-32 | S2 | `type="roller"` ignores `max_pages`, `include_changes`, `verbose` | verified-from-code |
| D-33 | S1 | All timestamps parsed tz-naive as local | verified-from-code |
| D-34 | S2 | `flatten_page_patches` breaks on 3-level nesting; disagrees with `parse_patch` | inferred |
| D-35 | S3 | csv bootstrap fetches påtegninger one entity at a time at 5 req/s | verified-from-code |
| D-36 | S1 | Bootstrap loses every event between the bulk download and the tip query | verified-from-code |
| D-37 | S2 | Empty feed at bootstrap leaves the cursor at 0 → history replay | verified-from-code |
| D-38 | S1 | Multi-type sync **loses** the first type's `historiske_navn` writes | verified-from-code |
| D-39 | S3 | Bulk roller sync re-downloads 131 MB whenever any role event exists | verified-from-code |
| D-40 | S1 | Roller bulk changelog timestamps are fabricated for the residual set | verified-from-code |
| D-41 | S3 | `apply_ny_events`/`apply_endring_events` are O(events × rows) with full copies | verified-from-code |
| D-42 | S1 | Unmapped CDC fields silently dropped by `find_state_column` | verified-from-code |
| D-43 | S1 | `Sletting` deletes the org's påtegninger and name history | verified-from-code |
| D-44 | S1 | Påtegning appliers are not idempotent, so the documented crash-replay duplicates rows | verified-from-code |
| D-45 | S4 | `%||%` does not catch `NA_character_` in the status line | verified-from-code |
| D-46 | S2 | Date-vs-string partition filter under arrow | inferred |
| D-47 | S1 | Changelog schema differs by backend (`sync_date` column) | verified-from-code |
| D-48 | S2 | `track=` keeps NA-field rows | verified-from-code |
| D-49 | S1 | Changelog date filters operate on partition date, not event time | verified-from-code |
| D-50 | S1 | `brreg_flows` exits always join to NA because exited orgs were deleted from state | verified-from-code |
| D-51 | S1 | Historical entries carry present-day attributes | verified-from-code |
| D-52 | S1 | Bulk-path entry counts are survivor-filtered | verified-from-code |
| D-53 | S2 | `legal_form`/`updates` silently ignored on the changelog path | verified-from-code |
| D-54 | S2 | Raw `.gz` copied **inside** the arrow dataset root | inferred, high probability |
| D-55 | S4 | Manifest ids are not unique under `force=TRUE` | verified-from-code |
| D-56 | S4 | `brreg_import` writes no manifest entry | verified-from-code |
| D-57 | S2 | `brreg_import(type="roller")` parses JSON as CSV | verified-from-code |
| D-58 | S4 | `brreg_cleanup` leaves dangling manifest entries | verified-from-code |
| D-59 | S2 | `brreg_manifest()` infinitely recurses on an empty `downloads` array | verified-from-code |
| D-60 | S1 | `is_entry`/`is_exit` are censoring artifacts, not events | verified-from-code |
| D-61 | S3 | `select_cols` dead; no projection pushdown in `brreg_panel` | verified-from-code |
| D-62 | S2 | `max_gap` is a no-op for `frequency="custom"` | verified-from-code |
| D-63 | S2 | `type="roller"` accepted by panel/series where the grain is wrong | verified-from-code |
| D-64 | S3 | `brreg_series` never uses arrow | verified-from-code |
| D-65 | S4 | `format_period()` dead; `period` is a date string | verified-from-code |
| D-66 | S1 | `brreg_events` aligns snapshots positionally | verified-from-code |
| D-67 | S2 | `as_brreg_tsibble(brreg_panel())` — the documented example — hits duplicate keys | inferred |
| D-68 | S2 | `as_brreg_tsibble` cannot honour `brreg_flows`' own meta index | verified-from-code |
| D-69 | S2 | `brreg_replay` excludes the whole target day | verified-from-code |
| D-70 | S2 | Replay without `include_changes` silently no-ops | verified-from-code |
| D-71 | S1 | Address/array patches never replay | verified-from-code |
| D-72 | S3 | Depth-2 demands all three bulks (~342 MB) | verified-from-code |
| D-73 | S1 | Mixed edge direction in a directed graph | verified-from-code |
| D-74 | S3 | `.brregEnv` bulk cache never evicted | verified-from-code |
| D-75 | S4 | `lang="no"` labels stored in a `name_en` column | verified-from-code |
| D-76 | S4 | 40-entry `skip` denylist is dead | verified-from-code |
| D-77 | S4 | `.onLoad` RDS override path is dead | verified-from-code |
| D-78 | S1 | **`brreg_harmonize_kommune` does not harmonise** — identity map | verified-from-code |
| D-79 | S1 | `return()` inside the KLASS error handler poisons the session cache | verified-from-code |
| D-80 | S1 | `brreg_harmonize_nace` takes the target column positionally | inferred |
| D-81 | S1 | `active_only` is a dead parameter | verified-from-code |
| D-82 | S4 | `update_id` character promised, `as.integer` applied | verified-from-code |
| D-83 | S2 | `diff_roller_state` uses tidyr (Suggests) with no `check_installed` | verified-from-code |

Counts: **S1 = 32**, **S2 = 24**, **S3 = 11**, **S4 = 12** across 79 registered defects.

---

## 17. The three defects worth fixing first

1. **D-78 / D-79 — harmonisation is not implemented.** Both `brreg_harmonize_*` functions
   claim to remap codes across reforms. `brreg_harmonize_kommune` builds an identity map
   from a classification, not a correspondence, so the 2020 reform codes it exists to
   handle pass through unchanged with an NA name. Both then poison the session cache on
   KLASS failure. Two functions with a stated purpose neither performs.
2. **D-50 / D-51 / D-52 — every `brreg_flows` path is biased.** The changelog path joins
   exits to a state table from which those exits have already been deleted, so exits carry
   NA keys and never offset entries; the bulk path counts registrations of survivors only.
   `net` is the headline column and it is wrong on all three paths.
3. **D-38 / D-43 / D-36 — the sync engine loses observations.** A two-type sync drops the
   first type's name history; deletion erases påtegninger and name history; bootstrap has
   an unbounded blind window. Given the platform's premise that population certainty is
   paramount, a mirror that silently loses rows is worse than no mirror.

## 18. What is genuinely well built

`brreg_konsern`'s recursive flatten with observed-wins-over-derived precedence;
`diff_roller_state`'s composite key and the `backfill_roller_cols` compatibility shim;
the `read_roles_json` yyjsonr/jsonlite dispatch; `flatten_page_patches`' synthetic NA row
for patch-less events; RFC 6902 `move` emitting both destination and source rows;
`brreg_signatur`'s RF/RI documentation, which is more precise than BRREG's own;
`brreg_network`'s collector registry and lazy depth-2 pipeline; `extract_entity_name`'s
parser-agnostic handling; the zero-drop passthrough policy in `rename_from_dict`; and the
typed empty returns in `brreg_update_fields`, `brreg_snapshots`, and `empty_changelog`.

---

## 19. Insight tracking

**old → new**: "tidybrreg is a typed API client with CDC primitives" → "tidybrreg is a
typed API client with **three uncoordinated persistence stores** and an analytics layer
whose derived quantities (`net`, `is_entry`, `is_exit`, `event`, `*_harmonized`) are
mostly artifacts" *because* the analytics functions derive events from state that the sync
engine has already mutated, and the harmonisation functions never received their
correspondence tables. **Invalidates** the assumption that a passing test suite over 29
files implies the derived columns are meaningful — the tests exercise parsing and schema,
not analytic identities. **Relies on** the code at `316610b` being what is installed from
r-universe. **May be true because** D-78, D-81, D-50 and D-38 are each readable directly
from a single function body. **May be wrong because** three of the sharpest claims (D-54
arrow-reads-raw-gz, D-67 tsibble duplicate keys, D-80 klassR column order) are *inferred*
from dependency behaviour I could not execute here; each is a five-minute empirical check.

**Counterpoints to hold**

- The defect count is inflated by counting each `tibble()` empty return and each silent
  `break` separately. Collapsed by root cause there are roughly six: no empty-schema
  contract, no error contract, no persistence transaction, hand-maintained field maps,
  no arrow pushdown discipline, and derived analytics computed from mutated state.
- Several S1s are only S1 for the analytic layer, which the platform does not use — the
  Registrum pipelines take enheter/roller/underenheter through Python+DuckDB and use
  tidybrreg for ad-hoc lookup and entity resolution. On the paths the platform actually
  exercises (`brreg_entity`, `brreg_roles`, `brreg_search`, `brreg_updates`) the defect
  density is markedly lower, and D-09/D-33 are the two that reach it.
- "The function does nothing" (D-78, D-81) is the strongest possible reading. The weaker
  reading is that these are partial implementations awaiting the correspondence-table and
  changelog-join work, and the roxygen was written to the intent rather than the state.
  The observable behaviour is identical either way, which is why it is registered as S1.
