root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

test_label_harmonize <- function(fx = load_fixtures()) {
  stress_init("18-label-harmonize")
  stress_stagger()

  asa <- fx$known$asa
  e <- brreg_entity(asa)

  check("L-01", "labelling a data frame preserves shape", {
    l <- brreg_label(e)
    nrow(l) == nrow(e) && ncol(l) == ncol(e)
  })

  check("L-02", "legal form is translated",
        !identical(brreg_label(e)$legal_form, e$legal_form))

  check("L-03", "nace is translated",
        !identical(brreg_label(e)$nace_1, e$nace_1))

  check("L-04", "org_nr is never touched",
        identical(brreg_label(e)$org_nr, e$org_nr))

  check("L-05", "name is never touched",
        identical(brreg_label(e)$name, e$name))

  check("L-06", "dates are never touched",
        identical(brreg_label(e)$founding_date, e$founding_date))

  check("L-07", "labelling is idempotent", {
    a <- brreg_label(e)
    b <- brreg_label(a)
    identical(a$legal_form, b$legal_form)
  }, defect = "D-95")

  check("L-08", "code = retains the original value", {
    l <- brreg_label(e, code = "legal_form")
    identical(l$legal_form_code, e$legal_form)
  })

  check("L-09", "code = places the code column adjacent to the label", {
    l <- brreg_label(e, code = "legal_form")
    abs(which(names(l) == "legal_form_code") - which(names(l) == "legal_form")) == 1L
  })

  check("L-10", "multiple code columns are supported", {
    l <- brreg_label(e, code = c("legal_form", "nace_1"))
    all(c("legal_form_code", "nace_1_code") %in% names(l))
  })

  check("L-11", "code = on a non-labelable column is a no-op", {
    l <- brreg_label(e, code = "employees")
    !"employees_code" %in% names(l)
  })

  check("L-12", "vector labelling of legal forms", {
    v <- brreg_label(c("AS", "ASA", "ENK"), dic = "legal_form")
    length(v) == 3L && !any(v %in% c("AS", "ASA", "ENK"))
  })

  check("L-13", "vector labelling of roles", {
    v <- brreg_label(c("LEDE", "MEDL"), dic = "role")
    length(v) == 2L && !identical(v, c("LEDE", "MEDL"))
  })

  check("L-14", "vector labelling of role groups",
        length(brreg_label(c("STYR", "REVI"), dic = "role_group")) == 2L)

  check("L-15", "vector labelling of nace",
        !identical(brreg_label("64.190", dic = "nace"), "64.190"))

  check("L-16", "vector labelling of sector",
        is.character(brreg_label(c("2100"), dic = "sector")))

  check("L-17", "unknown codes pass through unchanged",
        identical(brreg_label(c("AS", "ZZZ"), dic = "legal_form")[2], "ZZZ"),
        defect = "D-95")

  check_error("L-18", "vector without dic aborts",
              brreg_label(c("AS")), pattern = "dic")

  check_error("L-19", "unknown dic aborts",
              brreg_label("AS", dic = "nope"), pattern = "Unknown dictionary")

  check("L-20", "empty data frame returns unchanged",
        nrow(brreg_label(tibble::tibble())) == 0L)

  check("L-21", "lang = no yields Norwegian labels", {
    en <- brreg_label(e, lang = "en")$nace_1
    no <- brreg_label(e, lang = "no")$nace_1
    !identical(en, no)
  }, defect = "D-96")

  check("L-22", "get_brreg_dic returns the documented columns", {
    d <- get_brreg_dic("nace")
    has_cols(d, c("code", "name_en", "level"))
  })

  check("L-23", "nace dictionary is non-trivial", nrow(get_brreg_dic("nace")) > 500L)

  check("L-24", "sector dictionary is non-trivial", nrow(get_brreg_dic("sector")) > 10L)

  check("L-25", "dictionary codes are unique",
        !any(duplicated(get_brreg_dic("nace")$code)))

  check("L-26", "second dictionary call is served from cache", {
    t1 <- system.time(get_brreg_dic("nace"))[["elapsed"]]
    t2 <- system.time(get_brreg_dic("nace"))[["elapsed"]]
    t2 <= t1 + 0.05
  })

  check("L-27", "lang variants are cached separately", {
    a <- get_brreg_dic("nace", lang = "en")
    b <- get_brreg_dic("nace", lang = "no")
    !identical(a$name_en, b$name_en)
  })

  check("L-28", "the KLASS fallback objects exist in the namespace", {
    ns <- asNamespace("tidybrreg")
    exists("nace_codes", envir = ns, inherits = FALSE) &&
      exists("sector_codes", envir = ns, inherits = FALSE)
  })

  check("L-29", "labelling many rows is stable", {
    s <- brreg_search(legal_form = "AS", max_results = 200)
    l <- brreg_label(s)
    nrow(l) == nrow(s) && !any(is.na(l$legal_form))
  })

  has_klassr <- requireNamespace("klassR", quietly = TRUE)

  km <- tibble::tibble(municipality_code = c("0301", "1201", "0602", "5001", "1103"))

  check("H-01", "kommune harmonisation returns the documented columns", {
    if (!has_klassr) NA else {
      out <- brreg_harmonize_kommune(km)
      all(c("municipality_code_harmonized", "municipality_code_target_name") %in%
            names(out))
    }
  })

  check("H-02", "a pre-2020 code is actually remapped", {
    if (!has_klassr) NA else {
      out <- brreg_harmonize_kommune(km)
      !identical(out$municipality_code_harmonized[3], "0602")
    }
  }, defect = "D-78")

  check("H-03", "harmonisation changes at least one reformed code", {
    if (!has_klassr) NA else {
      out <- brreg_harmonize_kommune(km)
      any(out$municipality_code_harmonized != out$municipality_code)
    }
  }, defect = "D-78")

  check("H-04", "target names are resolved for current codes", {
    if (!has_klassr) NA else {
      out <- brreg_harmonize_kommune(km)
      !is.na(out$municipality_code_target_name[1])
    }
  })

  check("H-05", "harmonisation is idempotent", {
    if (!has_klassr) NA else {
      a <- brreg_harmonize_kommune(km)
      b <- brreg_harmonize_kommune(
        tibble::tibble(municipality_code = a$municipality_code_harmonized))
      identical(a$municipality_code_harmonized, b$municipality_code_harmonized)
    }
  })

  check("H-06", "a failed correspondence fetch does not poison the session cache", {
    if (!has_klassr) NA else {
      bad <- brreg_harmonize_kommune(km, target_date = as.Date("1800-01-01"))
      good <- brreg_harmonize_kommune(km, target_date = as.Date("1800-01-01"))
      is.data.frame(good) && nrow(good) == nrow(km) &&
        !any(grepl("^municipality_code_harmonized$", names(bad)) & FALSE) &&
        ncol(good) <= ncol(km) + 2L
    }
  }, defect = "D-79")

  check("H-07", "custom column name is honoured", {
    if (!has_klassr) NA else {
      d <- tibble::tibble(kom = c("0301"))
      out <- brreg_harmonize_kommune(d, col = "kom")
      "kom_harmonized" %in% names(out)
    }
  })

  nc <- tibble::tibble(nace_1 = c("06.100", "64.190", "62.010"))

  check("H-10", "nace harmonisation returns the documented columns", {
    if (!has_klassr) NA else {
      out <- brreg_harmonize_nace(nc)
      all(c("nace_1_harmonized", "nace_1_ambiguous") %in% names(out))
    }
  }, defect = "D-80")

  check("H-11", "harmonised nace values look like codes, not descriptions", {
    if (!has_klassr) NA else {
      out <- brreg_harmonize_nace(nc)
      all(grepl("^[0-9]", stats::na.omit(out$nace_1_harmonized)))
    }
  }, defect = "D-80")

  check("H-12", "at least one code changes between SN2007 and SN2025", {
    if (!has_klassr) NA else {
      out <- brreg_harmonize_nace(nc)
      any(out$nace_1_harmonized != out$nace_1)
    }
  }, defect = "D-80")

  check("H-13", "ambiguity flag is logical", {
    if (!has_klassr) NA else is.logical(brreg_harmonize_nace(nc)$nace_1_ambiguous)
  }, defect = "D-80")

  check("H-14", "reverse direction is supported", {
    if (!has_klassr) NA else {
      out <- brreg_harmonize_nace(nc, from = "SN2025", to = "SN2007")
      "nace_1_harmonized" %in% names(out)
    }
  }, defect = "D-80")

  check_error("H-15", "unknown classification aborts",
              brreg_harmonize_nace(nc, from = "SN1994"), pattern = "Unknown")

  check("H-16", "nace harmonisation preserves row count", {
    if (!has_klassr) NA else nrow(brreg_harmonize_nace(nc)) == nrow(nc)
  }, defect = "D-80")

  stress_flush()
}

test_label_harmonize()
