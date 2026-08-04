root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

prewarm <- function(store = Sys.getenv("STRESS_SHARED_STORE",
                                       file.path(stress_root(), "tmp", "shared-store")),
                    sample_rows = as.integer(Sys.getenv("STRESS_SAMPLE_ROWS", "50000")),
                    do_roller = identical(Sys.getenv("STRESS_ROLLER", "1"), "1"),
                    do_json = identical(Sys.getenv("STRESS_JSON", "1"), "1"),
                    dates = Sys.Date() - c(400L, 200L, 30L, 0L)) {
  stress_init("30-bulk-prewarm")
  dir.create(store, recursive = TRUE, showWarnings = FALSE)
  options(brreg.data_dir = store, brreg.allow_download = TRUE)

  paths <- new.env(parent = emptyenv())

  check("BW-01", "enheter csv bulk downloads", {
    p <- brreg_download("enheter", format = "csv", type_output = "path")
    paths$enheter_csv <- p
    file.exists(p) && file.size(p) > 10e6
  })

  check("BW-02", "underenheter csv bulk downloads", {
    p <- brreg_download("underenheter", format = "csv", type_output = "path")
    paths$underenheter_csv <- p
    file.exists(p) && file.size(p) > 1e6
  })

  check("BW-03", "enheter json bulk downloads", {
    if (!do_json) NA else {
      p <- brreg_download("enheter", format = "json", type_output = "path")
      paths$enheter_json <- p
      file.exists(p) && file.size(p) > 10e6
    }
  })

  check("BW-04", "roller json bulk downloads", {
    if (!do_roller) NA else {
      p <- brreg_download("roller", type_output = "path")
      paths$roller_json <- p
      file.exists(p) && file.size(p) > 10e6
    }
  })

  check("BW-05", "cached second call performs no download", {
    t1 <- system.time(brreg_download("enheter", type_output = "path"))[["elapsed"]]
    t1 < 10
  })

  check("BW-06", "sampled enheter parse succeeds", {
    paths$base <- tb$parse_bulk_csv(paths$enheter_csv, n_max = sample_rows)
    is.data.frame(paths$base) && nrow(paths$base) > 1000L && "org_nr" %in% names(paths$base)
  })

  check("BW-07", "snapshot store partitions are written", {
    ok <- TRUE
    for (i in seq_along(dates)) {
      d <- paths$base
      n <- nrow(d)
      keep <- seq_len(n - (length(dates) - i) * 25L)
      d <- d[keep, , drop = FALSE]
      if (i > 1L) {
        idx <- seq_len(min(500L, nrow(d)))
        d$employees[idx] <- as.integer(d$employees[idx] %in% NA) + i * 10L
        d$municipality_code[idx] <- sprintf("%04d", 300 + i)
        d$nace_1[idx] <- if (i %% 2 == 0) "62.010" else "64.190"
      }
      p <- file.path(store, "enheter", paste0("snapshot_date=", dates[i]), "data.parquet")
      tb$write_parquet_safe(d, p)
      ok <- ok && file.exists(p)
    }
    ok
  })

  check("BW-08", "snapshot store lists every partition",
        nrow(brreg_snapshots()) == length(dates))

  check("BW-09", "snapshot dates round trip",
        identical(sort(brreg_snapshots()$snapshot_date), sort(as.Date(dates))))

  check("BW-10", "arrow can open the constructed store", {
    if (!requireNamespace("arrow", quietly = TRUE)) NA else {
      ds <- brreg_open()
      inherits(ds, "Dataset")
    }
  })

  check("BW-11", "underenheter store is written for cross-type tests", {
    u <- tb$parse_bulk_csv(paths$underenheter_csv, n_max = min(sample_rows, 20000L))
    p1 <- file.path(store, "underenheter", paste0("snapshot_date=", dates[1]), "data.parquet")
    p2 <- file.path(store, "underenheter", paste0("snapshot_date=", dates[length(dates)]),
                    "data.parquet")
    tb$write_parquet_safe(u, p1)
    tb$write_parquet_safe(u[seq_len(nrow(u) - 10L), ], p2)
    file.exists(p1) && file.exists(p2)
  })

  saveRDS(list(paths = as.list(paths)[setdiff(ls(paths), "base")], store = store, dates = dates,
               sample_rows = sample_rows,
               cache_dir = tools::R_user_dir("tidybrreg", "cache")),
          file.path(stress_results_dir(), "prewarm.rds"))

  stress_flush()
}

prewarm()
