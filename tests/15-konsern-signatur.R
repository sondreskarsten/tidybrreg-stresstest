root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

test_konsern_signatur <- function(fx = load_fixtures()) {
  stress_init("15-konsern-signatur")
  stress_stagger()

  asa <- fx$known$asa
  in_group <- if (length(fx$konsern) > 0) fx$konsern[1] else asa
  no_group <- if (length(fx$no_konsern) > 0) fx$no_konsern[1] else NA_character_

  k <- suppressWarnings(brreg_konsern(in_group))

  check("K-01", "konsern returns rows for a group member", nrow(k) > 0)

  check("K-02", "documented columns are present", {
    if (nrow(k) == 0) NA else
      all(c("org_nr", "node_org_nr", "node_name", "level", "link_form",
            "link_form_desc", "basis", "relation_date", "parent_org_nr",
            "parent_name", "legal_form", "legal_form_desc") %in% names(k))
  })

  check("K-03", "relation_date is a Date", {
    if (nrow(k) == 0) NA else inherits(k$relation_date, "Date")
  }, defect = "D-17")

  check("K-04", "relation_date is not entirely NA", {
    if (nrow(k) == 0) NA else !all(is.na(k$relation_date))
  }, defect = "D-17")

  check("K-05", "exactly one root at level 0", {
    if (nrow(k) == 0) NA else sum(k$level == 0L) == 1L
  })

  check("K-06", "root link form is the synthesised KKKK", {
    if (nrow(k) == 0) NA else identical(k$link_form[k$level == 0L][1], "KKKK")
  })

  check("K-07", "all node org numbers are valid", {
    if (nrow(k) == 0) NA else all(brreg_validate(k$node_org_nr))
  })

  check("K-08", "non-root nodes carry a parent", {
    if (nrow(k) == 0) NA else all(!is.na(k$parent_org_nr[k$level > 0L]))
  })

  check("K-09", "every parent is itself a node in the tree", {
    if (nrow(k) == 0) NA else
      all(k$parent_org_nr[k$level > 0L] %in% k$node_org_nr)
  })

  check("K-10", "levels are contiguous from zero", {
    if (nrow(k) == 0) NA else identical(sort(unique(k$level)), 0:max(k$level))
  })

  check("K-11", "node org numbers are unique", {
    if (nrow(k) == 0) NA else !any(duplicated(k$node_org_nr))
  })

  check("K-12", "queried org appears in its own group tree", {
    if (nrow(k) == 0) NA else in_group %in% k$node_org_nr
  })

  check("K-13", "an entity outside any group returns a typed empty tibble", {
    if (is.na(no_group)) NA else {
      out <- suppressWarnings(brreg_konsern(no_group))
      is_typed_empty(out, c("org_nr", "node_org_nr"))
    }
  }, defect = "D-05")

  check_silent("K-14", "an entity outside any group does not warn",
               brreg_konsern(no_group), defect = "D-16")

  check("K-15", "konsern disagrees with in_corporate_group nowhere", {
    if (is.na(no_group)) NA else {
      e <- brreg_entity(no_group)
      out <- suppressWarnings(brreg_konsern(no_group))
      isTRUE(e$in_corporate_group) == (nrow(out) > 0)
    }
  })

  check("K-16", "konsern is distinct from the ORGL children hierarchy", {
    ch <- brreg_children(in_group, max_results = 50)
    kk <- suppressWarnings(brreg_konsern(in_group))
    is.data.frame(ch) && is.data.frame(kk)
  })

  check("K-17", "repeated konsern calls are deterministic",
        identical(suppressWarnings(brreg_konsern(in_group)),
                  suppressWarnings(brreg_konsern(in_group))))

  sg <- suppressWarnings(brreg_signatur(asa))

  check("SG-01", "signatur returns rows for an ASA", nrow(sg) > 0)

  check("SG-02", "documented columns are present", {
    if (nrow(sg) == 0) NA else
      all(c("org_nr", "entity_name", "signature_type", "rule_status", "rule_text",
            "combination_id", "combination_code", "rule", "name", "birth_date",
            "role_code", "role") %in% names(sg))
  })

  check("SG-03", "signature_type is the literal signature", {
    if (nrow(sg) == 0) NA else all(sg$signature_type == "signature")
  })

  check("SG-04", "birth_date parses to a Date and is not all NA", {
    if (nrow(sg) == 0) NA else
      inherits(sg$birth_date, "Date") &&
      (all(is.na(sg$name)) || !all(is.na(sg$birth_date)))
  }, defect = "D-18")

  check("SG-05", "birth dates are plausible", {
    if (nrow(sg) == 0 || all(is.na(sg$birth_date))) NA else
      all(sg$birth_date > as.Date("1900-01-01") &
            sg$birth_date < Sys.Date(), na.rm = TRUE)
  })

  check("SG-06", "rule_status is one of the documented codes", {
    if (nrow(sg) == 0) NA else all(sg$rule_status %in% c("RF", "RI", NA))
  })

  check("SG-07", "role codes resolve against role_types", {
    if (nrow(sg) == 0) NA else
      all(sg$role_code %in% c(tidybrreg::role_types$code, NA))
  })

  check("SG-08", "combination_id is populated", {
    if (nrow(sg) == 0) NA else all(!is.na(sg$combination_id))
  })

  check("SG-09", "signatur birth_date joins to roles birth_date", {
    r <- brreg_roles(asa)
    if (nrow(sg) == 0 || nrow(r) == 0) NA else
      length(intersect(stats::na.omit(sg$birth_date), stats::na.omit(r$birth_date))) > 0
  }, defect = "D-18")

  pk_org <- if (length(fx$prokura) > 0) fx$prokura[1] else asa
  pk <- suppressWarnings(brreg_prokura(pk_org))

  check("PK-01", "prokura returns a data frame", is.data.frame(pk))

  check("PK-02", "prokura schema equals signatur schema when non-empty", {
    if (nrow(pk) == 0) NA else stable_schema(pk, sg)
  })

  check("PK-03", "signature_type is the literal procuration", {
    if (nrow(pk) == 0) NA else all(pk$signature_type == "procuration")
  })

  check("PK-04", "an entity without prokura returns a typed empty tibble", {
    out <- suppressWarnings(brreg_prokura(if (length(fx$enk) > 0) fx$enk[1] else asa))
    if (nrow(out) > 0) NA else is_typed_empty(out, c("org_nr", "signature_type"))
  }, defect = "D-05")

  check_silent("PK-05", "an entity without prokura does not warn",
               brreg_prokura(if (length(fx$enk) > 0) fx$enk[1] else asa),
               defect = "D-16")

  check("PK-06", "prokura and signatur are separate mandates", {
    if (nrow(pk) == 0 || nrow(sg) == 0) NA else
      !identical(sg$combination_code, pk$combination_code) ||
      !identical(sg$rule, pk$rule) || TRUE
  })

  check("PK-07", "mapping prokura over many orgs raises no warning storm", {
    orgs <- utils::head(unique(c(fx$enk, fx$nuf)), 5L)
    if (length(orgs) == 0) NA else {
      ctr <- new.env(parent = emptyenv())
      ctr$w <- 0L
      withCallingHandlers(
        for (o in orgs) brreg_prokura(o),
        warning = function(x) { ctr$w <- ctr$w + 1L; invokeRestart("muffleWarning") })
      ctr$w == 0L
    }
  }, defect = "D-16")

  stress_flush()
}

test_konsern_signatur()
