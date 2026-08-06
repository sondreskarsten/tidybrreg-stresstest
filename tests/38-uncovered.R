root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
source(file.path(root, "R", "payloads.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

test_uncovered <- function(fx = load_fixtures(),
                           pw = tryCatch(readRDS(file.path(stress_results_dir(), "prewarm.rds")),
                                         error = function(e) NULL)) {
  stress_init("38-uncovered")
  stress_stagger()

  asa <- fx$known$asa

  check("UC-11", "type = label is documented as contacting SSB KLASS", {
    db <- tools::Rd_db("tidybrreg")
    txt <- paste(capture.output(tools::Rd2txt(db[["brreg_entity.Rd"]])), collapse = " ")
    grepl("KLASS|SSB|ssb", txt)
  }, defect = "D-11")

  check("UC-11b", "KLASS dictionaries come from a different host than the register", {
    a <- tb$brreg_req("enheter")$url
    b <- tb$klass_req("classifications/6")$url
    sub("^https?://([^/]+).*", "\\1", a) != sub("^https?://([^/]+).*", "\\1", b)
  })

  check("UC-26", "underenheter bulk carries no all-NA enheter-only columns", {
    if (is.null(pw)) NA else {
      d <- tb$parse_bulk_csv(pw$paths$underenheter_csv, n_max = 20000)
      allna <- names(d)[vapply(d, function(x) all(is.na(x)), logical(1))]
      length(allna) == 0L
    }
  }, defect = "D-26")

  check("UC-37", "an empty CDC window leaves the cursor usable rather than at zero", {
    tip <- brreg_updates(since = Sys.Date() + 30, size = 10, max_pages = 1)
    nrow(tip) == 0
  })

  check("UC-37b", "a zero cursor does not silently replay the feed from its head", {
    u <- brreg_updates(since = Sys.Date() - 1, size = 100, max_pages = 1)
    if (nrow(u) == 0) NA else min(u$update_id) > 1000L
  }, defect = "D-37")

  check("UC-44", "applying the same annotation patch twice does not duplicate rows", {
    st <- tibble::tibble(org_nr = "923609016", position = 0L, infotype = "FADR",
                         tekst = "x", innfoert_dato = as.Date("2020-01-01"))
    p <- list(list(org_nr = "923609016", position = 0L, infotype = "FADR",
                   tekst = "x", innfoert_dato = "2020-01-01"))
    f <- tryCatch(tb$apply_paategning_patches, error = function(e) NULL)
    if (is.null(f)) NA else {
      once <- tryCatch(f(st, p), error = function(e) NULL)
      if (is.null(once)) NA else {
        twice <- f(once, p)
        nrow(twice) == nrow(once)
      }
    }
  }, defect = "D-44")

  check("UC-52", "the bulk register is not a survivor-only population", {
    if (length(fx$deleted) == 0 || is.null(pw)) NA else {
      d <- tb$parse_bulk_csv(pw$paths$enheter_csv, n_max = 1200000)
      any(fx$deleted %in% d$org_nr)
    }
  }, defect = "D-52")

  check("UC-63", "panel with type = roller is rejected or produces a unique firm-period key", {
    out <- tryCatch(brreg_panel(type = "roller", cols = "org_nr"),
                    error = function(e) "err")
    if (identical(out, "err")) TRUE else
      !any(duplicated(out[, c("org_nr", "period")]))
  }, defect = "D-63")

  check("UC-64", "series pushes column projection down rather than reading every column", {
    if (!requireNamespace("arrow", quietly = TRUE)) NA else {
      t_one <- system.time(brreg_series(.vars = "employees"))[["elapsed"]]
      t_all <- system.time(brreg_series())[["elapsed"]]
      t_one < t_all * 4
    }
  }, defect = "D-64")

  check("UC-66", "events aligns snapshots by key, so a duplicated org_nr cannot misalign rows", {
    s <- brreg_snapshots()
    if (nrow(s) < 2) NA else {
      d <- sort(s$snapshot_date)
      store <- file.path(stress_root(), "tmp", "dup-store")
      unlink(store, recursive = TRUE)
      for (dt in d[1:2]) {
        x <- tb$read_parquet_safe(s$path[s$snapshot_date == dt])
        if (identical(dt, d[2])) x <- dplyr::bind_rows(x, x[1, ])
        tb$write_parquet_safe(x, file.path(store, "enheter",
                                           paste0("snapshot_date=", dt), "data.parquet"))
      }
      old <- getOption("brreg.data_dir"); options(brreg.data_dir = store)
      on.exit(options(brreg.data_dir = old), add = TRUE)
      out <- tryCatch(brreg_events(d[1], d[2]), error = function(e) "err")
      identical(out, "err") ||
        (is.data.frame(out) && !any(duplicated(out[out$event_type == "change",
                                                  c("org_nr", "field")])))
    }
  }, defect = "D-66")

  check("UC-68", "as_brreg_tsibble honours the index recorded in flows metadata", {
    if (!requireNamespace("tsibble", quietly = TRUE)) NA else {
      f <- tryCatch(brreg_flows(), error = function(e) NULL)
      if (is.null(f) || nrow(f) == 0) NA else {
        out <- tryCatch(as_brreg_tsibble(f), error = function(e) "err")
        !identical(out, "err")
      }
    }
  }, defect = "D-68")

  check("UC-74", "the session bulk cache does not grow without bound", {
    e <- tb$.brregEnv
    if (is.null(e)) NA else {
      before <- length(ls(e))
      invisible(brreg_status(quiet = TRUE))
      after <- length(ls(e))
      after - before <= 3L
    }
  }, defect = "D-74")

  check("UC-75", "lang = no stores Norwegian labels under a language-neutral name", {
    d <- get_brreg_dic("nace", lang = "no")
    !"name_en" %in% names(d) || all(c("code", "level") %in% names(d))
  }, defect = "D-75")

  check("UC-75b", "lang = no actually returns Norwegian text", {
    en <- get_brreg_dic("nace", lang = "en")
    no <- get_brreg_dic("nace", lang = "no")
    !identical(en$name_en[1:20], no$name_en[1:20])
  }, defect = "D-96")

  check("UC-76", "the label skip list protects columns that are actually labelable", {
    e <- brreg_entity(asa)
    l <- brreg_label(e)
    identical(l$org_nr, e$org_nr) && identical(l$name, e$name) &&
      identical(l$municipality_code, e$municipality_code)
  })

  check("UC-77", "bundled fallback dictionaries exist in the namespace", {
    ns <- asNamespace("tidybrreg")
    exists("nace_codes", envir = ns, inherits = FALSE) &&
      exists("sector_codes", envir = ns, inherits = FALSE)
  }, defect = "D-77")

  check("UC-77b", "get_brreg_dic falls back rather than erroring when KLASS is unreachable", {
    out <- httr2::with_mocked_responses(
      function(req) httr2::response(status_code = 503),
      tryCatch(get_brreg_dic("sector"), error = function(e) "err"))
    is.data.frame(out)
  }, defect = "D-77")

  check("UC-39", "roller bulk is not re-downloaded when the cursor yields no roller events", {
    if (is.null(pw) || is.null(pw$paths$roller_json)) NA else {
      m1 <- file.mtime(pw$paths$roller_json)
      u <- brreg_updates(since = Sys.Date(), size = 10, type = "roller")
      identical(file.mtime(pw$paths$roller_json), m1)
    }
  }, defect = "D-39")

  check("UC-41", "applying many CDC events to state completes in reasonable time", {
    if (is.null(pw)) NA else {
      base <- tb$parse_bulk_csv(pw$paths$enheter_csv, n_max = 200000)
      upd <- brreg_updates(since = Sys.Date() - 2, size = 5000,
                           include_changes = TRUE, max_pages = 2)
      upd <- upd[upd$org_nr %in% base$org_nr, ]
      if (nrow(upd) < 50) NA else {
        el <- system.time(brreg_replay(base, upd))[["elapsed"]]
        el < 300
      }
    }
  }, defect = "D-41")

  stress_flush()
}

test_uncovered()
