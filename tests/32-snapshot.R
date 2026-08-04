root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

test_snapshot <- function(pw = readRDS(file.path(stress_results_dir(), "prewarm.rds")),
                          store = file.path(stress_root(), "tmp", "snapshot-store")) {
  stress_init("32-snapshot")
  dir.create(store, recursive = TRUE, showWarnings = FALSE)
  options(brreg.data_dir = store, brreg.allow_download = TRUE)

  has_arrow <- requireNamespace("arrow", quietly = TRUE)

  check("SN-01", "underenheter snapshot writes a parquet partition", {
    p <- brreg_snapshot("underenheter", ask = FALSE)
    file.exists(p) && grepl("snapshot_date=", p)
  })

  check("SN-02", "snapshot is listed", nrow(brreg_snapshots("underenheter")) == 1L)

  check("SN-03", "snapshot records a manifest entry", {
    m <- brreg_manifest()
    nrow(m) >= 1L && any(m$type == "underenheter")
  })

  check("SN-04", "manifest records a file hash", {
    m <- brreg_manifest()
    any(!is.na(m$file_hash))
  })

  check("SN-05", "manifest record_count matches the parquet row count", {
    m <- brreg_manifest()
    p <- m$parquet_path[m$type == "underenheter"][1]
    nrow(tb$read_parquet_safe(p)) == m$record_count[m$type == "underenheter"][1]
  })

  check("SN-06", "re-snapshotting without force is a no-op", {
    n <- nrow(brreg_manifest())
    brreg_snapshot("underenheter", ask = FALSE)
    nrow(brreg_manifest()) == n
  })

  check("SN-07", "the snapshot store contains only parquet files", {
    files <- list.files(file.path(store, "underenheter"), recursive = TRUE)
    all(grepl("\\.parquet$", files))
  }, defect = "D-54")

  check("SN-08", "arrow can open the store written by brreg_snapshot", {
    if (!has_arrow) NA else {
      ds <- brreg_open("underenheter")
      nrow(dplyr::collect(dplyr::filter(ds, .data$org_nr == "000000000"))) == 0L
    }
  }, defect = "D-54")

  check("SN-09", "arrow reads the expected row count from the store", {
    if (!has_arrow) NA else {
      ds <- brreg_open("underenheter")
      nrow(ds) == brreg_manifest()$record_count[brreg_manifest()$type == "underenheter"][1]
    }
  }, defect = "D-54")

  check("SN-10", "snapshot date partition key matches the requested date", {
    d <- Sys.Date() - 1L
    p <- brreg_snapshot("underenheter", date = d, ask = FALSE)
    grepl(paste0("snapshot_date=", d), p)
  })

  check("SN-11", "force overwrites rather than duplicating a partition", {
    d <- Sys.Date() - 1L
    brreg_snapshot("underenheter", date = d, force = TRUE, ask = FALSE)
    length(list.files(file.path(store, "underenheter",
                                paste0("snapshot_date=", d)),
                      pattern = "\\.parquet$", recursive = TRUE)) == 1L
  })

  check("SN-12", "manifest ids remain unique after a forced re-snapshot",
        !any(duplicated(brreg_manifest()$id)), defect = "D-55")

  imp <- file.path(store, "import-src.csv.gz")
  file.copy(pw$paths$underenheter_csv, imp, overwrite = TRUE)

  check("IM-01", "import writes a partition", {
    p <- brreg_import(imp, snapshot_date = "2024-12-31", type = "underenheter")
    file.exists(p)
  })

  check("IM-02", "imported partition is listed",
        as.Date("2024-12-31") %in% brreg_snapshots("underenheter")$snapshot_date)

  check("IM-03", "imported partition parses to the mapped schema", {
    p <- brreg_snapshots("underenheter")$path[
      brreg_snapshots("underenheter")$snapshot_date == as.Date("2024-12-31")]
    "org_nr" %in% names(tb$read_parquet_safe(p))
  })

  check("IM-04", "import records provenance in the manifest",
        any(brreg_manifest()$snapshot_date == as.Date("2024-12-31")),
        defect = "D-56")

  check("IM-05", "import without force does not overwrite", {
    p1 <- brreg_import(imp, snapshot_date = "2024-12-31", type = "underenheter")
    m1 <- file.mtime(p1)
    brreg_import(imp, snapshot_date = "2024-12-31", type = "underenheter")
    identical(file.mtime(p1), m1)
  })

  check("IM-06", "import with force overwrites", {
    p1 <- brreg_import(imp, snapshot_date = "2024-12-31", type = "underenheter",
                       force = TRUE)
    file.exists(p1)
  })

  check("IM-07", "importing a roller json either parses it or refuses", {
    p <- pw$paths$roller_json
    if (is.null(p)) NA else {
      out <- tryCatch(brreg_import(p, snapshot_date = "2024-01-01", type = "roller"),
                      error = function(e) "err")
      if (identical(out, "err")) TRUE else {
        d <- tb$read_parquet_safe(out)
        "role_code" %in% names(d)
      }
    }
  }, defect = "D-57")

  check("CL-01", "cleanup keeps the newest n partitions", {
    before <- nrow(brreg_snapshots("underenheter"))
    if (before < 3L) NA else {
      brreg_cleanup(keep_n = 2L, type = "underenheter")
      nrow(brreg_snapshots("underenheter")) == 2L
    }
  })

  check("CL-02", "cleanup removes the whole partition directory", {
    dirs <- list.dirs(file.path(store, "underenheter"), recursive = FALSE)
    length(dirs) == nrow(brreg_snapshots("underenheter"))
  })

  check("CL-03", "cleanup prunes the manifest of deleted snapshots", {
    m <- brreg_manifest()
    live <- brreg_snapshots("underenheter")$snapshot_date
    all(m$snapshot_date[m$type == "underenheter"] %in% live)
  }, defect = "D-58")

  check("CL-04", "cleanup by age is honoured", {
    brreg_cleanup(max_age_days = 1L, type = "underenheter")
    all(brreg_snapshots("underenheter")$snapshot_date >= Sys.Date() - 1L)
  })

  check("CL-05", "cleanup returns the deleted rows invisibly", {
    d <- brreg_cleanup(keep_n = 1L, type = "underenheter")
    is.data.frame(d)
  })

  stress_flush()
}

test_snapshot()
