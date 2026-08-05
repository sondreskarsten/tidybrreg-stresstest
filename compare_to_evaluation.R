suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

parse_evaluation <- function(path = "EVALUATION.md") {
  ln <- readLines(path, warn = FALSE)

  fn_of <- function(x) {
    m <- regmatches(x, regexpr("(brreg_[a-z_]+|diff_roller_state|get_brreg_dic|as_brreg_tsibble)", x))
    if (length(m) == 0) NA_character_ else m
  }

  call_rows <- grep("^\\| [0-9]+ \\|", ln, value = TRUE)
  calls <- lapply(call_rows, function(r) {
    p <- trimws(strsplit(r, "\\|")[[1]])
    p <- p[p != ""]
    tibble(
      call_no = suppressWarnings(as.integer(p[1])),
      call = p[2] %||% NA_character_,
      expected = p[3] %||% NA_character_,
      persists = p[4] %||% NA_character_,
      verdict = p[5] %||% NA_character_,
      fn = fn_of(p[2] %||% "")
    )
  }) %>% bind_rows()

  calls$defects <- vapply(call_rows, function(r) {
    d <- regmatches(r, gregexpr("D-[0-9]+", r))[[1]]
    if (length(d) == 0) NA_character_ else paste(unique(d), collapse = ",")
  }, character(1))

  def_rows <- grep("^\\| D-[0-9]+ \\|", ln, value = TRUE)
  defects <- lapply(def_rows, function(r) {
    p <- trimws(strsplit(r, "\\|")[[1]])
    p <- p[p != ""]
    tibble(defect = p[1], severity = p[2] %||% NA_character_,
           description = p[3] %||% NA_character_,
           evidence = p[4] %||% NA_character_)
  }) %>% bind_rows()

  list(calls = calls, defects = defects)
}

load_results <- function(dir = "results") {
  fs <- list.files(dir, pattern = "\\.rds$", full.names = TRUE)
  fs <- fs[!basename(fs) %in% c("fixtures.rds", "prewarm.rds", "environment.rds",
                                "runs.rds", "summary.rds")]
  comp <- fs[!grepl("partial", fs)]
  part <- fs[grepl("partial", fs)]
  part <- part[!sub("\\.partial\\.rds$", "", basename(part)) %in%
                 sub("\\.rds$", "", basename(comp))]
  if (length(c(comp, part)) == 0) return(tibble())
  res <- bind_rows(lapply(c(comp, part), readRDS))
  res$outcome <- case_when(
    res$status == "PASS" & is.na(res$defect) ~ "pass",
    res$status == "PASS" & !is.na(res$defect) ~ "pass_unexpected",
    res$status == "SKIP" ~ "skip",
    res$status %in% c("FAIL", "ERROR") & !is.na(res$defect) ~ "defect_confirmed",
    TRUE ~ "regression"
  )
  res
}

file_function_map <- function() {
  tribble(
    ~file,                     ~fn,
    "12-entity",               "brreg_entity",
    "13-search",               "brreg_search",
    "13-search",               "brreg_underenheter",
    "13-search",               "brreg_children",
    "14-roles",                "brreg_roles",
    "14-roles",                "brreg_roles_legal",
    "14-roles",                "brreg_board_summary",
    "15-konsern-signatur",     "brreg_konsern",
    "15-konsern-signatur",     "brreg_signatur",
    "15-konsern-signatur",     "brreg_prokura",
    "16-governance",           "brreg_board_network",
    "16-governance",           "brreg_survival_data",
    "17-updates",              "brreg_updates",
    "17-updates",              "brreg_update_fields",
    "18-label-harmonize",      "brreg_label",
    "18-label-harmonize",      "get_brreg_dic",
    "18-label-harmonize",      "brreg_harmonize_kommune",
    "18-label-harmonize",      "brreg_harmonize_nace",
    "19-roller-diff",          "diff_roller_state",
    "20-request-manifest",     "brreg_manifest",
    "20-request-manifest",     "brreg_data_dir",
    "20-request-manifest",     "brreg_snapshots",
    "20-request-manifest",     "brreg_status",
    "20-request-manifest",     "brreg_sync_status",
    "21-network",              "brreg_network",
    "31-download",             "brreg_download",
    "32-snapshot",             "brreg_snapshot",
    "32-snapshot",             "brreg_import",
    "32-snapshot",             "brreg_open",
    "32-snapshot",             "brreg_cleanup",
    "33-panel-series-events",  "brreg_panel",
    "33-panel-series-events",  "brreg_series",
    "33-panel-series-events",  "brreg_events",
    "33-panel-series-events",  "as_brreg_tsibble",
    "34-sync",                 "brreg_sync",
    "34-sync",                 "brreg_changes",
    "34-sync",                 "brreg_change_summary",
    "34-sync",                 "brreg_flows",
    "34-sync",                 "brreg_annotations",
    "34-sync",                 "brreg_annotation_summary",
    "34-sync",                 "brreg_historical_names",
    "35-replay",               "brreg_replay",
    "10-validate",             "brreg_validate",
    "36-file-outputs",         "brreg_snapshot"
  )
}

compare <- function(eval_path = "EVALUATION.md", results_dir = "results",
                    out_dir = "results") {
  ev <- parse_evaluation(eval_path)
  res <- load_results(results_dir)
  if (nrow(res) == 0) {
    message("no results to compare")
    return(invisible(NULL))
  }
  map <- file_function_map()

  res_fn <- res %>%
    left_join(map, by = "file", relationship = "many-to-many")

  per_fn <- ev$calls %>%
    filter(!is.na(fn)) %>%
    count(fn, name = "enumerated_calls") %>%
    left_join(
      res_fn %>% filter(!is.na(fn)) %>%
        count(fn, outcome) %>%
        tidyr::pivot_wider(names_from = outcome, values_from = n, values_fill = 0L),
      by = "fn"
    ) %>%
    mutate(across(where(is.numeric), ~tidyr::replace_na(.x, 0L))) %>%
    mutate(checks = rowSums(across(any_of(c("pass", "defect_confirmed",
                                            "pass_unexpected", "regression", "skip"))))) %>%
    arrange(desc(.data$enumerated_calls))

  predicted <- ev$defects$defect
  observed <- res %>% filter(!is.na(defect)) %>% distinct(defect, outcome)

  confirmed <- observed %>% filter(outcome == "defect_confirmed") %>% pull(defect)
  not_repro <- setdiff(observed %>% filter(outcome == "pass_unexpected") %>% pull(defect),
                       confirmed)
  untested <- setdiff(predicted, observed$defect)
  new_found <- setdiff(confirmed, predicted)

  defect_status <- tibble(
    defect = union(predicted, observed$defect)
  ) %>%
    mutate(
      predicted_in_eval = .data$defect %in% predicted,
      status = case_when(
        .data$defect %in% confirmed & .data$defect %in% predicted ~ "confirmed",
        .data$defect %in% confirmed ~ "confirmed_new",
        .data$defect %in% not_repro ~ "did_not_reproduce",
        TRUE ~ "not_covered"
      )
    ) %>%
    left_join(ev$defects[, c("defect", "severity", "description")], by = "defect") %>%
    arrange(.data$status, .data$defect)

  readr_write <- function(x, f) utils::write.csv(x, file.path(out_dir, f), row.names = FALSE)
  readr_write(per_fn, "coverage_by_function.csv")
  readr_write(defect_status, "defect_crosswalk.csv")
  readr_write(ev$calls, "evaluation_calls.csv")

  txt <- c(
    "COMPARISON AGAINST EVALUATION.md",
    sprintf("  enumerated calls in evaluation : %d", nrow(ev$calls)),
    sprintf("  functions enumerated           : %d", dplyr::n_distinct(stats::na.omit(ev$calls$fn))),
    sprintf("  defects predicted in evaluation: %d", length(predicted)),
    sprintf("  checks executed                : %d", nrow(res)),
    "",
    sprintf("  predicted defects confirmed    : %d", length(intersect(confirmed, predicted))),
    sprintf("  predicted did NOT reproduce    : %d  (%s)", length(not_repro),
            paste(sort(not_repro), collapse = ", ")),
    sprintf("  predicted never exercised      : %d  (%s)", length(untested),
            paste(sort(untested), collapse = ", ")),
    sprintf("  NEW defects found by the suite : %d  (%s)", length(new_found),
            paste(sort(new_found), collapse = ", ")),
    "",
    "FUNCTIONS ENUMERATED BUT NEVER EXERCISED:",
    paste0("  ", paste(setdiff(stats::na.omit(unique(ev$calls$fn)),
                               stats::na.omit(unique(res_fn$fn))), collapse = ", "))
  )
  writeLines(txt, file.path(out_dir, "evaluation_comparison.txt"))
  cat(paste(txt, collapse = "\n"), "\n\n")
  cat("=== coverage by function (top 20) ===\n")
  print(as.data.frame(head(per_fn, 20)))
  cat("\n=== defect crosswalk summary ===\n")
  print(as.data.frame(count(defect_status, status)))
  invisible(list(per_fn = per_fn, defect_status = defect_status))
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

if (sys.nframe() <= 1L && !interactive() &&
    any(grepl("compare_to_evaluation\\.R$", commandArgs(trailingOnly = FALSE)))) {
  compare()
}
