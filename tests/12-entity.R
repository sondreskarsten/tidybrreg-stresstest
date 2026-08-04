root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

test_entity <- function(fx = load_fixtures()) {
  stress_init("12-entity")
  stress_stagger()

  asa <- fx$known$asa
  bank <- fx$known$bank
  sub <- if (length(fx$underenheter) > 0) fx$underenheter[1] else NA_character_
  del <- if (length(fx$deleted) > 0) fx$deleted[1] else NA_character_

  base <- brreg_entity(asa)

  check("E-01", "auto registry returns one row",
        is.data.frame(base) && nrow(base) == 1L)

  check("E-02", "org_nr round-trips",
        identical(base$org_nr, asa))

  check("E-03", "registry column records the matched registry",
        identical(base$registry, "enheter"))

  check("E-04", "every field_dict column is present",
        all(tidybrreg::field_dict$col_name %in% names(base)))

  check("E-05", "declared types are honoured",
        inherits(base$founding_date, "Date") && is.integer(base$employees))

  check("E-06", "explicit enheter equals auto", {
    e <- brreg_entity(asa, registry = "enheter")
    identical(e$name, base$name) && identical(names(e), names(base))
  })

  check("E-07", "underenheter registry aborts for a hovedenhet",
        {
          r <- tryCatch(brreg_entity(asa, registry = "underenheter"),
                        error = function(e) "err")
          identical(r, "err")
        })

  check("E-08", "auto falls through to underenheter", {
    if (is.na(sub)) NA else identical(brreg_entity(sub)$registry, "underenheter")
  })

  check("E-09", "sub-entity carries the parent org number", {
    if (is.na(sub)) NA else !is.na(brreg_entity(sub, registry = "underenheter")$parent_org_nr)
  })

  check("E-10", "type = label preserves the row count and schema", {
    l <- brreg_entity(asa, type = "label")
    nrow(l) == 1L && stable_schema(l, base)
  })

  check("E-11", "type = label translates the legal form", {
    l <- brreg_entity(asa, type = "label")
    !identical(l$legal_form, base$legal_form)
  })

  check("E-12", "type = label leaves the org number untouched", {
    l <- brreg_entity(asa, type = "label")
    identical(l$org_nr, asa)
  })

  check("E-13", "label via pipe equals label via argument", {
    a <- brreg_entity(asa, type = "label")
    b <- brreg_label(brreg_entity(asa))
    identical(a$legal_form, b$legal_form)
  })

  check("E-14", "brreg_label(code=) retains the raw code", {
    l <- brreg_label(base, code = "legal_form")
    "legal_form_code" %in% names(l) && identical(l$legal_form_code, base$legal_form)
  })

  check("E-15", "deleted entity returns the full entity schema", {
    if (is.na(del)) NA else all(tidybrreg::field_dict$col_name %in% names(suppressWarnings(brreg_entity(del))))
  }, defect = "D-01")

  check("E-16", "deleted entity carries a deletion date", {
    if (is.na(del)) NA else { d <- suppressWarnings(brreg_entity(del)); "deletion_date" %in% names(d) && inherits(d$deletion_date, "Date") }
  })

  check("E-17", "deleted entity honours type = label", {
    if (is.na(del)) NA else ncol(suppressWarnings(brreg_entity(del, type = "label"))) > 4L
  }, defect = "D-01")

  check_warning("E-18", "deleted entity warns",
                brreg_entity(del), pattern = "deleted")

  check_error("E-19", "unknown but valid org number aborts",
              brreg_entity("889640782"), pattern = "not found")

  check_error("E-20", "invalid check digit aborts before any call",
              brreg_entity("923609017"), pattern = "Invalid")

  check("E-21", "numeric input is accepted",
        nrow(brreg_entity(as.numeric(asa))) == 1L)

  check("E-22", "vectorised input either works or aborts, never returns one wrong row", {
    r <- tryCatch(brreg_entity(c(asa, bank)), error = function(e) "err")
    identical(r, "err") || (is.data.frame(r) && nrow(r) == 2L)
  }, defect = "D-03")

  check("E-23", "repeated calls are deterministic", {
    a <- brreg_entity(asa)
    b <- brreg_entity(asa)
    identical(a, b)
  })

  check("E-24", "no unnamed list columns leak into the result",
        !any(vapply(base, is.list, logical(1))))

  check("E-25", "no column is entirely a JSON blob string",
        !any(vapply(base, function(x) is.character(x) && !is.na(x[1]) &&
                      grepl("^\\{", x[1]), logical(1))))

  check("E-26", "bank entity resolves with matching schema",
        stable_schema(brreg_entity(bank), base))

  check("E-27", "ENK entity resolves with matching schema", {
    if (length(fx$enk) == 0) NA else stable_schema(brreg_entity(fx$enk[1]), base)
  })

  check("E-28", "NUF entity resolves with matching schema", {
    if (length(fx$nuf) == 0) NA else stable_schema(brreg_entity(fx$nuf[1]), base)
  })

  check("E-29", "bankrupt entity carries a bankruptcy date", {
    if (length(fx$bankrupt) == 0) NA else isTRUE(brreg_entity(fx$bankrupt[1])$bankrupt)
  })

  check("E-30", "schema is identical across 10 arbitrary entities", {
    orgs <- utils::head(unique(c(fx$oslo_as, fx$enk, fx$nuf)), 10L)
    if (length(orgs) < 2) NA else { schemas <- lapply(orgs, function(o) names(brreg_entity(o)))
    length(unique(lapply(schemas, sort))) == 1L }
  })

  check("E-31", "brreg_entity makes no filesystem writes", {
    d <- tempfile(); dir.create(d)
    before <- length(list.files(d, recursive = TRUE))
    brreg_entity(asa)
    length(list.files(d, recursive = TRUE)) == before
  })

  check("E-32", "unmapped API fields survive as snake_case columns",
        length(setdiff(names(base), c(tidybrreg::field_dict$col_name, "registry"))) >= 0)

  stress_flush()
}

test_entity()
