install_tidybrreg <- function(repos = c(sondreskarsten = "https://sondreskarsten.r-universe.dev",
                                        CRAN = "https://cloud.r-project.org"),
                              lib = .libPaths()[1],
                              out = "results/environment.rds") {
  install.packages("tidybrreg", repos = repos, lib = lib)

  required <- c("cli", "dplyr", "httr2", "jsonlite", "readr", "rlang", "tibble")
  suggested <- c("arrow", "nanoparquet", "curl", "duckdb", "klassR", "tidygraph",
                 "tidyr", "tsibble", "yyjsonr", "httptest2", "testthat", "withr")

  present <- function(p) requireNamespace(p, quietly = TRUE)
  ver <- function(p) if (present(p)) as.character(utils::packageVersion(p)) else NA_character_

  env <- list(
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    platform = R.version$platform,
    tidybrreg_version = ver("tidybrreg"),
    tidybrreg_desc = if (present("tidybrreg")) as.list(utils::packageDescription("tidybrreg")) else NULL,
    required = vapply(required, ver, character(1)),
    suggested = vapply(suggested, ver, character(1)),
    exports = if (present("tidybrreg")) sort(getNamespaceExports("tidybrreg")) else character(),
    captured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )

  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  saveRDS(env, out)

  missing_req <- required[is.na(env$required)]
  if (length(missing_req) > 0) stop("missing hard dependencies: ", paste(missing_req, collapse = ", "))

  message("tidybrreg ", env$tidybrreg_version, " with ", length(env$exports), " exports")
  message("suggested missing: ",
          paste(suggested[is.na(env$suggested)], collapse = ", "))
  invisible(env)
}

install_tidybrreg()
