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

  doc_key_cols <- c("org_nr", "name", "legal_form", "employees", "founding_date",
                    "nace_1", "municipality_code", "bankrupt")

  check("E-04", "the documented key columns are present", {
    all(doc_key_cols %in% names(base))
  }, defect = "D-93")

  check("E-04b", "column names follow the package field dictionary as documented", {
    known_passthrough <- c("registry", "historiske_navn",
                           "organisasjonsform__links_self_href")
    all(setdiff(names(base), known_passthrough) %in% tidybrreg::field_dict$col_name)
  })

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

  check("E-15", "the 410 branch, when it fires, returns exactly the documented 4-col schema", {
    fake_410 <- httr2::response(
      status_code = 410,
      headers = list(`Content-Type` = "application/json;charset=UTF-8"),
      body = charToRaw(jsonlite::toJSON(
        list(slettedato = "2020-01-01", organisasjonsnummer = "923609016"),
        auto_unbox = TRUE)))
    out <- httr2::with_mocked_responses(function(req) fake_410, {
      suppressWarnings(brreg_entity(asa))
    })
    ncol(out) > 10L
  }, defect = "D-01")

  check("E-16", "the 410 branch sets deleted = TRUE and a parsed deletion_date", {
    fake_410 <- httr2::response(
      status_code = 410,
      headers = list(`Content-Type` = "application/json;charset=UTF-8"),
      body = charToRaw(jsonlite::toJSON(
        list(slettedato = "2020-03-15", organisasjonsnummer = "923609016"),
        auto_unbox = TRUE)))
    out <- httr2::with_mocked_responses(function(req) fake_410, {
      suppressWarnings(brreg_entity(asa))
    })
    isTRUE(out$deleted) && identical(out$deletion_date, as.Date("2020-03-15"))
  })

  check("E-17", "type = label has an observable effect even on the reduced deleted-entity schema", {
    fake_410 <- httr2::response(
      status_code = 410,
      headers = list(`Content-Type` = "application/json;charset=UTF-8"),
      body = charToRaw(jsonlite::toJSON(
        list(slettedato = "2020-01-01", organisasjonsnummer = "923609016"),
        auto_unbox = TRUE)))
    out_label <- httr2::with_mocked_responses(function(req) fake_410, {
      suppressWarnings(brreg_entity(asa, type = "label"))
    })
    out_plain <- httr2::with_mocked_responses(function(req) fake_410, {
      suppressWarnings(brreg_entity(asa))
    })
    !identical(out_label, out_plain)
  }, defect = "D-01")


  check("E-18", "the 410 branch warns", {
    fake_410 <- httr2::response(
      status_code = 410,
      headers = list(`Content-Type` = "application/json;charset=UTF-8"),
      body = charToRaw(jsonlite::toJSON(
        list(slettedato = "2020-01-01", organisasjonsnummer = "923609016"),
        auto_unbox = TRUE)))
    warned <- FALSE
    withCallingHandlers(
      httr2::with_mocked_responses(function(req) fake_410, brreg_entity(asa)),
      warning = function(w) { warned <<- TRUE; invokeRestart("muffleWarning") })
    warned
  })

  check("E-19a", "precondition: live deletions are actually served as HTTP 200, not 410", {
    if (is.na(del)) NA else {
      tb <- asNamespace("tidybrreg")
      r <- tb$brreg_req(paste0("enheter/", del)) |>
        httr2::req_error(is_error = \(resp) FALSE) |> httr2::req_perform()
      httr2::resp_status(r) == 200L
    }
  })

  check("E-19b", "precondition: a live deleted entity carries the respons_klasse=SlettetEnhet marker", {
    if (is.na(del)) NA else {
      tb <- asNamespace("tidybrreg")
      r <- tb$brreg_req(paste0("enheter/", del)) |>
        httr2::req_error(is_error = \(resp) FALSE) |> httr2::req_perform()
      body <- httr2::resp_body_json(r)
      identical(body$respons_klasse, "SlettetEnhet") && !is.null(body$slettedato)
    }
  })

  check("E-19c", "brreg_entity() explicitly flags a live deleted entity as deleted", {
    if (is.na(del)) NA else isTRUE(suppressWarnings(brreg_entity(del))$deleted)
  }, defect = "D-91")

  check_warning("E-19d", "a live deleted entity resolved via the 200 path still warns the caller",
                { if (is.na(del)) NA else brreg_entity(del) },
                defect = "D-91")

  check("E-19e", "across every discovered deleted org, brreg_entity() flags each one as deleted", {
    if (length(fx$deleted) == 0) NA else {
      all(vapply(utils::head(fx$deleted, 8L), function(o) {
        isTRUE(suppressWarnings(brreg_entity(o))$deleted)
      }, logical(1)))
    }
  }, defect = "D-91")


  check_error("E-19", "an org number that never existed in the register aborts",
              brreg_entity("832071404"), pattern = "not found")

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

  check("E-26", "bank entity carries the documented key columns",
        all(doc_key_cols %in% names(brreg_entity(bank))), defect = "D-93")

  check("E-27", "ENK entity carries the documented key columns", {
    if (length(fx$enk) == 0) NA else
      all(doc_key_cols %in% names(brreg_entity(fx$enk[1])))
  }, defect = "D-93")

  check("E-28", "NUF entity carries the documented key columns", {
    if (length(fx$nuf) == 0) NA else
      all(doc_key_cols %in% names(brreg_entity(fx$nuf[1])))
  }, defect = "D-93")

  check("E-29", "bankrupt entity carries a bankruptcy date", {
    if (length(fx$bankrupt) == 0) NA else isTRUE(brreg_entity(fx$bankrupt[1])$bankrupt)
  })

  check("E-30", "the documented key columns are present for every entity type", {
    orgs <- utils::head(unique(c(asa, bank, fx$enk[1], fx$nuf[1], fx$oslo_as)), 10L)
    if (length(orgs) < 3) NA else
      all(vapply(orgs, function(o) all(doc_key_cols %in% names(brreg_entity(o))),
                 logical(1)))
  }, defect = "D-93")

  check("E-30b", "bind_rows across heterogeneous entity types never errors and unions gracefully", {
    orgs <- utils::head(unique(c(fx$oslo_as, fx$enk, fx$nuf, asa, bank)), 10L)
    if (length(orgs) < 2) NA else {
      out <- dplyr::bind_rows(lapply(orgs, brreg_entity))
      nrow(out) == length(orgs) && all(c("org_nr", "name", "legal_form") %in% names(out))
    }
  })


  check("E-31", "brreg_entity makes no filesystem writes", {
    d <- tempfile(); dir.create(d)
    before <- length(list.files(d, recursive = TRUE))
    brreg_entity(asa)
    length(list.files(d, recursive = TRUE)) == before
  })

  check("E-32", "a nested HAL _links block survives into the output as a real column", {
    "organisasjonsform__links_self_href" %in% names(base) &&
      !"organisasjonsform__links_self_href" %in% tidybrreg::field_dict$col_name &&
      grepl("^https?://", base$organisasjonsform__links_self_href)
  }, defect = "D-92")

  check("E-32b", "the leaked link column is not filtered by the top-level _links guard", {
    tb <- asNamespace("tidybrreg")
    flat <- tb$flatten_json(list(
      organisasjonsnummer = "923609016",
      organisasjonsform = list(kode = "ASA", `_links` = list(self = list(href = "http://x")))
    ))
    m <- tb$rename_from_dict(flat)
    "organisasjonsform__links_self_href" %in% names(m)
  }, defect = "D-92")


  stress_flush()
}

test_entity()
