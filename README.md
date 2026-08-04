# tidybrreg-stresstest

Adversarial conformance suite for [tidybrreg](https://github.com/sondreskarsten/tidybrreg),
the R interface to Norway's Enhetsregisteret.

Every check asserts what a **correct** package would return. Checks are not written to the
package's current behaviour, so a check that fails is either a confirmed defect or a
regression. Each check optionally carries a `defect` tag (`D-xx`) drawn from a prior static
evaluation of tidybrreg 0.5.0; the runner then separates four outcomes:

| Outcome | Meaning |
|---|---|
| `pass` | correct behaviour, no defect predicted |
| `defect_confirmed` | failed, and a defect was predicted here |
| `pass_unexpected` | a predicted defect did **not** reproduce — the prediction was wrong or the defect is fixed |
| `regression` | failed with no defect predicted — the interesting column |

## Layout

```
setup.sh                 r2u bootstrap + apt binaries + install.R
install.R                installs tidybrreg from r-universe, captures the environment
run_all.R                tiered parallel driver and result aggregation
R/helpers.R              check recorders, subprocess and time-budget probes
R/payloads.R             synthetic API payload builders for offline internals testing
tests/                   one file per domain, each independently runnable
results/                 per-file rds + csv, aggregated summary, logs
```

## Running

```bash
bash setup.sh
Rscript run_all.R                      # everything
Rscript run_all.R 12-entity.R          # one file
Rscript run_all.R summarise            # re-aggregate existing results
```

Environment knobs:

| Variable | Default | Effect |
|---|---|---|
| `STRESS_CORES` | cores − 1 | parallelism within a tier |
| `STRESS_ROLLER` | `1` | download and parse the 131 MB roller totalbestand |
| `STRESS_JSON` | `1` | download the JSON bulk in addition to CSV |
| `STRESS_SAMPLE_ROWS` | `50000` | rows sampled into the synthetic snapshot store |
| `STRESS_CSV_BUDGET` | `900` | seconds allowed for a CSV-format `brreg_sync()` bootstrap |
| `STRESS_REPLAY_ROWS` | `200000` | base rows for replay tests |

## Tiers and isolation

Parallelism is tiered because the three persistence stores in tidybrreg (download cache,
snapshot store, sync state) are not concurrency-safe.

| Tier | Files | Concurrency | Why |
|---|---|---|---|
| 0 | `00-fixtures.R` | serial | discovers live org numbers every other file depends on |
| 1 | `10`–`21` | parallel | offline internals and light API calls |
| 2 | `30-bulk-prewarm.R` | serial | single writer of the shared download cache; builds a deterministic snapshot store |
| 3 | `31`–`35` | parallel | read the warm cache, write to their own state directories |

Each worker gets its own `R_USER_DATA_DIR` and a shared `R_USER_CACHE_DIR`, so snapshot and
sync state never collide while the 340 MB of bulk payloads is downloaded exactly once.
tidybrreg throttles at 5 req/s per process, so aggregate request rate scales with
`STRESS_CORES`; keep it modest against a public register.

## What is stressed

- **Schema contracts** — every function that can return an empty result is checked for a
  *typed* empty rather than a zero-column `tibble()`; every function whose output columns
  could vary with payload content is checked for invariance across entities.
- **Round trips** — search vs entity, roles vs signatur, konsern vs `in_corporate_group`,
  events vs set difference, series vs panel counts, replay vs live lookup.
- **Algebraic properties** — diff antisymmetry, entry/exit disjointness, `net = entries −
  exits`, board counts summing to board size, idempotence of labelling, harmonisation and
  replay.
- **Internals against synthetic payloads** — patch flatteners at nesting depth 3, integer
  parse failure counts either side of 20, separator agreement between the entity and bulk
  paths, `fratraadt` present and absent, dotted vs ISO dates, oversized role groups.
- **Persistence and isolation** — atomic parquet writes, manifest uniqueness and pruning,
  what actually lands in the snapshot store directory, cursor monotonicity, multi-type
  sync interaction.
- **Failure containment** — probes that could hang or overflow the stack run in
  subprocesses with timeouts (`check_subprocess`, `check_budget`), so one pathological
  path cannot take down a worker.

## Data source

All register data is Brønnøysund Register Centre content under NLOD 2.0. This repository
contains no register data, only code that fetches it.
