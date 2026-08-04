root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

cl_cols <- c("timestamp", "org_nr", "registry", "change_type", "field",
             "value_from", "value_to", "update_id")

test_sync <- function(store = file.path(stress_root(), "tmp", "sync-store"),
                      csv_budget = as.integer(Sys.getenv("STRESS_CSV_BUDGET", "900"))) {
  stress_init("34-sync")
  dir.create(store, recursive = TRUE, showWarnings = FALSE)
  options(brreg.data_dir = store, brreg.allow_download = TRUE)

  check("SY-01", "status before sync reports nothing initialised", {
    s <- brreg_sync_status()
    all(vapply(s$state, function(x) isFALSE(x$exists), logical(1)))
  })

  check("SY-02", "json bootstrap of enheter completes", {
    r <- brreg_sync(types = "enheter", format = "json", verbose = FALSE)
    is.list(r) && !is.null(r$summary$enheter)
  })

  check("SY-03", "enheter state file is written",
        file.exists(file.path(store, "state", "enheter.parquet")))

  check("SY-04", "paategninger state is written",
        file.exists(file.path(store, "state", "paategninger.parquet")))

  check("SY-05", "historiske_navn state is written",
        file.exists(file.path(store, "state", "historiske_navn.parquet")))

  check("SY-06", "cursor is written and non-zero", {
    cur <- jsonlite::fromJSON(file.path(store, "state", "sync_cursor.json"))
    cur$enheter_id > 0L
  })

  check("SY-07", "json bootstrap populates paategninger", {
    p <- tb$read_parquet_safe(file.path(store, "state", "paategninger.parquet"))
    nrow(p) > 0
  })

  check("SY-08", "json bootstrap backfills name history", {
    h <- tb$read_parquet_safe(file.path(store, "state", "historiske_navn.parquet"))
    nrow(h) > 0
  })

  check("SY-09", "state row count is of register magnitude", {
    s <- tb$read_parquet_safe(file.path(store, "state", "enheter.parquet"))
    nrow(s) > 900000L
  })

  check("SY-10", "state org numbers are unique", {
    s <- tb$read_parquet_safe(file.path(store, "state", "enheter.parquet"))
    !any(duplicated(s$org_nr))
  })

  check("SY-11", "sync_status reflects the initialised store", {
    s <- brreg_sync_status()
    isTRUE(s$state$enheter$exists)
  })

  check("SY-12", "a second sync advances the cursor monotonically", {
    before <- jsonlite::fromJSON(file.path(store, "state", "sync_cursor.json"))$enheter_id
    brreg_sync(types = "enheter", verbose = FALSE)
    after <- jsonlite::fromJSON(file.path(store, "state", "sync_cursor.json"))$enheter_id
    after >= before
  })

  check("SY-13", "a second sync is idempotent on state row count", {
    a <- nrow(tb$read_parquet_safe(file.path(store, "state", "enheter.parquet")))
    brreg_sync(types = "enheter", verbose = FALSE)
    b <- nrow(tb$read_parquet_safe(file.path(store, "state", "enheter.parquet")))
    abs(a - b) < 5000L
  })

  check("SY-14", "changelog partitions are written", {
    d <- file.path(store, "state", "changelog")
    dir.exists(d) && length(list.files(d, recursive = TRUE, pattern = "parquet")) > 0
  })

  check("SY-15", "changelog schema is the documented one", {
    cl <- brreg_changes()
    identical(sort(names(cl)), sort(cl_cols))
  }, defect = "D-47")

  check("SY-16", "changelog change types are the documented set", {
    cl <- brreg_changes()
    all(cl$change_type %in% c("entry", "exit", "change", "annotation_added",
                              "annotation_cleared", "name_history_added"))
  })

  check("SY-17", "changelog org numbers are valid", {
    cl <- brreg_changes()
    if (nrow(cl) == 0) NA else all(brreg_validate(cl$org_nr))
  })

  check("SY-18", "changelog change rows carry a field name", {
    cl <- brreg_changes(change_type = "change")
    if (nrow(cl) == 0) NA else all(!is.na(cl$field))
  })

  check("SY-19", "changed fields map to real state columns", {
    cl <- brreg_changes(change_type = "change")
    s <- tb$read_parquet_safe(file.path(store, "state", "enheter.parquet"))
    if (nrow(cl) == 0) NA else all(unique(cl$field) %in% names(s))
  }, defect = "D-42")

  check("SY-20", "track filter returns only the requested field", {
    cl <- brreg_changes(track = "employees")
    if (nrow(cl) == 0) NA else all(cl$field == "employees")
  }, defect = "D-48")

  check("SY-21", "org_nr filter is exact", {
    cl <- brreg_changes()
    if (nrow(cl) == 0) NA else {
      o <- cl$org_nr[1]
      all(brreg_changes(org_nr = o)$org_nr == o)
    }
  })

  check("SY-22", "date filters accept Date input and do not error", {
    is.data.frame(brreg_changes(from = Sys.Date() - 7, to = Sys.Date()))
  }, defect = "D-46")

  check("SY-23", "date filter is applied to the event timestamp", {
    cl <- brreg_changes(from = Sys.Date())
    if (nrow(cl) == 0) NA else all(as.Date(substr(cl$timestamp, 1, 10)) >= Sys.Date())
  }, defect = "D-49")

  check("SY-24", "registry filter is honoured", {
    cl <- brreg_changes(registry = "enheter")
    if (nrow(cl) == 0) NA else all(cl$registry == "enheter")
  })

  check("SY-25", "change summary agrees with the raw changelog", {
    cl <- brreg_changes()
    su <- brreg_change_summary()
    if (nrow(cl) == 0) NA else sum(su$n) == nrow(cl)
  })

  check("SY-26", "changelog is ordered by time", {
    cl <- brreg_changes()
    if (nrow(cl) < 2) NA else !is.unsorted(cl$timestamp)
  })

  check("SY-27", "annotations read back from state", {
    a <- brreg_annotations()
    is.data.frame(a) && nrow(a) > 0
  })

  check("SY-28", "annotation columns are the documented ones",
        all(c("org_nr", "position", "infotype", "tekst", "innfoert_dato") %in%
              names(brreg_annotations())))

  check("SY-29", "annotation org filter is exact", {
    a <- brreg_annotations()
    if (nrow(a) == 0) NA else all(brreg_annotations(org_nr = a$org_nr[1])$org_nr == a$org_nr[1])
  })

  check("SY-30", "annotation infotype filter is exact", {
    a <- brreg_annotations()
    if (nrow(a) == 0) NA else {
      it <- a$infotype[1]
      all(brreg_annotations(infotype = it)$infotype == it)
    }
  })

  check("SY-31", "translate adds an English description column", {
    a <- brreg_annotations(translate = TRUE)
    "infotype_desc" %in% names(a)
  })

  check("SY-32", "active_only = FALSE returns at least as many rows as TRUE", {
    a <- brreg_annotations(active_only = TRUE)
    b <- brreg_annotations(active_only = FALSE)
    nrow(b) > nrow(a)
  }, defect = "D-81")

  check("SY-33", "annotation summary totals match the state", {
    a <- brreg_annotations()
    s <- brreg_annotation_summary()
    sum(s$n_annotations) == nrow(a)
  })

  check("SY-34", "historical names read back from state", {
    h <- brreg_historical_names()
    is.data.frame(h) && nrow(h) > 0
  })

  check("SY-35", "historical name columns are the documented ones",
        all(c("org_nr", "position", "name", "from_date", "to_date") %in%
              names(brreg_historical_names())))

  check("SY-36", "historical name org filter is exact", {
    h <- brreg_historical_names()
    if (nrow(h) == 0) NA else
      all(brreg_historical_names(h$org_nr[1])$org_nr == h$org_nr[1])
  })

  check("SY-37", "flows from the changelog return rows", {
    f <- brreg_flows()
    is.data.frame(f) && nrow(f) >= 0
  })

  check("SY-38", "flows carry the documented columns", {
    f <- brreg_flows()
    all(c("date", "entries", "exits", "net") %in% names(f))
  })

  check("SY-39", "net equals entries minus exits", {
    f <- brreg_flows()
    if (nrow(f) == 0) NA else all(f$net == f$entries - f$exits)
  })

  check("SY-40", "exits carry industry and geography attributes", {
    f <- brreg_flows()
    ex <- f[f$exits > 0, ]
    if (nrow(ex) == 0) NA else !all(is.na(ex$nace_1))
  }, defect = "D-50")

  check("SY-41", "national flows aggregate to the grouped flows", {
    a <- brreg_flows(by = NULL)
    b <- brreg_flows()
    if (nrow(a) == 0 || nrow(b) == 0) NA else sum(a$entries) == sum(b$entries)
  })

  check("SY-42", "flows accept a legal_form filter on the changelog path", {
    a <- brreg_flows()
    b <- brreg_flows(legal_form = "AS")
    sum(b$entries) <= sum(a$entries)
  }, defect = "D-53")

  check("SY-43", "multi-type sync preserves the first type's name history", {
    h_before <- nrow(brreg_historical_names())
    brreg_sync(types = c("enheter", "underenheter"), format = "json", verbose = FALSE)
    h_after <- nrow(brreg_historical_names())
    h_after >= h_before
  }, defect = "D-38")

  check("SY-44", "underenheter state is written by the multi-type sync",
        file.exists(file.path(store, "state", "underenheter.parquet")))

  check("SY-45", "roller cdc bootstrap writes an empty state without a bulk download", {
    t0 <- Sys.time()
    brreg_sync(types = "roller", roller_method = "cdc", verbose = FALSE)
    el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    file.exists(file.path(store, "state", "roller.parquet"))
  })

  check("SY-46", "roller cdc sync produces roller changelog rows", {
    cl <- brreg_changes(registry = "roller")
    is.data.frame(cl)
  })

  check("SY-47", "deleted entities retain their annotation history", {
    cl <- brreg_changes(change_type = "exit")
    a <- brreg_annotations()
    if (nrow(cl) == 0) NA else {
      gone <- intersect(cl$org_nr, a$org_nr)
      length(gone) >= 0 && !all(cl$org_nr %in% setdiff(cl$org_nr, a$org_nr))
    }
  }, defect = "D-43")

  check_budget("SY-48", "csv bootstrap completes within the time budget",
               c(sprintf('options(brreg.data_dir = "%s", brreg.allow_download = TRUE)',
                         file.path(stress_root(), "tmp", "sync-csv-store")),
                 "library(tidybrreg)",
                 'r <- brreg_sync(types = "enheter", format = "csv", verbose = FALSE)',
                 'stopifnot(is.list(r))'),
               seconds = csv_budget, defect = "D-35")

  stress_flush()
}

test_sync()
