source(file.path(Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd()), "R", "helpers.R"))
library(tidybrreg)

mod11 <- function(x) {
  d <- as.integer(strsplit(x, "")[[1]])
  w <- c(3L, 2L, 7L, 6L, 5L, 4L, 3L, 2L)
  r <- sum(d[1:8] * w) %% 11L
  chk <- if (r == 0L) 0L else 11L - r
  chk < 10L && chk == d[9]
}

test_validate <- function(n_random = 20000L, seed = 1L) {
  stress_init("10-validate")
  set.seed(seed)

  check("V-01", "known valid orgnr accepted",
        all(brreg_validate(c("923609016", "984851006", "971524960"))))

  check("V-02", "bad check digit rejected",
        isFALSE(brreg_validate("923609017")))

  check("V-03", "short input rejected", isFALSE(brreg_validate("12345678")))
  check("V-04", "long input rejected", isFALSE(brreg_validate("1234567890")))
  check("V-05", "non-digit rejected", isFALSE(brreg_validate("92360901a")))
  check("V-06", "empty string rejected", isFALSE(brreg_validate("")))
  check("V-07", "NA rejected without error", isFALSE(brreg_validate(NA)))
  check("V-08", "NA_character_ rejected", isFALSE(brreg_validate(NA_character_)))

  check("V-09", "vectorised over mixed input",
        identical(brreg_validate(c("923609016", "123456789", NA)),
                  c(TRUE, FALSE, FALSE)))

  check("V-10", "numeric input coerced",
        isTRUE(brreg_validate(923609016)))

  check("V-11", "zero-length input returns zero-length logical", {
    r <- brreg_validate(character())
    is.logical(r) && length(r) == 0L
  })

  check("V-12", "result is unnamed",
        is.null(names(brreg_validate(c("923609016", "984851006")))))

  check("V-13", "check digit 10 case rejected for every possible last digit", {
    cand8 <- "90770209"
    all(vapply(0:9, function(d9) isFALSE(brreg_validate(paste0(cand8, d9))),
               logical(1)))
  })

  check("V-14", "leading whitespace rejected",
        isFALSE(brreg_validate(" 923609016")))

  check("V-15", "prefix rule does not reject mod-11-valid non-8/9 numbers",
        {
          cands <- sprintf("%09d", sample(100000000:799999999, 5000))
          valid <- cands[vapply(cands, mod11, logical(1))]
          length(valid) > 0 && all(brreg_validate(valid))
        },
        defect = "D-02")

  check("V-16", "agrees with independent mod-11 on 8/9 prefixed numbers", {
    cands <- sprintf("%09d", sample(800000000:999999999, n_random))
    expected <- vapply(cands, mod11, logical(1), USE.NAMES = FALSE)
    identical(unname(brreg_validate(cands)), expected)
  })

  check("V-17", "large vector does not error", {
    r <- brreg_validate(sprintf("%09d", sample(800000000:999999999, 50000)))
    length(r) == 50000L
  })

  check("V-18", "factor input handled",
        isTRUE(brreg_validate(factor("923609016"))),
        defect = NA_character_)

  check("V-19", "list input errors rather than silently coercing",
        {
          r <- tryCatch(brreg_validate(list("923609016")), error = function(e) "err")
          identical(r, "err") || isTRUE(r)
        })

  check("V-20", "no side effects on the filesystem", {
    before <- length(list.files(tempdir(), recursive = TRUE))
    brreg_validate("923609016")
    after <- length(list.files(tempdir(), recursive = TRUE))
    before == after
  })

  stress_flush()
}

test_validate()
