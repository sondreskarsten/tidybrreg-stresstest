root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
source(file.path(root, "R", "payloads.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

test_updates <- function(fx = load_fixtures()) {
  stress_init("17-updates")
  stress_stagger()

  u <- brreg_updates(since = Sys.Date() - 3, size = 500, max_pages = 3)

  check("U-01", "updates returns rows", nrow(u) > 0)

  check("U-02", "documented columns are present",
        all(c("update_id", "org_nr", "change_type", "timestamp") %in% names(u)))

  check("U-03", "timestamp is POSIXct", inherits(u$timestamp, "POSIXct"))

  check("U-04", "timestamps carry a UTC timezone", {
    tzs <- attr(u$timestamp, "tzone")
    !is.null(tzs) && nzchar(tzs) && tzs %in% c("UTC", "GMT")
  }, defect = "D-33")

  check("U-05", "timestamps are not in the future", {
    max(u$timestamp, na.rm = TRUE) <= Sys.time() + 86400
  }, defect = "D-33")

  check("U-06", "update_id is strictly increasing",
        all(diff(u$update_id) > 0))

  check("U-07", "update_id has no duplicates", !any(duplicated(u$update_id)))

  check("U-08", "change_type values are the documented set",
        all(u$change_type %in% c("Ny", "Endring", "Sletting", "Fjernet")))

  check("U-09", "org numbers are valid", all(brreg_validate(u$org_nr)))

  check("U-10", "default call does not silently truncate", {
    d <- brreg_updates()
    n_full <- nrow(brreg_updates(since = Sys.Date() - 1, size = 10000, max_pages = 20))
    nrow(d) >= n_full || nrow(d) < 100L
  }, defect = "D-30")

  check("U-11", "max_pages beyond the data does not loop forever", {
    d <- brreg_updates(since = Sys.Date() - 1, size = 10000, max_pages = 40)
    is.data.frame(d)
  })

  check("U-12", "pagination is contiguous with a single-page read", {
    a <- brreg_updates(since = Sys.Date() - 2, size = 200, max_pages = 3)
    b <- brreg_updates(since = Sys.Date() - 2, size = 600, max_pages = 1)
    length(intersect(a$update_id, b$update_id)) > 0 &&
      identical(utils::head(sort(a$update_id), 100L), utils::head(sort(b$update_id), 100L))
  })

  check("U-13", "since respects the time of day", {
    a <- brreg_updates(since = as.POSIXct(paste(Sys.Date() - 1, "00:00:00"), tz = "UTC"),
                       size = 5000, max_pages = 2)
    b <- brreg_updates(since = as.POSIXct(paste(Sys.Date() - 1, "23:00:00"), tz = "UTC"),
                       size = 5000, max_pages = 2)
    nrow(b) < nrow(a)
  }, defect = "D-31")

  check("U-14", "include_changes adds a list column of tibbles", {
    d <- brreg_updates(since = Sys.Date() - 2, size = 200,
                       include_changes = TRUE, max_pages = 1)
    "changes" %in% names(d) && is.list(d$changes) &&
      all(vapply(d$changes, is.data.frame, logical(1)))
  })

  check("U-15", "change tibbles carry the documented columns", {
    d <- brreg_updates(since = Sys.Date() - 2, size = 200,
                       include_changes = TRUE, max_pages = 1)
    ch <- dplyr::bind_rows(d$changes)
    if (nrow(ch) == 0) NA else
      all(c("operation", "field", "new_value") %in% names(ch))
  })

  check("U-16", "patch operations are RFC 6902 verbs", {
    d <- brreg_updates(since = Sys.Date() - 2, size = 200,
                       include_changes = TRUE, max_pages = 1)
    ch <- dplyr::bind_rows(d$changes)
    if (nrow(ch) == 0) NA else
      all(ch$operation %in% c("add", "remove", "replace", "move", "copy", "test"))
  })

  check("U-17", "underenheter stream works",
        nrow(brreg_updates(since = Sys.Date() - 3, size = 200,
                           type = "underenheter", max_pages = 2)) > 0)

  check("U-18", "roller stream works",
        nrow(brreg_updates(since = Sys.Date() - 3, size = 200, type = "roller")) > 0)

  check("U-19", "roller stream honours max_pages", {
    a <- brreg_updates(since = Sys.Date() - 3, size = 100, type = "roller",
                       max_pages = 1)
    b <- brreg_updates(since = Sys.Date() - 3, size = 100, type = "roller",
                       max_pages = 5)
    nrow(b) > nrow(a)
  }, defect = "D-32")

  check("U-20", "roller stream schema matches the enheter stream",
        stable_schema(brreg_updates(since = Sys.Date() - 3, size = 50, type = "roller"),
                      u))

  check("U-21", "future since yields a typed empty tibble", {
    d <- brreg_updates(since = Sys.Date() + 30, size = 10)
    is_typed_empty(d, c("update_id", "org_nr", "change_type", "timestamp"))
  }, defect = "D-05")

  check("U-22", "size above the API ceiling is capped, not rejected",
        is.data.frame(brreg_updates(since = Sys.Date() - 1, size = 99999)))

  f <- brreg_update_fields(since = Sys.Date() - 2, size = 500, max_pages = 2)

  check("UF-01", "update_fields returns rows", nrow(f) > 0)

  check("UF-02", "documented columns are present",
        all(c("update_id", "org_nr", "change_type", "timestamp", "operation",
              "field", "new_value") %in% names(f)))

  check("UF-03", "no list columns", !any(vapply(f, is.list, logical(1))))

  check("UF-04", "patch-less events appear as synthetic NA rows", {
    ny <- f[f$change_type == "Ny", ]
    if (nrow(ny) == 0) NA else all(is.na(ny$operation) & is.na(ny$field))
  })

  check("UF-05", "every event in the event view appears in the field view", {
    ev <- brreg_updates(since = Sys.Date() - 2, size = 500, max_pages = 2)
    all(ev$update_id %in% f$update_id)
  })

  check("UF-06", "field names contain no slashes",
        !any(grepl("/", stats::na.omit(f$field))))

  check("UF-07", "move operations emit a paired remove", {
    mv <- f[f$operation %in% "move", ]
    if (nrow(mv) == 0) NA else {
      any(f$operation %in% "remove")
    }
  })

  check("UF-08", "roller is rejected for the field view",
        {
          r <- tryCatch(brreg_update_fields(since = Sys.Date() - 1, type = "roller"),
                        error = function(e) "err")
          identical(r, "err")
        })

  check("UF-09", "field values are character or NA",
        is.character(f$new_value))

  check("UF-10", "empty window yields a typed empty tibble", {
    d <- brreg_update_fields(since = Sys.Date() + 30, size = 10)
    is_typed_empty(d, c("update_id", "org_nr", "change_type", "timestamp",
                        "operation", "field", "new_value"))
  })

  check("PT-01", "parse_patch flattens a depth-2 value", {
    p <- tb$parse_patch(payload_patch(depth = 2L))
    is.data.frame(p) && nrow(p) > 0 &&
      all(c("operation", "field", "new_value") %in% names(p))
  })

  check("PT-02", "parse_patch handles depth-3 nesting", {
    p <- tb$parse_patch(payload_patch(depth = 3L))
    any(grepl("dypNode", p$field))
  })

  check("PT-03", "parse_patch emits both sides of a move", {
    p <- tb$parse_patch(payload_patch())
    sum(p$operation == "remove") >= 2L
  }, defect = "D-94")

  check("PT-04", "parse_patch expands arrays positionally", {
    p <- tb$parse_patch(payload_patch())
    any(grepl("adresse_0", p$field)) && any(grepl("adresse_1", p$field))
  })

  check("PT-05", "flatten_page_patches agrees with parse_patch on field names", {
    ev <- list(list(oppdateringsid = 1L, organisasjonsnummer = "923609016",
                    endringstype = "Endring", dato = "2026-03-01T12:00:00.000Z",
                    endringer = payload_patch(depth = 2L)))
    a <- sort(tb$flatten_page_patches(ev)$field)
    b <- sort(tb$parse_patch(payload_patch(depth = 2L))$field)
    identical(a, b)
  }, defect = "D-34")

  check("PT-06", "flatten_page_patches survives depth-3 nesting", {
    ev <- list(list(oppdateringsid = 1L, organisasjonsnummer = "923609016",
                    endringstype = "Endring", dato = "2026-03-01T12:00:00.000Z",
                    endringer = payload_patch(depth = 3L)))
    r <- tb$flatten_page_patches(ev)
    is.data.frame(r) && any(grepl("dypNode", r$field))
  }, defect = "D-34")

  check("PT-07", "flatten_page_patches emits one synthetic row for patch-less events", {
    ev <- payload_update_page(n = 3L, with_changes = FALSE)
    r <- tb$flatten_page_patches(ev)
    nrow(r) == 3L && all(is.na(r$operation))
  })

  check("PT-08", "flatten_page_patches grows past the pre-allocation", {
    ev <- payload_update_page(n = 200L, with_changes = TRUE)
    r <- tb$flatten_page_patches(ev)
    nrow(r) >= 200L
  })

  check("PT-09", "parse_updates_page handles an empty page", {
    r <- tb$parse_updates_page(list())
    is_typed_empty(r, c("update_id", "org_nr", "change_type", "timestamp"))
  })

  check("PT-10", "parse_patch on an empty patch list returns a typed empty tibble",
        is_typed_empty(tb$parse_patch(list()),
                       c("operation", "field", "new_value")))

  stress_flush()
}

test_updates()
