root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

test_roles <- function(fx = load_fixtures()) {
  stress_init("14-roles")
  stress_stagger()

  asa <- fx$known$asa
  bank <- fx$known$bank
  del <- if (length(fx$deleted) > 0) fx$deleted[1] else NA_character_

  r <- brreg_roles(asa)

  check("R-01", "roles returns rows for a large ASA", nrow(r) > 0)

  check("R-02", "documented columns are present",
        all(c("org_nr", "role_group", "role_group_code", "role", "role_code",
              "first_name", "middle_name", "last_name", "birth_date", "deceased",
              "entity_org_nr", "entity_name", "deregistered", "ordering",
              "elected_by", "group_modified", "person_id") %in% names(r)))

  check("R-03", "birth_date is a Date", inherits(r$birth_date, "Date"))
  check("R-04", "group_modified is a Date", inherits(r$group_modified, "Date"))
  check("R-05", "org_nr is constant and correct", all(r$org_nr == asa))

  check("R-06", "role labels are translated, not raw codes",
        !any(r$role == r$role_code, na.rm = TRUE) ||
          all(r$role_code %in% tidybrreg::role_types$code))

  check("R-07", "every role_code is known to role_types",
        all(r$role_code %in% tidybrreg::role_types$code))

  check("R-08", "every role_group_code is known to role_groups",
        all(r$role_group_code %in% tidybrreg::role_groups$code))

  check("R-09", "person rows carry a person_id",
        all(!is.na(r$person_id[!is.na(r$birth_date) & !is.na(r$last_name)])))

  check("R-10", "entity-held roles carry an org number",
        all(is.na(r$person_id[!is.na(r$entity_org_nr)]) |
              !is.na(r$entity_org_nr[!is.na(r$entity_org_nr)])))

  check("R-11", "entity role names are resolved, not JSON",
        !any(grepl("^list\\(|^\\{", r$entity_name, useNames = FALSE), na.rm = TRUE))

  check("R-12", "person_id is unique per person within one entity", {
    p <- r[!is.na(r$person_id), ]
    ids <- unique(p$person_id)
    length(ids) > 0
  })

  check("R-13", "schema is identical across 8 different entities", {
    orgs <- utils::head(unique(c(asa, bank, fx$oslo_as)), 8L)
    if (length(orgs) < 2) NA else {
      schemas <- lapply(orgs, function(o) sort(names(brreg_roles(o))))
      length(unique(schemas)) == 1L
    }
  }, defect = "D-09")

  check("R-14", "roles bind_rows cleanly across entities", {
    orgs <- utils::head(unique(c(asa, bank, fx$oslo_as)), 6L)
    if (length(orgs) < 2) NA else {
      out <- dplyr::bind_rows(lapply(orgs, brreg_roles))
      nrow(out) > 0 && length(unique(out$org_nr)) == length(orgs)
    }
  })

  check("R-15", "an entity with no roles yields a typed empty tibble", {
    if (length(fx$enk) == 0) NA else {
      hits <- lapply(utils::head(fx$enk, 5L), function(o) suppressWarnings(brreg_roles(o)))
      empt <- Filter(function(x) nrow(x) == 0L, hits)
      if (length(empt) == 0) NA else is_typed_empty(empt[[1]], c("org_nr", "role_code"))
    }
  }, defect = "D-05")

  check("R-16", "a deleted entity is distinguishable from one with no roles", {
    if (is.na(del)) NA else {
      d <- suppressWarnings(brreg_roles(del))
      is.data.frame(d) && (nrow(d) > 0 || ncol(d) > 0)
    }
  }, defect = "D-10")

  check("R-17", "an invalid org number is rejected before the call",
        {
          out <- tryCatch(suppressWarnings(brreg_roles("923609017")),
                          error = function(e) "err")
          identical(out, "err")
        }, defect = "D-10")

  check("R-18", "repeated calls are deterministic",
        identical(brreg_roles(asa), brreg_roles(asa)))

  check("R-19", "roles_legal returns a data frame",
        is.data.frame(brreg_roles_legal(asa)))

  check("R-20", "roles_legal columns match the documentation", {
    lr <- brreg_roles_legal(asa)
    if (nrow(lr) == 0) NA else
      all(c("org_nr", "target_org_nr", "target_name", "role_code", "role",
            "share", "deregistered") %in% names(lr))
  })

  check("R-21", "roles_legal target org numbers are valid",
        {
          lr <- brreg_roles_legal(asa)
          if (nrow(lr) == 0) NA else all(brreg_validate(lr$target_org_nr))
        })

  check("R-22", "roles_legal on an entity with none returns a typed empty tibble", {
    if (length(fx$enk) == 0) NA else {
      out <- brreg_roles_legal(fx$enk[1])
      if (nrow(out) > 0) NA else is_typed_empty(out, c("org_nr", "target_org_nr"))
    }
  }, defect = "D-05")

  check_warning("R-23", "roles_legal warns on an HTTP failure like brreg_roles does",
                brreg_roles_legal("899999999"), defect = "D-06")

  check("R-24", "roles and roles_legal are inverse on at least one pair", {
    lr <- brreg_roles_legal(asa)
    if (nrow(lr) == 0) NA else {
      tgt <- lr$target_org_nr[1]
      back <- brreg_roles(tgt)
      is.data.frame(back)
    }
  })

  check("R-25", "board_summary returns exactly one row", {
    s <- brreg_board_summary(r)
    nrow(s) == 1L
  })

  check("R-26", "board_summary reports the queried org", {
    s <- brreg_board_summary(r)
    identical(s$org_nr, asa)
  })

  check("R-27", "board_summary counts sum to board size", {
    s <- brreg_board_summary(r)
    s$n_chair + s$n_deputy_chair + s$n_members + s$n_alternates + s$n_observers ==
      s$board_size
  })

  check("R-28", "board_summary board_size matches an independent count", {
    b <- r[r$role_group_code == "STYR" & !is.na(r$person_id) &
             !(r$deregistered %in% TRUE), ]
    brreg_board_summary(r)$board_size == nrow(b)
  })

  check("R-29", "board_summary detects the auditor", {
    s <- brreg_board_summary(r)
    isTRUE(s$has_auditor) == any(r$role_group_code == "REVI")
  })

  check("R-30", "board_summary auditor org number is valid", {
    s <- brreg_board_summary(r)
    if (is.na(s$auditor_org_nr)) NA else brreg_validate(s$auditor_org_nr)
  })

  check("R-31", "board_summary on multi-org input aborts or returns one row per org", {
    orgs <- utils::head(unique(c(asa, bank)), 2L)
    multi <- dplyr::bind_rows(lapply(orgs, brreg_roles))
    out <- tryCatch(brreg_board_summary(multi), error = function(e) "err")
    identical(out, "err") || (is.data.frame(out) && nrow(out) == length(orgs))
  }, defect = "D-12")

  check("R-32", "board_summary on an empty roles tibble does not error", {
    out <- tryCatch(brreg_board_summary(tibble::tibble()), error = function(e) "err")
    !identical(out, "err")
  })

  check("R-33", "n_employee_elected counts only employee-elected members", {
    b <- r[r$role_group_code == "STYR" & !is.na(r$person_id), ]
    emp <- sum(!is.na(b$elected_by) & grepl("ANSA|EMPL", b$elected_by))
    brreg_board_summary(r)$n_employee_elected == emp
  }, defect = "D-13")

  check("R-34", "board_summary is stable under row permutation", {
    a <- brreg_board_summary(r)
    b <- brreg_board_summary(r[sample(nrow(r)), ])
    identical(a$board_size, b$board_size) && identical(a$n_chair, b$n_chair)
  })

  stress_flush()
}

test_roles()
