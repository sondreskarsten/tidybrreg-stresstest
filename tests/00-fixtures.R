source(file.path(Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd()), "R", "helpers.R"))
library(tidybrreg)

build_fixtures <- function(out = file.path(stress_results_dir(), "fixtures.rds"),
                           known = list(asa = "923609016", bank = "984851006",
                                        orgl = "971524960"),
                           search_size = 25L) {
  stress_init("00-fixtures")

  fx <- new.env(parent = emptyenv())
  fx$known <- known
  fx$built_at <- Sys.time()

  check("FX-01", "seed ASA resolves", {
    e <- brreg_entity(known$asa)
    fx$asa_entity <- e
    is.data.frame(e) && nrow(e) == 1L && identical(e$org_nr, known$asa)
  })

  check("FX-02", "seed bank resolves", {
    e <- brreg_entity(known$bank)
    nrow(e) == 1L
  })

  check("FX-03", "discover ENK sample", {
    s <- brreg_search(legal_form = "ENK", max_results = search_size)
    fx$enk <- if (nrow(s) > 0) s$org_nr else character()
    length(fx$enk) > 0
  })

  check("FX-04", "discover NUF sample", {
    s <- brreg_search(legal_form = "NUF", max_results = search_size)
    fx$nuf <- if (nrow(s) > 0) s$org_nr else character()
    length(fx$nuf) > 0
  })

  check("FX-05", "discover bankrupt sample", {
    s <- brreg_search(bankrupt = TRUE, max_results = search_size)
    fx$bankrupt <- if (nrow(s) > 0) s$org_nr else character()
    length(fx$bankrupt) > 0
  })

  check("FX-06", "discover large Oslo AS sample", {
    s <- brreg_search(legal_form = "AS", municipality_code = "0301",
                      min_employees = 200, max_results = search_size)
    fx$oslo_as <- if (nrow(s) > 0) s$org_nr else character()
    length(fx$oslo_as) > 0
  })

  check("FX-07", "discover underenheter of seed", {
    s <- brreg_underenheter(known$asa, max_results = search_size)
    fx$underenheter <- if (nrow(s) > 0) s$org_nr else character()
    length(fx$underenheter) > 0
  })

  check("FX-08", "discover recently deleted org via CDC", {
    u <- brreg_updates(since = Sys.Date() - 14, size = 10000, max_pages = 5)
    del <- u$org_nr[u$change_type %in% c("Sletting", "Fjernet")]
    fx$deleted <- utils::head(unique(del[!is.na(del)]), 20L)
    fx$cdc_sample <- u
    length(fx$deleted) > 0
  })

  check("FX-09", "discover recently created org via CDC", {
    u <- fx$cdc_sample
    ny <- u$org_nr[u$change_type == "Ny"]
    fx$new_orgs <- utils::head(unique(ny[!is.na(ny)]), 20L)
    length(fx$new_orgs) > 0
  })

  check("FX-10", "discover org in a corporate group", {
    cand <- unique(c(known$asa, fx$oslo_as))
    hit <- character()
    for (o in utils::head(cand, 10L)) {
      k <- suppressWarnings(brreg_konsern(o))
      if (nrow(k) > 0) hit <- c(hit, o)
      if (length(hit) >= 3) break
    }
    fx$konsern <- hit
    length(hit) > 0
  })

  check("FX-11", "discover org with no corporate group", {
    cand <- fx$enk
    miss <- character()
    for (o in utils::head(cand, 5L)) {
      k <- suppressWarnings(brreg_konsern(o))
      if (nrow(k) == 0) miss <- c(miss, o)
      if (length(miss) >= 2) break
    }
    fx$no_konsern <- miss
    length(miss) > 0
  })

  check("FX-12", "discover org with registered prokura", {
    hit <- character()
    for (o in utils::head(c(known$asa, known$bank, fx$oslo_as), 10L)) {
      p <- suppressWarnings(brreg_prokura(o))
      if (nrow(p) > 0) hit <- c(hit, o)
      if (length(hit) >= 2) break
    }
    fx$prokura <- hit
    length(hit) > 0
  })

  check("FX-13", "discover org with entity-held role", {
    r <- brreg_roles(known$asa)
    fx$seed_roles <- r
    any(!is.na(r$entity_org_nr))
  })

  check("FX-14", "seed holds legal roles elsewhere", {
    lr <- brreg_roles_legal(known$asa)
    fx$seed_legal_roles <- lr
    is.data.frame(lr)
  })

  check("FX-15", "CDC field-level sample available", {
    f <- brreg_update_fields(since = Sys.Date() - 2, size = 500, max_pages = 2)
    fx$cdc_fields <- f
    nrow(f) > 0
  })

  saveRDS(as.list(fx), out)
  stress_flush()
  invisible(as.list(fx))
}

build_fixtures()
