root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

test_governance <- function(fx = load_fixtures()) {
  stress_init("16-governance")
  stress_stagger()

  asa <- fx$known$asa
  bank <- fx$known$bank
  roles <- dplyr::bind_rows(lapply(c(asa, bank), brreg_roles))

  has_tidygraph <- requireNamespace("tidygraph", quietly = TRUE)

  check("G-01", "board network builds from org numbers", {
    if (!has_tidygraph) NA else {
      g <- brreg_board_network(c(asa, bank))
      inherits(g, "tbl_graph")
    }
  })

  check("G-02", "board network builds from pre-fetched roles", {
    if (!has_tidygraph) NA else inherits(brreg_board_network(roles_data = roles), "tbl_graph")
  })

  check("G-03", "node count equals distinct entities plus distinct persons", {
    if (!has_tidygraph) NA else {
      g <- brreg_board_network(roles_data = roles)
      n <- tidygraph::as_tibble(g, "nodes")
      nrow(n) == length(unique(roles$org_nr)) +
        length(unique(stats::na.omit(roles$person_id)))
    }
  })

  check("G-04", "node types are exactly entity and person", {
    if (!has_tidygraph) NA else {
      n <- tidygraph::as_tibble(brreg_board_network(roles_data = roles), "nodes")
      setequal(unique(n$node_type), c("entity", "person"))
    }
  })

  check("G-05", "entity nodes are labelled with the entity's own name", {
    if (!has_tidygraph) NA else {
      n <- tidygraph::as_tibble(brreg_board_network(roles_data = roles), "nodes")
      ent <- n[n$node_type == "entity", ]
      if (!"entity_name" %in% names(ent)) NA else {
        truth <- brreg_entity(asa)$name
        got <- ent$entity_name[ent$name == asa]
        length(got) == 1L && (is.na(got) || identical(got, truth))
      }
    }
  }, defect = "D-19")

  check("G-06", "edge count equals person-held role rows", {
    if (!has_tidygraph) NA else {
      g <- brreg_board_network(roles_data = roles)
      nrow(tidygraph::as_tibble(g, "edges")) == sum(!is.na(roles$person_id))
    }
  })

  check("G-07", "no edge references a missing node", {
    if (!has_tidygraph) NA else {
      g <- brreg_board_network(roles_data = roles)
      e <- tidygraph::as_tibble(g, "edges")
      n <- tidygraph::as_tibble(g, "nodes")
      all(e$from <= nrow(n)) && all(e$to <= nrow(n))
    }
  })

  check_error("G-08", "no arguments aborts", brreg_board_network(),
              pattern = "org_nrs")

  check_error("G-09", "empty roles aborts",
              brreg_board_network(roles_data = tibble::tibble(org_nr = character(),
                                                             person_id = character())),
              pattern = "No role data")

  check("G-10", "an interlock across two firms is represented", {
    if (!has_tidygraph) NA else {
      shared <- intersect(
        stats::na.omit(roles$person_id[roles$org_nr == asa]),
        stats::na.omit(roles$person_id[roles$org_nr == bank]))
      g <- brreg_board_network(roles_data = roles)
      e <- tidygraph::as_tibble(g, "edges")
      length(shared) == 0 || nrow(e) > 0
    }
  })

  firms <- brreg_search(legal_form = "AS", municipality_code = "0301",
                        max_results = 200)

  sv <- brreg_survival_data(firms)

  check("SV-01", "survival columns are added",
        all(c("entry_date", "exit_date", "duration_years", "event") %in% names(sv)))

  check("SV-02", "row count is preserved", nrow(sv) == nrow(firms))

  check("SV-03", "entry_date is a Date", inherits(sv$entry_date, "Date"))
  check("SV-04", "exit_date is a Date", inherits(sv$exit_date, "Date"))
  check("SV-05", "event is 0/1 integer",
        is.integer(sv$event) && all(sv$event %in% c(0L, 1L)))

  check("SV-06", "duration is never negative",
        all(sv$duration_years >= 0, na.rm = TRUE))

  check("SV-07", "duration is finite where entry is known",
        all(is.finite(sv$duration_years[!is.na(sv$entry_date)])))

  check("SV-08", "event 1 implies a non-NA exit date",
        all(!is.na(sv$exit_date[sv$event == 1L])))

  check("SV-09", "event 0 implies an NA exit date",
        all(is.na(sv$exit_date[sv$event == 0L])))

  check("SV-10", "censored duration matches the censoring date", {
    cen <- sv[sv$event == 0L & !is.na(sv$entry_date), ]
    if (nrow(cen) == 0) NA else {
      expected <- as.numeric(difftime(Sys.Date(), cen$entry_date, units = "days")) / 365.25
      max(abs(expected - cen$duration_years), na.rm = TRUE) < 0.01
    }
  })

  check("SV-11", "explicit censoring_date is honoured", {
    s2 <- brreg_survival_data(firms, censoring_date = "2020-01-01")
    cen <- s2[s2$event == 0L & !is.na(s2$entry_date), ]
    if (nrow(cen) == 0) NA else {
      expected <- as.numeric(difftime(as.Date("2020-01-01"), cen$entry_date,
                                      units = "days")) / 365.25
      max(abs(expected - cen$duration_years), na.rm = TRUE) < 0.01
    }
  })

  check("SV-12", "entry_var = registration_date works", {
    s2 <- brreg_survival_data(firms, entry_var = "registration_date")
    inherits(s2$entry_date, "Date") && !all(is.na(s2$entry_date))
  })

  check("SV-13", "founding date never precedes registration by an implausible margin", {
    d <- as.numeric(difftime(firms$registration_date, firms$founding_date,
                             units = "days"))
    all(d > -3650, na.rm = TRUE)
  })

  check_error("SV-14", "missing entry column aborts",
              brreg_survival_data(firms, entry_var = "nope"), pattern = "not found")

  check("SV-15", "bankrupt firms are events", {
    b <- sv[sv$bankrupt %in% TRUE, ]
    if (nrow(b) == 0) NA else all(b$event == 1L)
  })

  check("SV-16", "the input register is not survivor-only for survival analysis", {
    if (length(fx$deleted) == 0) NA else any(fx$deleted %in% firms$org_nr)
  }, defect = "D-20")

  check("SV-17", "duration_years default entry basis is documented as registration", {
    a <- brreg_survival_data(firms)
    b <- brreg_survival_data(firms, entry_var = "registration_date")
    identical(a$duration_years, b$duration_years)
  }, defect = "D-20")

  stress_flush()
}

test_governance()
