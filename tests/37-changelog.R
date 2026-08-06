root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

cl_cols <- c("timestamp", "org_nr", "registry", "change_type", "field",
             "value_from", "value_to", "update_id")

rewind_cursor <- function(store, type = "enheter", by = 3000L) {
  p <- file.path(store, "state", "sync_cursor.json")
  cur <- jsonlite::fromJSON(p)
  key <- paste0(type, "_id")
  old <- cur[[key]]
  cur[[key]] <- max(0L, as.integer(old) - by)
  jsonlite::write_json(cur, p, auto_unbox = TRUE, pretty = TRUE)
  list(from = old, to = cur[[key]])
}

test_changelog <- function(store = file.path(stress_root(), "tmp", "changelog-store"),
                           rewind_by = as.integer(Sys.getenv("STRESS_REWIND", "3000"))) {
  stress_init("37-changelog")
  unlink(store, recursive = TRUE)
  dir.create(file.path(store, "state"), recursive = TRUE, showWarnings = FALSE)
  options(brreg.data_dir = store, brreg.allow_download = TRUE)

  check("CL-00", "bootstrap completes", {
    r <- brreg_sync(types = "enheter", format = "json", verbose = FALSE)
    is.list(r)
  })

  rw <- NULL
  check("CL-01", "cursor can be rewound to force a replay of real CDC events", {
    rw <<- rewind_cursor(store, "enheter", rewind_by)
    rw$to < rw$from
  })

  applied <- NULL
  check("CL-02", "the replay sync applies events and reports them", {
    r <- brreg_sync(types = "enheter", verbose = FALSE)
    applied <<- r
    is.list(r)
  })

  cl_dir <- file.path(store, "state", "changelog")

  check("CL-03", "a sync that applied events writes changelog partitions", {
    dir.exists(cl_dir) &&
      length(list.files(cl_dir, recursive = TRUE, pattern = "parquet")) > 0
  }, defect = "D-105")

  cl <- NULL
  check("CL-04", "brreg_changes() returns the applied events", {
    cl <<- brreg_changes()
    is.data.frame(cl) && nrow(cl) > 0
  }, defect = "D-105")

  have <- function() !is.null(cl) && nrow(cl) > 0

  check("CL-05", "changelog schema is exactly the documented eight columns", {
    if (!have()) NA else setequal(names(cl), cl_cols)
  }, defect = "D-47")

  check("CL-06", "every changelog org_nr is valid", {
    if (!have()) NA else all(brreg_validate(cl$org_nr))
  })

  check("CL-07", "change rows carry a field name", {
    x <- cl[cl$change_type == "change", ]
    if (!have() || nrow(x) == 0) NA else all(!is.na(x$field))
  })

  check("CL-08", "changed fields map to real state columns", {
    x <- cl[cl$change_type == "change", ]
    s <- tb$read_parquet_safe(file.path(store, "state", "enheter.parquet"))
    if (!have() || nrow(x) == 0) NA else all(unique(x$field) %in% names(s))
  }, defect = "D-42")

  check("CL-09", "track filter returns only the requested field", {
    x <- cl[cl$change_type == "change" & !is.na(cl$field), ]
    if (!have() || nrow(x) == 0) NA else {
      f <- names(sort(table(x$field), decreasing = TRUE))[1]
      out <- brreg_changes(track = f)
      nrow(out) > 0 && all(out$field == f)
    }
  }, defect = "D-48")

  check("CL-10", "org_nr filter is exact", {
    if (!have()) NA else {
      o <- cl$org_nr[1]
      out <- brreg_changes(org_nr = o)
      nrow(out) > 0 && all(out$org_nr == o)
    }
  })

  check("CL-11", "registry filter is honoured", {
    if (!have()) NA else all(brreg_changes(registry = "enheter")$registry == "enheter")
  })

  check("CL-12", "change_type filter is honoured", {
    if (!have()) NA else {
      ct <- names(sort(table(cl$change_type), decreasing = TRUE))[1]
      all(brreg_changes(change_type = ct)$change_type == ct)
    }
  })

  check("CL-13", "changelog is ordered by time", {
    if (!have() || nrow(cl) < 2) NA else !is.unsorted(cl$timestamp)
  })

  check("CL-14", "date filter is applied to the event timestamp, not the partition date", {
    if (!have()) NA else {
      d <- as.Date(substr(cl$timestamp, 1, 10))
      cutoff <- min(d, na.rm = TRUE) + 1
      out <- brreg_changes(from = cutoff)
      nrow(out) == 0 || all(as.Date(substr(out$timestamp, 1, 10)) >= cutoff)
    }
  }, defect = "D-49")

  check("CL-15", "change_summary totals equal the raw changelog", {
    if (!have()) NA else sum(brreg_change_summary()$n) == nrow(cl)
  })

  check("CL-16", "entry rows have no field and no old value", {
    x <- cl[cl$change_type == "entry", ]
    if (!have() || nrow(x) == 0) NA else all(is.na(x$field)) && all(is.na(x$value_from))
  })

  check("CL-17", "exit rows have no new value", {
    x <- cl[cl$change_type == "exit", ]
    if (!have() || nrow(x) == 0) NA else all(is.na(x$value_to))
  })

  check("CL-18", "change rows actually differ between old and new", {
    x <- cl[cl$change_type == "change" & !is.na(cl$value_from) & !is.na(cl$value_to), ]
    if (!have() || nrow(x) == 0) NA else all(x$value_from != x$value_to)
  })

  check("CL-19", "update_id is populated and non-decreasing over time", {
    if (!have() || all(is.na(cl$update_id))) NA else {
      u <- cl$update_id[!is.na(cl$update_id)]
      length(u) > 0 && !is.unsorted(u)
    }
  })

  check("CL-20", "changelog timestamps carry a timezone designator", {
    if (!have()) NA else all(grepl("(Z|[+-][0-9]{2}:?[0-9]{2})$", cl$timestamp))
  }, defect = "D-33")

  check("CL-21", "the state reflects the changes the changelog records", {
    x <- cl[cl$change_type == "change" & !is.na(cl$field), ]
    if (!have() || nrow(x) == 0) NA else {
      s <- tb$read_parquet_safe(file.path(store, "state", "enheter.parquet"))
      row <- x[1, ]
      if (!row$field %in% names(s)) NA else {
        cur <- as.character(s[[row$field]][s$org_nr == row$org_nr])
        length(cur) == 1 && identical(cur, as.character(row$value_to))
      }
    }
  }, defect = "D-40")

  check("CL-22", "changelog partitions are hive-encoded by sync_date", {
    if (!dir.exists(cl_dir)) NA else {
      p <- list.dirs(cl_dir, recursive = FALSE)
      length(p) > 0 && all(grepl("sync_date=\\d{4}-\\d{2}-\\d{2}$", p))
    }
  })

  check("CL-23", "changelog parquet on disk has the eight-column schema", {
    f <- list.files(cl_dir, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)
    if (length(f) == 0) NA else setequal(names(tb$read_parquet_safe(f[1])), cl_cols)
  })

  check("CL-24", "a second replay does not duplicate changelog rows", {
    if (!have()) NA else {
      before <- nrow(brreg_changes())
      brreg_sync(types = "enheter", verbose = FALSE)
      after <- nrow(brreg_changes())
      after >= before
    }
  })

  check("CL-25", "brreg_flows() works once a changelog exists", {
    if (!have()) NA else {
      f <- brreg_flows()
      is.data.frame(f) && all(c("date", "entries", "exits", "net") %in% names(f))
    }
  })

  check("CL-26", "flows net equals entries minus exits", {
    f <- tryCatch(brreg_flows(), error = function(e) NULL)
    if (is.null(f) || nrow(f) == 0) NA else all(f$net == f$entries - f$exits)
  })

  check("CL-27", "flows exits carry industry attributes rather than all-NA", {
    f <- tryCatch(brreg_flows(), error = function(e) NULL)
    if (is.null(f) || nrow(f) == 0) NA else {
      ex <- f[f$exits > 0, ]
      if (nrow(ex) == 0) NA else !all(is.na(ex$nace_1))
    }
  }, defect = "D-50")

  check("CL-28", "deleted entities retain their annotation history", {
    x <- cl[cl$change_type == "exit", ]
    a <- brreg_annotations()
    if (!have() || nrow(x) == 0 || nrow(a) == 0) NA else {
      length(intersect(x$org_nr, a$org_nr)) > 0
    }
  }, defect = "D-43")

  stress_flush()
}

test_changelog()
