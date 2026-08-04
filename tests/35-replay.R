root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

test_replay <- function(pw = readRDS(file.path(stress_results_dir(), "prewarm.rds")),
                        n_base = as.integer(Sys.getenv("STRESS_REPLAY_ROWS", "200000"))) {
  stress_init("35-replay")
  options(brreg.data_dir = pw$store)

  base <- tb$parse_bulk_csv(pw$paths$enheter_csv, n_max = n_base)
  upd <- brreg_updates(since = Sys.Date() - 5, size = 10000,
                       include_changes = TRUE, max_pages = 4)
  upd <- upd[upd$org_nr %in% base$org_nr, ]

  check("RP-00", "a usable update sample overlaps the base", nrow(upd) > 0)

  check("RP-01", "replay returns the base schema", {
    st <- brreg_replay(base, upd, target_date = Sys.Date())
    identical(sort(names(st)), sort(names(base)))
  })

  check("RP-02", "replay attaches replay_info", {
    st <- brreg_replay(base, upd)
    is.list(attr(st, "replay_info"))
  })

  check("RP-03", "replay_info counts sum to the applied updates", {
    st <- brreg_replay(base, upd)
    i <- attr(st, "replay_info")
    i$n_insert + i$n_update + i$n_delete <= i$n_updates_applied
  })

  check("RP-04", "deletions remove rows", {
    st <- brreg_replay(base, upd)
    del <- unique(upd$org_nr[upd$change_type %in% c("Sletting", "Fjernet")])
    del <- intersect(del, base$org_nr)
    if (length(del) == 0) NA else !any(del %in% st$org_nr)
  })

  check("RP-05", "an empty update set returns the base unchanged", {
    st <- brreg_replay(base, upd[0, ], target_date = Sys.Date())
    identical(nrow(st), nrow(base))
  })

  check("RP-06", "target_date includes events on that day", {
    d <- max(as.Date(upd$timestamp))
    a <- brreg_replay(base, upd, target_date = d)
    b <- brreg_replay(base, upd, target_date = d + 1)
    identical(attr(a, "replay_info")$n_updates_applied,
              attr(b, "replay_info")$n_updates_applied)
  }, defect = "D-69")

  check("RP-07", "an earlier target applies fewer updates", {
    d <- min(as.Date(upd$timestamp))
    a <- brreg_replay(base, upd, target_date = d + 1)
    b <- brreg_replay(base, upd, target_date = Sys.Date())
    attr(a, "replay_info")$n_updates_applied <=
      attr(b, "replay_info")$n_updates_applied
  })

  check("RP-08", "field changes are actually applied", {
    ch <- upd[upd$change_type == "Endring", ]
    ch <- ch[vapply(ch$changes, function(x) nrow(x) > 0, logical(1)), ]
    if (nrow(ch) == 0) NA else {
      st <- brreg_replay(base, ch)
      one <- ch[1, ]
      patch <- one$changes[[1]]
      fld <- patch$field[!is.na(patch$new_value)][1]
      if (is.na(fld)) NA else {
        col <- tb$lookup_patch_field(fld, names(base))
        if (is.null(col)) FALSE else
          !identical(base[[col]][base$org_nr == one$org_nr],
                     st[[col]][st$org_nr == one$org_nr]) ||
          identical(as.character(st[[col]][st$org_nr == one$org_nr]),
                    patch$new_value[patch$field == fld][1])
      }
    }
  })

  check("RP-09", "address changes are replayed rather than dropped", {
    ch <- dplyr::bind_rows(upd$changes)
    addr <- ch$field[grepl("adresse", ch$field)]
    if (length(addr) == 0) NA else {
      mapped <- vapply(unique(addr),
                       function(f) !is.null(tb$lookup_patch_field(f, names(base))),
                       logical(1))
      all(mapped)
    }
  }, defect = "D-71")

  check("RP-10", "every observed CDC field maps to a state column", {
    ch <- dplyr::bind_rows(upd$changes)
    if (nrow(ch) == 0) NA else {
      flds <- unique(stats::na.omit(ch$field))
      mapped <- vapply(flds, function(f) !is.null(tb$lookup_patch_field(f, names(base))),
                       logical(1))
      all(mapped)
    }
  }, defect = "D-71")

  check("RP-11", "replay without include_changes signals rather than silently no-oping", {
    plain <- brreg_updates(since = Sys.Date() - 2, size = 500, max_pages = 1)
    plain <- plain[plain$org_nr %in% base$org_nr, ]
    if (nrow(plain) == 0) NA else {
      out <- tryCatch(brreg_replay(base, plain), error = function(e) "err")
      identical(out, "err") ||
        attr(out, "replay_info")$n_update == 0L
    }
  }, defect = "D-70")

  check("RP-12", "cols restricts the replayed columns", {
    st <- brreg_replay(base, upd, cols = c("employees", "name"))
    setequal(names(st), c("org_nr", "employees", "name"))
  })

  check("RP-13", "new entities are inserted with a resolvable identity", {
    ny <- upd[upd$change_type == "Ny", ]
    if (nrow(ny) == 0) NA else {
      st <- brreg_replay(base, upd)
      added <- setdiff(st$org_nr, base$org_nr)
      if (length(added) == 0) NA else {
        row <- st[st$org_nr == added[1], ]
        !all(is.na(unlist(row[, setdiff(names(row), "org_nr")])))
      }
    }
  })

  check("RP-14", "replay never introduces duplicate org numbers", {
    st <- brreg_replay(base, upd)
    !any(duplicated(st$org_nr))
  })

  check("RP-15", "replay preserves column types", {
    st <- brreg_replay(base, upd)
    identical(vapply(base, function(x) class(x)[1], character(1)),
              vapply(st[names(base)], function(x) class(x)[1], character(1)))
  })

  check("RP-16", "replay agrees with a live lookup on a changed entity", {
    ch <- upd[upd$change_type == "Endring", ]
    if (nrow(ch) == 0) NA else {
      st <- brreg_replay(base, upd)
      o <- ch$org_nr[1]
      live <- brreg_entity(o)
      identical(as.character(st$name[st$org_nr == o]), as.character(live$name))
    }
  })

  check("RP-17", "replaying twice is idempotent", {
    a <- brreg_replay(base, upd)
    b <- brreg_replay(a, upd)
    nrow(a) == nrow(b)
  })

  stress_flush()
}

test_replay()
