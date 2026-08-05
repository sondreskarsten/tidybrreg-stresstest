root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

test_search <- function(fx = load_fixtures()) {
  stress_init("13-search")
  stress_stagger()

  asa <- fx$known$asa
  base <- brreg_search(name = "Equinor", max_results = 25)

  check("S-01", "name search returns rows", nrow(base) > 0)

  check("S-02", "total_matches attribute is set and numeric",
        is.numeric(attr(base, "total_matches")) && attr(base, "total_matches") > 0)

  check("S-03", "total_matches is at least the returned row count",
        attr(base, "total_matches") >= nrow(base))

  check("S-04", "search schema matches entity schema minus registry", {
    e <- brreg_entity(asa)
    setequal(setdiff(names(e), "registry"), setdiff(names(base), "registry")) ||
      all(tidybrreg::field_dict$col_name %in% names(base))
  }, defect = "D-93")

  check("S-05", "max_results is respected exactly",
        nrow(brreg_search(legal_form = "AS", max_results = 7)) == 7L)

  check("S-06", "max_results below the page size does not over-fetch",
        nrow(brreg_search(legal_form = "AS", max_results = 3)) == 3L)

  check("S-07", "max_results above the page size paginates",
        nrow(brreg_search(legal_form = "AS", max_results = 250)) == 250L)

  check("S-08", "legal_form filter is honoured", {
    s <- brreg_search(legal_form = "ENK", max_results = 20)
    all(s$legal_form == "ENK")
  })

  check("S-09", "municipality filter is honoured on enheter", {
    s <- brreg_search(municipality_code = "0301", max_results = 20)
    all(s$municipality_code == "0301")
  })

  check("S-10", "municipality filter is honoured on underenheter", {
    s <- brreg_search(municipality_code = "0301", registry = "underenheter",
                      max_results = 20)
    nrow(s) > 0 && all(s$location_municipality_code == "0301" |
                         s$municipality_code == "0301", na.rm = TRUE)
  })

  check("S-11", "nace filter is honoured", {
    s <- brreg_search(nace_code = "64.190", max_results = 20)
    nrow(s) > 0 && all(substr(s$nace_1, 1, 6) == "64.190")
  })

  check("S-12", "min_employees is honoured", {
    s <- brreg_search(min_employees = 500, max_results = 20)
    all(s$employees >= 500, na.rm = TRUE)
  })

  check("S-13", "max_employees is honoured", {
    s <- brreg_search(max_employees = 2, min_employees = 1, max_results = 20)
    all(s$employees <= 2, na.rm = TRUE)
  })

  check("S-14", "bankrupt filter is honoured", {
    s <- brreg_search(bankrupt = TRUE, max_results = 20)
    all(isTRUE(s$bankrupt) | s$bankrupt %in% TRUE)
  })

  check("S-15", "bankrupt on underenheter either filters or signals", {
    r <- withCallingHandlers(
      tryCatch(brreg_search(bankrupt = TRUE, registry = "underenheter", max_results = 5),
               error = function(e) "err"),
      warning = function(w) invokeRestart("muffleWarning"))
    identical(r, "err")
  }, defect = "D-04")

  check("S-16", "parent_org_nr filter is honoured", {
    s <- brreg_search(parent_org_nr = asa, registry = "underenheter", max_results = 20)
    nrow(s) > 0 && all(s$parent_org_nr == asa)
  })

  check("S-17", "combined filters are ANDed", {
    s <- brreg_search(legal_form = "AS", municipality_code = "0301",
                      min_employees = 100, max_results = 10)
    nrow(s) > 0 && all(s$legal_form == "AS") && all(s$municipality_code == "0301")
  })

  check("S-18", "no-match search returns a typed empty tibble", {
    s <- brreg_search(name = "zzzqqxnotanentityname", max_results = 10)
    is_typed_empty(s, c("org_nr", "name"))
  }, defect = "D-05")

  check("S-19", "no-match search still reports total_matches zero", {
    s <- brreg_search(name = "zzzqqxnotanentityname", max_results = 10)
    identical(as.integer(attr(s, "total_matches")), 0L)
  })

  check("S-20", "type = label preserves total_matches", {
    s <- brreg_search(name = "Equinor", max_results = 10, type = "label")
    !is.null(attr(s, "total_matches"))
  })

  check("S-21", "brreg_label(code=) preserves total_matches", {
    s <- brreg_label(base, code = "legal_form")
    !is.null(attr(s, "total_matches"))
  }, defect = "D-07")

  check("S-22", "underenheter registry returns rows", {
    s <- brreg_search(registry = "underenheter", max_results = 10)
    nrow(s) == 10L
  })

  check("S-23", "results are unique on org_nr",
        !any(duplicated(brreg_search(legal_form = "AS", max_results = 300)$org_nr)))

  check("S-24", "pagination is stable across two identical calls", {
    a <- brreg_search(legal_form = "ASA", max_results = 150)$org_nr
    b <- brreg_search(legal_form = "ASA", max_results = 150)$org_nr
    identical(sort(a), sort(b))
  })

  check("S-25", "max_results beyond the API ceiling warns and truncates",
        {
          n <- withCallingHandlers(
            nrow(brreg_search(legal_form = "AS", max_results = 10050)),
            warning = function(w) invokeRestart("muffleWarning"))
          n <= 10000L
        })

  check("S-26", "brreg_underenheter default does not silently truncate a large parent", {
    s <- brreg_underenheter(asa)
    total <- attr(s, "total_matches")
    is.null(total) || nrow(s) >= min(total, 200) &&
      (is.null(total) || total <= nrow(s) || nrow(s) < 200)
  }, defect = "D-08")

  check("S-27", "brreg_underenheter with a large cap retrieves everything", {
    s <- brreg_underenheter(asa, max_results = 10000)
    total <- attr(s, "total_matches")
    is.null(total) || nrow(s) == min(total, 10000)
  })

  check("S-28", "brreg_children returns the ORGL hierarchy", {
    s <- brreg_children(fx$known$orgl, max_results = 50)
    is.data.frame(s)
  })

  check("S-29", "brreg_children on an AS returns a typed empty tibble", {
    s <- brreg_children(asa)
    is_typed_empty(s, c("org_nr", "name")) || nrow(s) > 0
  }, defect = "D-05")

  check("S-30", "brreg_underenheter type = label works",
        is.data.frame(brreg_underenheter(asa, max_results = 5, type = "label")))

  check("S-31", "search never returns list columns", {
    s <- brreg_search(legal_form = "AS", max_results = 50)
    !any(vapply(s, is.list, logical(1)))
  })

  check("S-32", "search column types match the dictionary", {
    s <- brreg_search(legal_form = "AS", max_results = 50)
    d <- tidybrreg::field_dict
    dates <- d$col_name[d$type == "Date"]
    all(vapply(intersect(dates, names(s)), function(c) inherits(s[[c]], "Date"),
               logical(1)))
  })

  check("S-33", "an unreachable filter combination returns empty, not an error", {
    s <- brreg_search(legal_form = "ASA", min_employees = 999999, max_results = 5)
    is.data.frame(s) && nrow(s) == 0L
  })

  check("S-34", "search and entity agree on a single org", {
    s <- brreg_search(name = "EQUINOR ASA", max_results = 50)
    e <- brreg_entity(asa)
    row <- s[s$org_nr == asa, ]
    nrow(row) == 1L && identical(row$name, e$name) &&
      identical(row$legal_form, e$legal_form)
  })

  stress_flush()
}

test_search()
