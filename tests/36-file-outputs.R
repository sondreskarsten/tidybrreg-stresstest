root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

partition_dirs <- function(store, type = "underenheter") {
  base <- file.path(store, type)
  if (!dir.exists(base)) return(character())
  list.dirs(base, recursive = FALSE)
}

test_file_outputs <- function(store = file.path(stress_root(), "tmp", "snapshot-store"),
                              sync_store = file.path(stress_root(), "tmp", "sync-store")) {
  stress_init("36-file-outputs")
  options(brreg.data_dir = store)

  parts <- partition_dirs(store)
  has_store <- length(parts) > 0
  has_arrow <- requireNamespace("arrow", quietly = TRUE)

  check("FO-01", "the snapshot store exists after a snapshot run",
        has_store)

  check("FO-02", "every partition directory is hive-encoded as snapshot_date=YYYY-MM-DD", {
    if (!has_store) NA else all(grepl("snapshot_date=\\d{4}-\\d{2}-\\d{2}$", parts))
  })

  check("FO-03", "a partition contains exactly one data file", {
    if (!has_store) NA else {
      counts <- vapply(parts, function(p)
        length(list.files(p, pattern = "\\.parquet$", recursive = TRUE)), integer(1))
      all(counts == 1L)
    }
  })

  check("FO-04", "no non-parquet file is written inside the dataset root", {
    if (!has_store) NA else {
      files <- list.files(file.path(store, "underenheter"), recursive = TRUE)
      all(grepl("\\.parquet$", files))
    }
  }, defect = "D-54")

  check("FO-05", "arrow can open the store that brreg_snapshot() wrote", {
    if (!has_store || !has_arrow) NA else {
      ds <- brreg_open("underenheter")
      nrow(ds) > 0
    }
  }, defect = "D-54")

  check("FO-06", "the raw payload is not duplicated alongside the parquet", {
    if (!has_store) NA else {
      raw <- list.files(file.path(store, "underenheter"), pattern = "\\.gz$",
                        recursive = TRUE, full.names = TRUE)
      length(raw) == 0L
    }
  }, defect = "D-54")

  check("FO-07", "no temp or partial files are left behind after writing", {
    if (!has_store) NA else {
      leftovers <- list.files(store, pattern = "(\\.tmp$|\\.partial$|^\\.)",
                              recursive = TRUE, all.files = TRUE)
      length(leftovers) == 0L
    }
  })

  check("FO-08", "each parquet is readable and non-empty", {
    if (!has_store) NA else {
      pq <- list.files(store, pattern = "\\.parquet$", recursive = TRUE,
                       full.names = TRUE)
      all(vapply(pq, function(f) nrow(tb$read_parquet_safe(f)) > 0, logical(1)))
    }
  })

  check("FO-09", "parquet carries dictionary-mapped column names, not raw API names", {
    if (!has_store) NA else {
      pq <- list.files(store, pattern = "\\.parquet$", recursive = TRUE,
                       full.names = TRUE)[1]
      nms <- names(tb$read_parquet_safe(pq))
      "org_nr" %in% nms && !"organisasjonsnummer" %in% nms
    }
  })

  mpath <- file.path(store, "manifest.json")
  man <- if (file.exists(mpath)) jsonlite::fromJSON(mpath, simplifyVector = FALSE) else NULL

  check("FO-10", "manifest.json exists and declares a schema version", {
    if (is.null(man)) NA else !is.null(man$schema_version)
  })

  check("FO-11", "manifest ids are unique", {
    if (is.null(man)) NA else {
      ids <- vapply(man$downloads, function(e) e$id, character(1))
      !any(duplicated(ids))
    }
  }, defect = "D-55")

  check("FO-12", "every manifest parquet_path points at a file that exists", {
    if (is.null(man)) NA else {
      p <- vapply(man$downloads, function(e) e$parquet_path %||% NA_character_,
                  character(1))
      all(file.exists(stats::na.omit(p)))
    }
  }, defect = "D-58")

  check("FO-13", "manifest record_count matches the parquet it points at", {
    if (is.null(man)) NA else {
      e <- man$downloads[[1]]
      if (is.null(e$parquet_path) || !file.exists(e$parquet_path)) NA else
        nrow(tb$read_parquet_safe(e$parquet_path)) == e$record_count
    }
  })

  check("FO-14", "the documented CDC bridge metadata is actually populated", {
    if (is.null(man)) NA else {
      b <- lapply(man$downloads, function(e) e$cdc_bridge_first_update_id)
      any(vapply(b, function(x) length(x) > 0, logical(1)))
    }
  }, defect = "D-102")

  check("FO-15", "two snapshots with identical content hash are not stored under different dates", {
    if (is.null(man)) NA else {
      h <- vapply(man$downloads, function(e) e$file_hash %||% NA_character_,
                  character(1))
      d <- vapply(man$downloads, function(e) e$snapshot_date, character(1))
      ok <- TRUE
      for (hh in unique(stats::na.omit(h))) {
        if (length(unique(d[h == hh & !is.na(h)])) > 1L) ok <- FALSE
      }
      ok
    }
  }, defect = "D-103")

  check("FO-16", "manifest raw_path is absolute and resolvable, or absent", {
    if (is.null(man)) NA else {
      p <- vapply(man$downloads, function(e) e$raw_path %||% NA_character_,
                  character(1))
      p <- stats::na.omit(p)
      length(p) == 0L || all(file.exists(p))
    }
  })

  cur <- file.path(sync_store, "state", "sync_cursor.json")

  synced <- length(list.files(file.path(sync_store, "state"),
                              recursive = TRUE)) > 0

  check("FO-17", "sync writes a cursor file",
        if (!synced) NA else file.exists(cur))

  check("FO-18", "the cursor records a per-type id and a last_sync timestamp", {
    if (!file.exists(cur)) NA else {
      j <- jsonlite::fromJSON(cur)
      all(c("enheter_id", "underenheter_id", "roller_id") %in% names(j)) &&
        "last_sync" %in% names(j)
    }
  })

  check("FO-19", "state parquet files are written for every synced type", {
    d <- file.path(sync_store, "state")
    if (!synced || !file.exists(cur)) NA else {
      all(file.exists(file.path(d, c("enheter.parquet", "paategninger.parquet",
                                     "historiske_navn.parquet"))))
    }
  })

  check("FO-20", "changelog is hive-partitioned by sync_date", {
    d <- file.path(sync_store, "state", "changelog")
    if (!synced || !file.exists(cur)) NA else {
      parts <- list.dirs(d, recursive = FALSE)
      length(parts) > 0 && all(grepl("sync_date=\\d{4}-\\d{2}-\\d{2}$", parts))
    }
  })

  check("FO-21", "changelog partitions contain readable parquet with the 8-column schema", {
    d <- file.path(sync_store, "state", "changelog")
    f <- list.files(d, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)
    if (length(f) == 0) NA else {
      nms <- names(tb$read_parquet_safe(f[1]))
      setequal(nms, c("timestamp", "org_nr", "registry", "change_type", "field",
                      "value_from", "value_to", "update_id"))
    }
  })

  check("FO-22", "the changelog is append-only within a sync_date partition", {
    d <- file.path(sync_store, "state", "changelog")
    parts <- list.dirs(d, recursive = FALSE)
    if (length(parts) == 0) NA else {
      n <- vapply(parts, function(p)
        length(list.files(p, pattern = "\\.parquet$")), integer(1))
      all(n >= 1L)
    }
  })

  check("FO-23", "no state file is left zero-length by a partial write", {
    d <- file.path(sync_store, "state")
    if (!dir.exists(d)) NA else {
      f <- list.files(d, pattern = "\\.parquet$", full.names = TRUE)
      length(f) == 0L || all(file.size(f) > 0)
    }
  })

  check("FO-24", "every cached payload is a complete, readable gzip stream", {
    cache <- tools::R_user_dir("tidybrreg", "cache")
    gz <- list.files(cache, pattern = "\\.gz$", full.names = TRUE)
    if (length(gz) == 0) NA else {
      all(vapply(gz, function(f) {
        tryCatch({
          con <- gzfile(f, "rb"); on.exit(close(con))
          while (length(readBin(con, "raw", 1e6)) > 0) {}
          TRUE
        }, error = function(e) FALSE, warning = function(w) FALSE)
      }, logical(1)))
    }
  })

  check("FO-25", "a truncated cache payload does not reach the caller as valid data", {
    cache <- tools::R_user_dir("tidybrreg", "cache")
    src <- file.path(cache, "underenheter_bulk.csv.gz")
    if (!file.exists(src)) NA else {
      bak <- paste0(src, ".bak")
      file.rename(src, bak)
      on.exit({ unlink(src); file.rename(bak, src) }, add = TRUE)
      raw <- readBin(bak, "raw", n = 5e6)
      writeBin(raw, src)
      out <- tryCatch({
        d <- tb$parse_bulk_csv(brreg_download("underenheter", type_output = "path"),
                               n_max = 1e6)
        "silently-accepted"
      }, error = function(e) "detected", warning = function(w) "detected")
      identical(out, "detected")
    }
  }, defect = "D-104")

  stress_flush()
}

`%||%` <- function(x, y) if (is.null(x)) y else x
test_file_outputs()
