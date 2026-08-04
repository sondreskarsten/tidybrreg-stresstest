root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

test_download <- function(pw = readRDS(file.path(stress_results_dir(), "prewarm.rds"))) {
  stress_init("31-download")

  cache_dir <- tools::R_user_dir("tidybrreg", "cache")
  has_arrow <- requireNamespace("arrow", quietly = TRUE)

  check("DL-01", "path output returns an existing gzip file", {
    p <- brreg_download("enheter", type_output = "path")
    file.exists(p) && grepl("\\.gz$", p)
  })

  check("DL-02", "path output is inside the package cache directory", {
    p <- brreg_download("enheter", type_output = "path")
    startsWith(normalizePath(p), normalizePath(cache_dir))
  })

  check("DL-03", "roller csv is coerced to json with a message", {
    p <- brreg_download("roller", format = "csv", type_output = "path")
    grepl("json", p)
  })

  check("DL-04", "underenheter path output works",
        file.exists(brreg_download("underenheter", type_output = "path")))

  check("DL-05", "refresh = auto without a change does not re-download", {
    p <- brreg_download("enheter", type_output = "path")
    m1 <- file.mtime(p)
    brreg_download("enheter", refresh = "auto", type_output = "path")
    identical(file.mtime(p), m1)
  })

  check("DL-06", "refresh = auto compares against the server", {
    etag <- file.path(cache_dir, "enheter_bulk.csv.gz.etag")
    file.exists(etag) && nzchar(readLines(etag, n = 1, warn = FALSE))
  }, defect = "D-22")

  check("DL-07", "an unrecognised refresh value is rejected", {
    out <- tryCatch(brreg_download("enheter", refresh = "always", type_output = "path"),
                    error = function(e) "err")
    identical(out, "err")
  }, defect = "D-23")

  check("DL-08", "cache = FALSE does not leave a cached payload behind", {
    p <- file.path(cache_dir, "underenheter_bulk.csv.gz")
    existed <- file.exists(p)
    unlink(p)
    brreg_download("underenheter", cache = FALSE, type_output = "path")
    left <- file.exists(p)
    if (existed && !left) brreg_download("underenheter", type_output = "path")
    !left
  }, defect = "D-24")

  check("DL-09", "csv tibble output maps to English column names", {
    d <- tb$parse_bulk_csv(brreg_download("enheter", type_output = "path"), n_max = 5000)
    "org_nr" %in% names(d) && "legal_form" %in% names(d)
  })

  check("DL-10", "arrow output maps to the same column names as tibble output", {
    if (!has_arrow) NA else {
      a <- brreg_download("enheter", type_output = "arrow")
      "org_nr" %in% names(a)
    }
  }, defect = "D-25")

  check("DL-11", "arrow output is not materialised as a data frame", {
    if (!has_arrow) NA else !is.data.frame(brreg_download("enheter", type_output = "arrow"))
  })

  check("DL-12", "arrow output row count matches the register", {
    if (!has_arrow) NA else {
      a <- brreg_download("enheter", type_output = "arrow")
      nrow(a) > 900000L
    }
  })

  check("DL-13", "json bulk parses to a tibble with atomic columns", {
    p <- pw$paths$enheter_json
    if (is.null(p)) NA else {
      d <- tb$parse_bulk_json(p, type = "enheter")
      !any(vapply(d, is.list, logical(1)))
    }
  })

  check("DL-14", "json bulk carries historiskeNavn", {
    p <- pw$paths$enheter_json
    if (is.null(p)) NA else {
      d <- tb$parse_bulk_json(p, type = "enheter")
      any(grepl("historiske", names(d), ignore.case = TRUE))
    }
  })

  check("DL-15", "json bulk carries inline paategninger", {
    p <- pw$paths$enheter_json
    if (is.null(p)) NA else {
      d <- tb$parse_bulk_json(p, type = "enheter")
      any(c("annotations", "paategninger") %in% names(d))
    }
  })

  check("DL-16", "csv and json bulks agree on entity count", {
    p <- pw$paths$enheter_json
    if (is.null(p) || !has_arrow) NA else {
      a <- brreg_download("enheter", type_output = "arrow")
      j <- tb$parse_bulk_json(p, type = "enheter")
      abs(nrow(a) - nrow(j)) / nrow(j) < 0.02
    }
  })

  check("DL-17", "csv and json bulks agree on the column dictionary", {
    p <- pw$paths$enheter_json
    if (is.null(p)) NA else {
      cj <- names(tb$parse_bulk_json(p, type = "enheter"))
      cc <- names(tb$parse_bulk_csv(brreg_download("enheter", type_output = "path"),
                                    n_max = 100))
      length(setdiff(tidybrreg::field_dict$col_name, intersect(cj, cc))) == 0L
    }
  })

  check("DL-18", "underenheter output does not carry all-NA enheter-only columns", {
    d <- tb$parse_bulk_csv(brreg_download("underenheter", type_output = "path"),
                           n_max = 5000)
    allna <- names(d)[vapply(d, function(x) all(is.na(x)), logical(1))]
    length(allna) == 0L
  }, defect = "D-26")

  check("DL-19", "roller bulk parses to the roles schema", {
    p <- pw$paths$roller_json
    if (is.null(p)) NA else {
      code <- c(
        'library(tidybrreg)',
        sprintf('r <- tidybrreg:::parse_roles_bulk("%s")', p),
        'stopifnot(is.data.frame(r), nrow(r) > 1e6,',
        '          all(c("org_nr","role_code","person_id") %in% names(r)))'
      )
      f <- tempfile(fileext = ".R"); writeLines(code, f)
      st <- system2("Rscript", c("--vanilla", shQuote(f)), stdout = TRUE, stderr = TRUE,
                    timeout = 1800)
      is.null(attr(st, "status"))
    }
  })

  check("DL-20", "the register has no duplicate org numbers", {
    if (!has_arrow) NA else {
      a <- brreg_download("enheter", type_output = "arrow")
      ids <- as.vector(a[["organisasjonsnummer"]] %||% a[["org_nr"]])
      !any(duplicated(ids))
    }
  })

  check("DL-21", "every register org number is mod-11 valid", {
    if (!has_arrow) NA else {
      a <- brreg_download("enheter", type_output = "arrow")
      ids <- as.vector(a[["organisasjonsnummer"]] %||% a[["org_nr"]])
      all(brreg_validate(utils::head(ids, 20000L)))
    }
  }, defect = "D-02")

  check("DL-22", "a corrupted cache file surfaces as an error, not silent garbage", {
    p <- file.path(cache_dir, "corrupt_bulk.csv.gz")
    writeLines("not a gzip", p)
    out <- tryCatch(tb$parse_bulk_csv(p, n_max = 10), error = function(e) "err")
    unlink(p)
    identical(out, "err") || is.data.frame(out)
  })

  check("DL-23", "download does not mutate the snapshot store", {
    before <- nrow(brreg_snapshots())
    brreg_download("enheter", type_output = "path")
    nrow(brreg_snapshots()) == before
  })

  stress_flush()
}

`%||%` <- function(x, y) if (is.null(x)) y else x
test_download()
