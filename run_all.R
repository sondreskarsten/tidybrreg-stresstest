suppressPackageStartupMessages({
  library(parallel)
  library(dplyr)
  library(tibble)
})

stress_manifest <- function() {
  tibble::tribble(
    ~file,                         ~tier, ~store,     ~timeout,
    "00-fixtures.R",                   0L, "own",       900L,
    "10-validate.R",                   1L, "own",       900L,
    "11-parse-internals.R",            1L, "own",       900L,
    "12-entity.R",                     1L, "own",      1800L,
    "13-search.R",                     1L, "own",      1800L,
    "14-roles.R",                      1L, "own",      1800L,
    "15-konsern-signatur.R",           1L, "own",      1800L,
    "16-governance.R",                 1L, "own",      1800L,
    "17-updates.R",                    1L, "own",      1800L,
    "18-label-harmonize.R",            1L, "own",      1800L,
    "19-roller-diff.R",                1L, "own",      1800L,
    "20-request-manifest.R",           1L, "own",       900L,
    "21-network.R",                    1L, "own",      2400L,
    "30-bulk-prewarm.R",               2L, "shared",  10800L,
    "31-download.R",                   3L, "shared",   7200L,
    "32-snapshot.R",                   3L, "own",      7200L,
    "33-panel-series-events.R",        3L, "shared",   3600L,
    "34-sync.R",                       3L, "own",     10800L,
    "35-replay.R",                     3L, "shared",   3600L,
    "36-file-outputs.R",               4L, "own",      1800L,
    "37-changelog.R",                  3L, "own",     10800L,
    "38-uncovered.R",                  3L, "own",      5400L
  )
}

run_one <- function(row, root = getwd(), shared_cache = file.path(root, "tmp", "cache"),
                    shared_store = file.path(root, "tmp", "shared-store"),
                    log_dir = file.path(root, "results", "logs")) {
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  name <- sub("\\.R$", "", row$file)
  own_data <- file.path(root, "tmp", "data", name)
  dir.create(own_data, recursive = TRUE, showWarnings = FALSE)
  dir.create(shared_cache, recursive = TRUE, showWarnings = FALSE)

  data_dir <- if (identical(row$store, "shared")) shared_store else own_data

  env <- c(
    paste0("TIDYBRREG_STRESS_ROOT=", root),
    paste0("TIDYBRREG_STRESS_FILE=", name),
    paste0("R_USER_CACHE_DIR=", shared_cache),
    paste0("R_USER_DATA_DIR=", data_dir),
    paste0("STRESS_SHARED_STORE=", shared_store),
    paste0("STRESS_ROLLER=", Sys.getenv("STRESS_ROLLER", "1")),
    paste0("STRESS_JSON=", Sys.getenv("STRESS_JSON", "1")),
    paste0("STRESS_SAMPLE_ROWS=", Sys.getenv("STRESS_SAMPLE_ROWS", "50000")),
    paste0("STRESS_CSV_BUDGET=", Sys.getenv("STRESS_CSV_BUDGET", "900")),
    paste0("STRESS_REPLAY_ROWS=", Sys.getenv("STRESS_REPLAY_ROWS", "200000"))
  )

  log <- file.path(log_dir, paste0(name, ".log"))
  t0 <- Sys.time()
  status <- suppressWarnings(system2(
    "Rscript",
    c("--vanilla", shQuote(file.path(root, "tests", row$file))),
    stdout = log, stderr = log, env = env, timeout = row$timeout
  ))
  tibble::tibble(
    file = name, tier = row$tier, exit = as.integer(status),
    elapsed = as.numeric(difftime(Sys.time(), t0, units = "secs")), log = log
  )
}

run_tier <- function(rows, cores, root = getwd()) {
  if (nrow(rows) == 0) return(tibble::tibble())
  jobs <- split(rows, seq_len(nrow(rows)))
  out <- parallel::mclapply(jobs, run_one, root = root,
                            mc.cores = max(1L, min(cores, length(jobs))),
                            mc.preschedule = FALSE)
  dplyr::bind_rows(out)
}

run_all <- function(root = normalizePath(getwd()),
                    cores = as.integer(Sys.getenv("STRESS_CORES",
                                                  max(1L, parallel::detectCores() - 1L))),
                    only = NULL,
                    manifest = stress_manifest()) {
  dir.create(file.path(root, "results"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "tmp"), recursive = TRUE, showWarnings = FALSE)

  if (!is.null(only)) manifest <- manifest[manifest$file %in% only, ]

  runs <- list()
  for (t in sort(unique(manifest$tier))) {
    rows <- manifest[manifest$tier == t, ]
    n <- if (t %in% c(0L, 2L)) 1L else cores
    message(sprintf("== tier %d: %d file(s) on %d core(s) ==", t, nrow(rows), n))
    runs[[length(runs) + 1L]] <- run_tier(rows, n, root = root)
  }
  runs <- dplyr::bind_rows(runs)
  saveRDS(runs, file.path(root, "results", "runs.rds"))
  summarise_results(root)
}

summarise_results <- function(root = normalizePath(getwd())) {
  files <- list.files(file.path(root, "results"), pattern = "\\.rds$", full.names = TRUE)
  files <- files[!basename(files) %in% c("fixtures.rds", "prewarm.rds",
                                         "environment.rds", "runs.rds",
                                         "summary.rds")]
  complete <- files[!grepl("\\.partial\\.rds$", files)]
  partial <- files[grepl("\\.partial\\.rds$", files)]
  done <- sub("\\.rds$", "", basename(complete))
  partial <- partial[!sub("\\.partial\\.rds$", "", basename(partial)) %in% done]
  files <- c(complete, partial)
  if (length(partial) > 0) {
    message("incomplete (process died mid-file): ",
            paste(sub("\\.partial\\.rds$", "", basename(partial)), collapse = ", "))
  }
  if (length(files) == 0) {
    message("no results found")
    return(invisible(NULL))
  }
  res <- dplyr::bind_rows(lapply(files, readRDS))

  res$outcome <- dplyr::case_when(
    res$status == "PASS" & is.na(res$defect) ~ "pass",
    res$status == "PASS" & !is.na(res$defect) ~ "pass_unexpected",
    res$status == "SKIP" ~ "skip",
    res$status %in% c("FAIL", "ERROR") & !is.na(res$defect) ~ "defect_confirmed",
    TRUE ~ "regression"
  )

  overall <- dplyr::count(res, .data$outcome, sort = TRUE)
  by_file <- dplyr::count(res, .data$file, .data$outcome) |>
    tidyr::pivot_wider(names_from = "outcome", values_from = "n", values_fill = 0L)
  by_defect <- res |>
    dplyr::filter(!is.na(.data$defect)) |>
    dplyr::count(.data$defect, .data$outcome) |>
    dplyr::arrange(.data$defect)

  saveRDS(list(results = res, overall = overall, by_file = by_file,
               by_defect = by_defect),
          file.path(root, "results", "summary.rds"))
  utils::write.csv(res, file.path(root, "results", "all-checks.csv"), row.names = FALSE)

  cat("\n===== OVERALL =====\n"); print(as.data.frame(overall))
  cat("\n===== BY FILE =====\n"); print(as.data.frame(by_file))
  cat("\n===== DEFECT PROBES =====\n"); print(as.data.frame(by_defect))
  cat("\n===== REGRESSIONS (unexpected failures) =====\n")
  print(as.data.frame(res[res$outcome == "regression",
                          c("file", "id", "description", "status", "message")]))
  cat("\n===== DEFECTS THAT DID NOT REPRODUCE =====\n")
  print(as.data.frame(res[res$outcome == "pass_unexpected",
                          c("file", "id", "defect", "description")]))
  invisible(res)
}

stress_invoked_as_script <- function() {
  sys.nframe() <= 1L && !interactive() &&
    any(grepl("run_all\\.R$", commandArgs(trailingOnly = FALSE)))
}

if (stress_invoked_as_script()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 0 && args[1] == "summarise") {
    summarise_results()
  } else if (length(args) > 0) {
    run_all(only = args)
  } else {
    run_all()
  }
}
