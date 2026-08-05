root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

test_panel <- function(pw = readRDS(file.path(stress_results_dir(), "prewarm.rds"))) {
  stress_init("33-panel-series-events")
  options(brreg.data_dir = pw$store)

  snaps <- brreg_snapshots()
  dates <- sort(snaps$snapshot_date)

  check("PN-00", "the shared store has at least three snapshots", nrow(snaps) >= 3L)

  p <- brreg_panel(cols = c("employees", "nace_1", "municipality_code", "legal_form"))

  check("PN-01", "panel returns rows", nrow(p) > 0)

  check("PN-02", "documented columns are present",
        all(c("org_nr", "period", "snapshot_date") %in% names(p)))

  check("PN-03", "requested columns are present",
        all(c("employees", "nace_1") %in% names(p)))

  check("PN-04", "no unrequested payload columns leak in",
        !"business_address" %in% names(p), defect = "D-61")

  check("PN-05", "date_mapping attribute is attached",
        is.data.frame(attr(p, "date_mapping")))

  check("PN-06", "every panel snapshot_date exists in the store",
        all(unique(p$snapshot_date) %in% snaps$snapshot_date))

  check("PN-07", "LOCF never uses a future snapshot", {
    m <- attr(p, "date_mapping")
    all(m$snapshot_date <= m$target_date)
  })

  check("PN-08", "one row per firm per period",
        !any(duplicated(p[, c("org_nr", "period")])))

  check("PN-09", "quarterly frequency yields more periods than yearly", {
    y <- brreg_panel("year", cols = "employees")
    q <- brreg_panel("quarter", cols = "employees")
    length(unique(q$period)) >= length(unique(y$period))
  })

  check("PN-10", "monthly frequency yields the most periods", {
    m <- brreg_panel("month", cols = "employees")
    q <- brreg_panel("quarter", cols = "employees")
    length(unique(m$period)) >= length(unique(q$period))
  })

  check("PN-11", "custom dates are honoured", {
    cp <- brreg_panel("custom", dates = dates[c(1, 3)], cols = "employees")
    length(unique(cp$period)) == 2L
  })

  check("PN-12", "from and to bound the panel", {
    b <- brreg_panel("year", from = dates[2], to = dates[length(dates)],
                     cols = "employees")
    min(as.Date(b$period)) >= dates[2]
  })

  check("PN-13", "max_gap removes stale carry-forward", {
    a <- brreg_panel("month", cols = "employees")
    b <- brreg_panel("month", cols = "employees", max_gap = 1L)
    length(unique(b$period)) <= length(unique(a$period))
  })

  check("PN-14", "max_gap is effective for custom frequency", {
    far <- as.Date("2030-01-01")
    a <- brreg_panel("custom", dates = c(dates[length(dates)], far), cols = "employees")
    b <- brreg_panel("custom", dates = c(dates[length(dates)], far), cols = "employees",
                     max_gap = 1L)
    length(unique(b$period)) < length(unique(a$period))
  }, defect = "D-62")

  check("PN-15", "is_entry marks only genuinely new firms", {
    first_period <- min(p$period)
    ent <- p[p$is_entry & p$period == first_period, ]
    nrow(ent) == 0L
  }, defect = "D-60")

  check("PN-16", "is_exit marks only firms absent from later periods", {
    last_period <- max(p$period)
    ex <- p[p$is_exit & p$period == last_period, ]
    nrow(ex) == 0L
  }, defect = "D-60")

  check("PN-17", "a firm removed between snapshots is flagged as an exit exactly once", {
    dropped <- setdiff(
      tidybrreg:::read_parquet_safe(snaps$path[1])$org_nr,
      tidybrreg:::read_parquet_safe(snaps$path[nrow(snaps)])$org_nr)
    if (length(dropped) == 0) NA else {
      sub <- p[p$org_nr %in% dropped[1], ]
      sum(sub$is_exit) == 1L
    }
  }, defect = "D-60")

  check("PN-18", "labelled panel translates codes", {
    l <- brreg_panel(cols = c("legal_form"), label = TRUE)
    !identical(sort(unique(l$legal_form)), sort(unique(p$legal_form)))
  })

  check("PN-19", "underenheter panel works",
        nrow(brreg_panel(type = "underenheter", cols = "org_nr")) > 0)

  check_error("PN-20", "custom frequency without dates aborts informatively",
              brreg_panel("custom", cols = "employees"))

  check("PN-21", "period values are period labels, not raw snapshot dates", {
    y <- brreg_panel("year", cols = "employees")
    all(grepl("^\\d{4}$", unique(y$period)))
  }, defect = "D-65")

  s <- brreg_series(.vars = "employees", by = "legal_form")

  check("SE-01", "series returns rows", nrow(s) > 0)

  check("SE-02", "series has a period column", "period" %in% names(s))

  check("SE-03", "series names summary columns as col_fn",
        "employees_total" %in% names(s))

  check("SE-04", "counting mode works without .vars", {
    c0 <- brreg_series()
    "n" %in% names(c0) && all(c0$n > 0)
  })

  check("SE-05", "national totals equal the sum of grouped totals", {
    g <- brreg_series(.vars = "employees", by = "legal_form")
    n <- brreg_series(.vars = "employees")
    per <- stats::aggregate(g$employees_total, list(period = g$period), sum, na.rm = TRUE)
    all(abs(per$x - n$employees_total[match(per$period, n$period)]) < 1)
  })

  check("SE-06", "multiple summary functions produce multiple columns", {
    m <- brreg_series(.vars = "employees",
                      .fns = list(avg = function(x) mean(x, na.rm = TRUE),
                                  total = function(x) sum(x, na.rm = TRUE)))
    all(c("employees_avg", "employees_total") %in% names(m))
  })

  check("SE-07", "multiple grouping variables are supported",
        nrow(brreg_series(.vars = "employees",
                          by = c("legal_form", "municipality_code"))) > 0)

  check("SE-08", "series counts match panel counts per period", {
    c0 <- brreg_series()
    pp <- brreg_panel(cols = "org_nr")
    a <- tapply(pp$org_nr, pp$period, length)
    all(c0$n[match(names(a), c0$period)] == as.integer(a))
  })

  check("SE-09", "brreg_panel_meta is attached", {
    !is.null(attr(s, "brreg_panel_meta"))
  })

  check_error("SE-10", "an unknown grouping column aborts informatively",
              brreg_series(.vars = "employees", by = "nope"))

  check("SE-11", "quarterly and monthly frequencies work",
        nrow(brreg_series(frequency = "quarter")) > 0 &&
          nrow(brreg_series(frequency = "month")) > 0)

  ev <- brreg_events(dates[1], dates[length(dates)])

  check("EV-01", "events returns rows", nrow(ev) > 0)

  check("EV-02", "documented columns are present",
        all(c("org_nr", "event_type", "event_date", "field", "value_from",
              "value_to") %in% names(ev)))

  check("EV-03", "event types are the documented set",
        all(ev$event_type %in% c("entry", "exit", "change")))

  check("EV-04", "event_date equals the later snapshot",
        all(ev$event_date == dates[length(dates)]))

  check("EV-05", "exits equal the set difference of org numbers", {
    a <- tidybrreg:::read_parquet_safe(snaps$path[snaps$snapshot_date == dates[1]])$org_nr
    b <- tidybrreg:::read_parquet_safe(
      snaps$path[snaps$snapshot_date == dates[length(dates)]])$org_nr
    setequal(ev$org_nr[ev$event_type == "exit"], setdiff(a, b))
  })

  check("EV-06", "entries equal the reverse set difference", {
    a <- tidybrreg:::read_parquet_safe(snaps$path[snaps$snapshot_date == dates[1]])$org_nr
    b <- tidybrreg:::read_parquet_safe(
      snaps$path[snaps$snapshot_date == dates[length(dates)]])$org_nr
    setequal(ev$org_nr[ev$event_type == "entry"], setdiff(b, a))
  })

  check("EV-07", "planted municipality changes are detected", {
    ch <- ev[ev$event_type == "change" & ev$field == "municipality_code", ]
    nrow(ch) > 0
  })

  check("EV-08", "change rows carry both values", {
    ch <- ev[ev$event_type == "change", ]
    all(ch$value_from != ch$value_to | is.na(ch$value_from) | is.na(ch$value_to))
  })

  check("EV-09", "entry and exit rows carry no field", {
    all(is.na(ev$field[ev$event_type %in% c("entry", "exit")]))
  })

  check("EV-10", "cols restricts the tracked fields", {
    e2 <- brreg_events(dates[1], dates[length(dates)], cols = "municipality_code")
    all(e2$field[e2$event_type == "change"] == "municipality_code")
  })

  check("EV-11", "identical snapshots produce no events", {
    e0 <- brreg_events(dates[1], dates[1])
    nrow(e0) == 0L
  })

  check_error("EV-12", "an unknown snapshot date aborts",
              brreg_events(as.Date("1999-01-01"), dates[1]), pattern = "No snapshot")

  check("EV-13", "reversed dates are rejected or clearly labelled", {
    out <- tryCatch(brreg_events(dates[length(dates)], dates[1]),
                    error = function(e) "err")
    identical(out, "err")
  }, defect = "D-98")

  check("EV-14", "no org number appears as both entry and exit",
        length(intersect(ev$org_nr[ev$event_type == "entry"],
                         ev$org_nr[ev$event_type == "exit"])) == 0L)

  has_tsibble <- requireNamespace("tsibble", quietly = TRUE)

  check("TS-01", "series converts to a tsibble", {
    if (!has_tsibble) NA else inherits(as_brreg_tsibble(s), "tbl_ts")
  })

  check("TS-02", "panel converts to a tsibble", {
    if (!has_tsibble) NA else
      inherits(as_brreg_tsibble(brreg_panel(cols = "employees")), "tbl_ts")
  }, defect = "D-67")

  check("TS-03", "explicit key and index are honoured", {
    if (!has_tsibble) NA else
      inherits(as_brreg_tsibble(s, key = "legal_form", index = "period"), "tbl_ts")
  })

  check("TS-04", "the tsibble index is a Date", {
    if (!has_tsibble) NA else inherits(as_brreg_tsibble(s)$period, "Date")
  })

  check("TS-05", "no rows are lost in conversion", {
    if (!has_tsibble) NA else nrow(as_brreg_tsibble(s)) == nrow(s)
  })

  stress_flush()
}

test_panel()
