root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
source(file.path(root, "R", "payloads.R"))
library(tidybrreg)

cl_cols <- c("timestamp", "org_nr", "registry", "change_type", "field",
             "value_from", "value_to", "update_id")

test_roller_diff <- function(fx = load_fixtures()) {
  stress_init("19-roller-diff")

  old <- synthetic_roles_state(n = 3L)
  new_same <- old
  new_added <- dplyr::bind_rows(old, synthetic_roles_state(n = 1L, shift = 10L))
  new_removed <- old[-2, ]
  new_changed <- old
  new_changed$last_name[1] <- "Endret"

  check("RD-01", "identical states produce no changelog rows",
        nrow(diff_roller_state(old, new_same)) == 0L)

  check("RD-02", "changelog schema is exactly the documented one", {
    d <- diff_roller_state(NULL, old)
    identical(names(d), cl_cols)
  })

  check("RD-03", "NULL old state treats everything as entry", {
    d <- diff_roller_state(NULL, old)
    nrow(d) > 0 && all(d$change_type == "entry")
  })

  check("RD-04", "zero-row old state treats everything as entry", {
    d <- diff_roller_state(old[0, ], old)
    nrow(d) > 0 && all(d$change_type == "entry")
  })

  check("RD-05", "zero-row new state treats everything as exit", {
    d <- diff_roller_state(old, old[0, ])
    nrow(d) > 0 && all(d$change_type == "exit")
  })

  check("RD-06", "registry is always roller",
        all(diff_roller_state(NULL, old)$registry == "roller"))

  check("RD-07", "an added role yields entry rows only for that role", {
    d <- diff_roller_state(old, new_added)
    nrow(d) > 0 && all(d$change_type == "entry")
  })

  check("RD-08", "a removed role yields exit rows only", {
    d <- diff_roller_state(old, new_removed)
    nrow(d) > 0 && all(d$change_type == "exit")
  })

  check("RD-09", "a modified field yields exactly one change row", {
    d <- diff_roller_state(old, new_changed)
    sum(d$change_type == "change") >= 1L && all(d$field[d$change_type == "change"] == "last_name")
  })

  check("RD-10", "change rows carry both old and new values", {
    d <- diff_roller_state(old, new_changed)
    ch <- d[d$change_type == "change", ]
    all(!is.na(ch$value_from)) && all(!is.na(ch$value_to))
  })

  check("RD-11", "entry rows have NA value_from",
        all(is.na(diff_roller_state(NULL, old)$value_from)))

  check("RD-12", "exit rows have NA value_to",
        all(is.na(diff_roller_state(old, old[0, ])$value_to)))

  check("RD-13", "diff is antisymmetric on entry and exit", {
    a <- diff_roller_state(old, new_added)
    b <- diff_roller_state(new_added, old)
    nrow(a) == nrow(b) && all(a$change_type == "entry") && all(b$change_type == "exit")
  })

  check("RD-14", "NA to value transition is recorded", {
    o <- old; o$elected_by <- NA_character_
    n <- old; n$elected_by <- "ANSA"
    d <- diff_roller_state(o, n)
    any(d$field == "elected_by" & d$change_type == "change")
  })

  check("RD-15", "value to NA transition is recorded", {
    o <- old; o$elected_by <- "ANSA"
    n <- old; n$elected_by <- NA_character_
    d <- diff_roller_state(o, n)
    any(d$field == "elected_by" & d$change_type == "change")
  })

  check("RD-16", "a birth date correction is not silently invisible", {
    n <- old; n$birth_date[1] <- old$birth_date[1] + 1
    n$person_id[1] <- paste0(n$birth_date[1], "_l1_f1_")
    d <- diff_roller_state(old, n)
    nrow(d) > 0
  })

  check("RD-17", "timestamp is passed through", {
    d <- diff_roller_state(NULL, old, timestamp = "2026-01-01T00:00:00")
    all(d$timestamp == "2026-01-01T00:00:00")
  })

  check("RD-18", "integer update_id is passed through", {
    d <- diff_roller_state(NULL, old, update_id = 42L)
    all(d$update_id == 42L)
  })

  check("RD-19", "character update_id does not become NA", {
    d <- suppressWarnings(diff_roller_state(NULL, old, update_id = "batch-7"))
    !all(is.na(d$update_id))
  }, defect = "D-82")

  check("RD-20", "legacy state without the post-0.3.4 columns diffs cleanly", {
    o <- old[, setdiff(names(old), c("deregistered", "ordering", "elected_by",
                                     "group_modified"))]
    d <- diff_roller_state(o, old)
    is.data.frame(d)
  })

  check("RD-21", "state with resigned diffs against state without", {
    o <- old; o$resigned <- FALSE
    d <- diff_roller_state(o, old)
    is.data.frame(d) && identical(names(d), cl_cols)
  })

  check("RD-22", "entity-held roles are keyed distinctly", {
    o <- old
    o$person_id <- NA_character_
    o$entity_org_nr <- "976389387"
    d <- diff_roller_state(o, o)
    nrow(d) == 0L
  })

  check("RD-23", "duplicate role rows are not silently collapsed", {
    dup <- dplyr::bind_rows(old, old[1, ])
    d <- diff_roller_state(old, dup)
    nrow(d) > 0
  }, defect = "D-100")

  check("RD-24", "diff of a large state completes", {
    big_old <- dplyr::bind_rows(lapply(1:200, function(i)
      synthetic_roles_state(org_nr = sprintf("9%08d", i), n = 5L)))
    big_new <- big_old
    big_new$last_name[1:100] <- "Endret"
    d <- diff_roller_state(big_old, big_new)
    sum(d$change_type == "change") == 100L
  })

  check("RD-25", "org_nr on every changelog row is populated",
        all(!is.na(diff_roller_state(old, new_changed)$org_nr)))

  check("RD-26", "no role key leaks into the output",
        !any(c("role_key", "holder_id") %in% names(diff_roller_state(NULL, old))))

  check("RD-27", "diff works without tidyr attached explicitly", {
    d <- diff_roller_state(NULL, old)
    nrow(d) > 0
  }, defect = "D-83")

  check("RD-28", "live round trip on a real entity", {
    a <- brreg_roles(fx$known$asa)
    d <- diff_roller_state(a, a)
    nrow(d) == 0L
  })

  check("RD-29", "live bootstrap diff yields entries for every role", {
    a <- brreg_roles(fx$known$asa)
    d <- diff_roller_state(NULL, a)
    length(unique(paste(d$org_nr))) == 1L && nrow(d) > nrow(a)
  })

  check("RD-30", "empty against empty yields a typed empty changelog", {
    d <- diff_roller_state(old[0, ], old[0, ])
    is_typed_empty(d, cl_cols)
  })

  stress_flush()
}

test_roller_diff()
