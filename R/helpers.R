stress_env <- new.env(parent = emptyenv())

stress_root <- function(default = Sys.getenv("TIDYBRREG_STRESS_ROOT", unset = getwd())) {
  normalizePath(default, mustWork = FALSE)
}

stress_results_dir <- function(root = stress_root()) {
  file.path(root, "results")
}

stress_init <- function(file = Sys.getenv("TIDYBRREG_STRESS_FILE", unset = "adhoc"),
                        results_dir = stress_results_dir(),
                        seed = 20260805L) {
  assign("file", file, envir = stress_env)
  assign("rows", list(), envir = stress_env)
  assign("results_dir", results_dir, envir = stress_env)
  assign("t0", Sys.time(), envir = stress_env)
  dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
  set.seed(seed)
  options(warn = 1, expressions = 5000L, timeout = 3600L)
  invisible(file)
}

stress_fmt <- function(x, max_chars = 240L) {
  out <- tryCatch(paste(utils::capture.output(utils::str(x, max.level = 1L)), collapse = " | "),
                  error = function(e) "<unprintable>")
  substr(out, 1L, max_chars)
}

stress_record <- function(id, desc, status, message = NA_character_,
                          defect = NA_character_, warnings = character(),
                          elapsed = NA_real_, group = NA_character_) {
  row <- tibble::tibble(
    file = get("file", envir = stress_env),
    id = id,
    group = group,
    description = desc,
    defect = defect,
    status = status,
    message = if (is.na(message[1])) NA_character_ else substr(paste(message, collapse = " / "), 1L, 400L),
    n_warnings = length(warnings),
    warnings = if (length(warnings) == 0) NA_character_ else substr(paste(warnings, collapse = " / "), 1L, 400L),
    elapsed = elapsed
  )
  assign("rows", c(get("rows", envir = stress_env), list(row)), envir = stress_env)
  cat(sprintf("[%-5s] %-8s %s%s\n", status, id, desc,
              if (!is.na(defect)) paste0(" <", defect, ">") else ""))
  invisible(row)
}

check <- function(id, desc, expr, defect = NA_character_, group = NA_character_) {
  t0 <- Sys.time()
  warns <- character()
  status <- "PASS"
  msg <- NA_character_
  val <- withCallingHandlers(
    tryCatch(expr,
             error = function(e) {
               status <<- "ERROR"
               msg <<- conditionMessage(e)
               NULL
             }),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  if (!identical(status, "ERROR")) {
    if (isTRUE(val)) {
      status <- "PASS"
    } else if (is.logical(val) && length(val) == 1L && is.na(val)) {
      status <- "SKIP"
      msg <- "precondition unavailable"
    } else {
      status <- "FAIL"
      msg <- stress_fmt(val)
    }
  }
  stress_record(id, desc, status, msg, defect, warns,
                as.numeric(difftime(Sys.time(), t0, units = "secs")), group)
}

check_error <- function(id, desc, expr, pattern = NULL, defect = NA_character_,
                        group = NA_character_) {
  t0 <- Sys.time()
  warns <- character()
  caught <- NULL
  res <- withCallingHandlers(
    tryCatch({
      force(expr)
      NULL
    }, error = function(e) {
      caught <<- conditionMessage(e)
      TRUE
    }),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  status <- if (is.null(caught)) "FAIL" else if (is.null(pattern) || grepl(pattern, caught)) "PASS" else "FAIL"
  msg <- if (is.null(caught)) "no error raised" else caught
  stress_record(id, desc, status, msg, defect, warns,
                as.numeric(difftime(Sys.time(), t0, units = "secs")), group)
}

check_warning <- function(id, desc, expr, pattern = NULL, defect = NA_character_,
                          group = NA_character_) {
  t0 <- Sys.time()
  warns <- character()
  withCallingHandlers(
    tryCatch(force(expr), error = function(e) NULL),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  hit <- if (length(warns) == 0) FALSE else if (is.null(pattern)) TRUE else any(grepl(pattern, warns))
  stress_record(id, desc, if (hit) "PASS" else "FAIL",
                if (length(warns) == 0) "no warning raised" else NA_character_,
                defect, warns,
                as.numeric(difftime(Sys.time(), t0, units = "secs")), group)
}

check_silent <- function(id, desc, expr, defect = NA_character_, group = NA_character_) {
  t0 <- Sys.time()
  warns <- character()
  withCallingHandlers(
    tryCatch(force(expr), error = function(e) NULL),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  stress_record(id, desc, if (length(warns) == 0) "PASS" else "FAIL",
                NA_character_, defect, warns,
                as.numeric(difftime(Sys.time(), t0, units = "secs")), group)
}

check_subprocess <- function(id, desc, code, expect = c("ok", "error"),
                             timeout = 120L, defect = NA_character_,
                             group = NA_character_, env_extra = character()) {
  expect <- match.arg(expect)
  t0 <- Sys.time()
  script <- tempfile(fileext = ".R")
  on.exit(unlink(script), add = TRUE)
  writeLines(code, script)
  out <- suppressWarnings(system2("Rscript",
                                  c("--vanilla", shQuote(script)),
                                  stdout = TRUE, stderr = TRUE,
                                  timeout = timeout,
                                  env = env_extra))
  st <- attr(out, "status")
  st <- if (is.null(st)) 0L else st
  ok <- identical(st, 0L)
  status <- if ((expect == "ok" && ok) || (expect == "error" && !ok)) "PASS" else "FAIL"
  stress_record(id, desc, status,
                paste0("exit=", st, " :: ", paste(utils::tail(out, 6L), collapse = " | ")),
                defect, character(),
                as.numeric(difftime(Sys.time(), t0, units = "secs")), group)
}

check_budget <- function(id, desc, code, seconds = 180L, defect = NA_character_,
                         group = NA_character_) {
  check_subprocess(id, desc, code, expect = "ok", timeout = seconds,
                   defect = defect, group = group)
}

stress_skip <- function(id, desc, reason, defect = NA_character_, group = NA_character_) {
  stress_record(id, desc, "SKIP", reason, defect, character(), 0, group)
}

has_cols <- function(x, cols) {
  is.data.frame(x) && all(cols %in% names(x))
}

is_typed_empty <- function(x, cols) {
  is.data.frame(x) && nrow(x) == 0L && all(cols %in% names(x))
}

col_class <- function(x, col) {
  if (!is.data.frame(x) || !col %in% names(x)) return(NA_character_)
  class(x[[col]])[1]
}

stable_schema <- function(a, b) {
  identical(sort(names(a)), sort(names(b)))
}

stress_flush <- function(results_dir = get("results_dir", envir = stress_env),
                         file = get("file", envir = stress_env)) {
  rows <- get("rows", envir = stress_env)
  if (length(rows) == 0) rows <- list(tibble::tibble())
  res <- dplyr::bind_rows(rows)
  saveRDS(res, file.path(results_dir, paste0(file, ".rds")))
  utils::write.csv(res, file.path(results_dir, paste0(file, ".csv")), row.names = FALSE)
  cat(sprintf("\n== %s: %d checks, %s ==\n", file, nrow(res),
              paste(names(table(res$status)), table(res$status),
                    sep = "=", collapse = " ")))
  invisible(res)
}

load_fixtures <- function(path = file.path(stress_results_dir(), "fixtures.rds")) {
  if (!file.exists(path)) stop("fixtures not built; run tests/00-fixtures.R first")
  readRDS(path)
}

stress_stagger <- function(max_seconds = 3) {
  Sys.sleep(stats::runif(1, 0, max_seconds))
  invisible(NULL)
}
