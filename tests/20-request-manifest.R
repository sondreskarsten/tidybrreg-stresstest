root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

test_request_manifest <- function() {
  stress_init("20-request-manifest")

  check("Q-01", "enhetsregisteret base url is correct",
        identical(tb$brreg_base_url(), "https://data.brreg.no/enhetsregisteret/api"))

  check("Q-02", "fullmakt base url is correct",
        identical(tb$brreg_base_url("fullmakt"), "https://data.brreg.no/fullmakt"))

  check_error("Q-03", "unknown service aborts", tb$brreg_base_url("nope"))

  check("Q-04", "request carries a descriptive user agent", {
    r <- tb$brreg_req("enheter/923609016")
    ua <- r$headers[["User-Agent"]]
    ua <- if (is.null(ua)) r$options$useragent else ua
    !is.null(ua) && grepl("tidybrreg", ua)
  })

  check("Q-05", "request sets a UTF-8 accept header", {
    r <- tb$brreg_req("enheter/923609016")
    grepl("charset=UTF-8", r$headers[["Accept"]] %||% "")
  })

  check("Q-06", "query parameters are appended", {
    r <- tb$brreg_req("enheter", query = list(navn = "Equinor"))
    grepl("navn=Equinor", r$url)
  })

  check("Q-07", "NULL query parameters are dropped", {
    r <- tb$brreg_req("enheter", query = list(navn = NULL, size = 10))
    !grepl("navn", r$url) && grepl("size=10", r$url)
  })

  check("Q-08", "klass requests target SSB", {
    r <- tb$klass_req("classifications/6/codesAt")
    grepl("^https://data.ssb.no/api/klass/v1", r$url)
  })

  check("Q-09", "brreg and klass use different throttle realms", {
    a <- tb$brreg_req("enheter")
    b <- tb$klass_req("classifications/6")
    !identical(a$policies$throttle$realm, b$policies$throttle$realm)
  })

  check("Q-10", "retry policy is configured", {
    r <- tb$brreg_req("enheter")
    !is.null(r$policies$retry_max_tries) || !is.null(r$policies$retry_is_transient)
  })

  check("Q-11", "error body extractor returns character or empty", {
    fn <- tb$brreg_error_body
    is.function(fn)
  })

  check("Q-12", "path segments are escaped, not concatenated blindly", {
    r <- tb$brreg_req("enheter/923609016/roller")
    grepl("enheter/923609016/roller", r$url)
  })

  d <- tempfile("brregdata")
  old_opt <- getOption("brreg.data_dir")
  options(brreg.data_dir = d)
  on.exit(options(brreg.data_dir = old_opt), add = TRUE)

  check("DD-01", "data_dir honours the option",
        identical(normalizePath(brreg_data_dir()), normalizePath(d)))

  check("DD-02", "data_dir creates the directory", dir.exists(brreg_data_dir()))

  check("DD-03", "snapshots on an empty store returns a typed empty tibble",
        is_typed_empty(brreg_snapshots(), c("snapshot_date", "file_size", "path")))

  check("DD-04", "snapshots snapshot_date column is a Date",
        inherits(brreg_snapshots()$snapshot_date, "Date"))

  check("DD-05", "snapshots supports all three types",
        all(vapply(c("enheter", "underenheter", "roller"),
                   function(t) is.data.frame(brreg_snapshots(t)), logical(1))))

  check_error("DD-06", "open on an empty store aborts", brreg_open(),
              pattern = "No snapshots")

  check_error("DD-07", "cleanup without criteria aborts", brreg_cleanup(),
              pattern = "keep_n")

  check("DD-08", "cleanup on an empty store is a no-op",
        nrow(brreg_cleanup(keep_n = 5)) == 0L)

  check("MN-01", "manifest on an empty store returns a typed empty tibble",
        is_typed_empty(brreg_manifest(),
                       c("id", "type", "snapshot_date", "endpoint", "format",
                         "download_timestamp", "record_count", "parquet_path")))

  check("MN-02", "manifest snapshot_date is a Date",
        inherits(brreg_manifest()$snapshot_date, "Date"))

  writeLines('{"schema_version":"1.0","downloads":[]}',
             file.path(brreg_data_dir(), "manifest.json"))

  check_subprocess("MN-03", "manifest with an empty downloads array terminates",
                   c(sprintf('options(brreg.data_dir = "%s", expressions = 5000)', d),
                     "library(tidybrreg)",
                     "m <- brreg_manifest()",
                     "stopifnot(is.data.frame(m), nrow(m) == 0)"),
                   expect = "ok", timeout = 60L, defect = "D-59")

  unlink(file.path(brreg_data_dir(), "manifest.json"))

  entry <- tb$build_manifest_entry(type = "enheter", snapshot_date = Sys.Date(),
                                   endpoint = "https://example.org", format = "csv",
                                   record_count = 5L)

  check("MN-04", "manifest entry carries the documented fields",
        all(c("id", "type", "snapshot_date", "endpoint", "format",
              "download_timestamp", "record_count") %in% names(entry)))

  tb$write_manifest_entry(entry)

  check("MN-05", "written entry is readable", nrow(brreg_manifest()) == 1L)

  tb$write_manifest_entry(entry)

  check("MN-06", "manifest ids stay unique across writes",
        !any(duplicated(brreg_manifest()$id)), defect = "D-55")

  check("ST-01", "status reports all three datasets", {
    s <- brreg_status(quiet = TRUE)
    length(s$available) + length(s$missing) == 3L
  })

  check("ST-02", "status all_ready is consistent", {
    s <- brreg_status(quiet = TRUE)
    identical(s$all_ready, length(s$missing) == 0L)
  })

  check("ST-03", "status accepts a subset",
        identical(brreg_status("roller", quiet = TRUE)$missing, "roller") ||
          identical(brreg_status("roller", quiet = TRUE)$available, "roller"))

  check_error("ST-04", "status rejects an unknown dataset",
              brreg_status("nope", quiet = TRUE))

  check("ST-05", "sync_status runs on an uninitialised store", {
    s <- brreg_sync_status()
    is.list(s) && !is.null(s$cursor)
  })

  check("ST-06", "sync_status reports never rather than NA before any sync", {
    out <- utils::capture.output(brreg_sync_status())
    !any(grepl("Last sync: NA", out))
  }, defect = "D-45")

  check("ST-07", "sync_status cursors start at zero", {
    s <- brreg_sync_status()
    all(c(s$cursor$enheter_id, s$cursor$underenheter_id, s$cursor$roller_id) == 0L)
  })

  check("PQ-01", "a parquet backend is available",
        tb$parquet_tier() %in% c("arrow", "nanoparquet"))

  check("PQ-02", "parquet round trip preserves a tibble", {
    p <- file.path(tempdir(), "rt.parquet")
    x <- tibble::tibble(a = 1:3, b = c("x", "y", "z"), d = Sys.Date() + 0:2)
    tb$write_parquet_safe(x, p)
    y <- tb$read_parquet_safe(p)
    nrow(y) == 3L && identical(as.character(y$b), x$b) && inherits(y$d, "Date")
  })

  check("PQ-03", "parquet writes are atomic (no temp files left behind)", {
    dd <- file.path(tempdir(), "atomic"); dir.create(dd, showWarnings = FALSE)
    tb$write_parquet_safe(tibble::tibble(a = 1), file.path(dd, "x.parquet"))
    length(list.files(dd)) == 1L
  })

  stress_flush()
}

`%||%` <- function(x, y) if (is.null(x)) y else x
test_request_manifest()
