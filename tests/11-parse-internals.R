root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
source(file.path(root, "R", "payloads.R"))
library(tidybrreg)

tb <- asNamespace("tidybrreg")

test_parse_internals <- function() {
  stress_init("11-parse-internals")

  fd <- tidybrreg::field_dict

  check("P-01", "field_dict has the documented shape",
        has_cols(fd, c("api_path", "col_name", "type")) && nrow(fd) > 0)

  check("P-02", "field_dict api_path values are unique",
        !any(duplicated(fd$api_path)))

  check("P-03", "field_dict col_name values are unique",
        !any(duplicated(fd$col_name)))

  check("P-04", "field_dict types are all coercible targets",
        all(fd$type %in% c("character", "Date", "integer", "numeric", "logical")))

  check("P-05", "no two api_paths collapse to the same snake_case name",
        !any(duplicated(tb$to_snake(fd$api_path))),
        defect = "D-29")

  check("P-06", "to_snake handles camelCase",
        identical(tb$to_snake("antallAnsatte"), "antall_ansatte"))

  check("P-07", "to_snake handles dot notation",
        identical(tb$to_snake("forretningsadresse.kommune"), "forretningsadresse_kommune"))

  check("P-08", "to_snake handles digit boundaries",
        identical(tb$to_snake("naeringskode1Kode"), "naeringskode1_kode"))

  check("P-09", "to_snake is idempotent",
        identical(tb$to_snake(tb$to_snake("forretningsadresse.postNummer")),
                  tb$to_snake("forretningsadresse.postNummer")))

  raw <- payload_entity()

  check("P-10", "flatten_json produces dot-notation keys", {
    f <- tb$flatten_json(raw)
    all(c("organisasjonsnummer", "forretningsadresse.kommunenummer",
          "naeringskode1.kode") %in% names(f))
  })

  check("P-11", "flatten_json recurses past depth 2", {
    f <- tb$flatten_json(payload_entity(nested_depth = 3L))
    "dypNode.niva2.niva3.verdi" %in% names(f)
  })

  check("P-12", "unnamed arrays are joined with the same separator as the bulk path", {
    single <- tb$flatten_json(raw)[["forretningsadresse.adresse"]]
    bulk <- tb$flatten_cell(list("Forusbeen 50"))
    sep_single <- if (grepl("; ", single)) "; " else if (grepl(", ", single)) ", " else "none"
    multi_single <- tb$flatten_json(list(a = list("x", "y")))[["a"]]
    multi_bulk <- tb$flatten_cell(list("x", "y"))
    identical(multi_single, multi_bulk)
  }, defect = "D-28")

  check("P-13", "rename_from_dict maps every dictionary column", {
    m <- tb$rename_from_dict(tb$flatten_json(raw))
    all(fd$col_name %in% names(m))
  })

  check("P-14", "rename_from_dict drops nothing (zero-drop policy)", {
    f <- tb$flatten_json(payload_entity(nested_depth = 3L))
    m <- tb$rename_from_dict(f)
    keys <- setdiff(names(f), grep("^_links", names(f), value = TRUE))
    mapped <- fd$col_name[match(keys, fd$api_path)]
    expected <- ifelse(is.na(mapped), tb$to_snake(keys), mapped)
    all(expected %in% names(m))
  }, defect = "D-29")

  check("P-15", "HAL links never reach the output",
        !any(grepl("^_?links", names(tb$rename_from_dict(tb$flatten_json(raw))))))

  check("P-16", "coerce_types produces the declared classes", {
    m <- tb$coerce_types(tb$rename_from_dict(tb$flatten_json(raw)))
    date_cols <- fd$col_name[fd$type == "Date"]
    int_cols <- fd$col_name[fd$type == "integer"]
    all(vapply(date_cols, function(c) inherits(m[[c]], "Date"), logical(1))) &&
      all(vapply(int_cols, function(c) is.integer(m[[c]]), logical(1)))
  })

  check("P-17", "parse_entity returns exactly one row",
        nrow(tb$parse_entity(raw)) == 1L)

  check("P-18", "parse_entities on heterogeneous payloads keeps a stable schema", {
    a <- tb$parse_entity(payload_entity("923609016"))
    b <- tb$parse_entity(payload_entity("984851006", nested_depth = 3L))
    all(names(a) %in% names(dplyr::bind_rows(a, b)))
  })

  check("P-19", "parse_entity is invariant to field order", {
    p1 <- payload_entity()
    p2 <- p1[rev(names(p1))]
    a <- tb$parse_entity(p1)
    b <- tb$parse_entity(p2)
    identical(sort(names(a)), sort(names(b)))
  })

  check("P-20", "empty payload does not error", {
    r <- tb$parse_entity(list(organisasjonsnummer = "923609016"))
    nrow(r) == 1L
  })

  csv_ok <- synthetic_bulk_csv(bad_integers = 0L)
  csv_bad20 <- synthetic_bulk_csv(bad_integers = 20L)
  csv_bad25 <- synthetic_bulk_csv(bad_integers = 25L)

  check("P-21", "clean bulk CSV parses", {
    d <- tb$parse_bulk_csv(csv_ok)
    nrow(d) == 50L && "org_nr" %in% names(d)
  })

  check("P-22", "20 integer parse failures are reported as an attribute", {
    d <- suppressWarnings(tb$parse_bulk_csv(csv_bad20))
    p <- attr(d, "brreg_parse_problems")
    is.data.frame(p) && nrow(p) > 0
  })

  check("P-23", "more than 20 integer parse failures do not abort the parse", {
    d <- suppressWarnings(tb$parse_bulk_csv(csv_bad25))
    is.data.frame(d) && nrow(d) == 50L
  }, defect = "D-27")

  check("P-24", "parse problem table rows equal the number of failures", {
    d <- suppressWarnings(tb$parse_bulk_csv(csv_bad20))
    p <- attr(d, "brreg_parse_problems")
    nrow(p) == 20L
  }, defect = "D-27")

  check("P-25", "flatten_cell on NULL yields NA",
        is.na(tb$flatten_cell(NULL)))

  check("P-26", "flatten_cell on an empty data frame yields NA",
        is.na(tb$flatten_cell(data.frame())))

  check("P-27", "flatten_cell on a data frame yields valid JSON", {
    j <- tb$flatten_cell(data.frame(a = 1, b = "x"))
    !is.na(j) && jsonlite::validate(j)
  })

  check("P-28", "flatten_cell on a named list yields valid JSON", {
    j <- tb$flatten_cell(list(a = 1, b = "x"))
    !is.na(j) && jsonlite::validate(j)
  })

  check("P-29", "flatten_cell is total over all-NULL lists",
        is.na(tb$flatten_cell(list(NULL, NULL))))

  check("P-30", "drop_hal_links removes only link columns", {
    d <- tibble::tibble(a = 1, `_links` = 2, `x.links` = 3)
    out <- tb$drop_hal_links(d)
    "a" %in% names(out) && !any(grepl("links", names(out)))
  })

  check("P-31", "rename_and_coerce is case insensitive on api paths", {
    d <- tibble::tibble(ORGANISASJONSNUMMER = "923609016", NAVN = "X")
    out <- suppressWarnings(tb$rename_and_coerce(d))
    "org_nr" %in% names(out)
  })

  check("P-32", "rename_and_coerce adds only dictionary columns for absent fields", {
    d <- tibble::tibble(organisasjonsnummer = "923609016")
    out <- suppressWarnings(tb$rename_and_coerce(d))
    setequal(setdiff(names(out), "org_nr"), setdiff(fd$col_name, "org_nr"))
  }, defect = "D-26")

  check("P-33", "extract_entity_name handles the jsonlite shape",
        identical(tb$extract_entity_name(list(navnelinje1 = "KPMG AS")), "KPMG AS"))

  check("P-34", "extract_entity_name handles the yyjsonr shape",
        identical(tb$extract_entity_name("KPMG AS"), "KPMG AS"))

  check("P-35", "extract_entity_name handles unnamed lists",
        identical(tb$extract_entity_name(list("KPMG", "AS")), "KPMG AS"))

  check("P-36", "extract_entity_name handles NULL",
        is.na(tb$extract_entity_name(NULL)))

  check("P-37", "flatten_roles produces the documented columns", {
    r <- tb$flatten_roles(payload_roles(with_fratraadt = TRUE), "923609016")
    all(c("org_nr", "role_group", "role_group_code", "role", "role_code",
          "first_name", "middle_name", "last_name", "birth_date", "deceased",
          "entity_org_nr", "entity_name", "resigned", "deregistered",
          "ordering", "elected_by", "group_modified", "person_id") %in% names(r))
  })

  check("P-38", "flatten_roles schema is invariant to fratraadt presence", {
    a <- tb$flatten_roles(payload_roles(with_fratraadt = TRUE), "923609016")
    b <- tb$flatten_roles(payload_roles(with_fratraadt = FALSE), "923609016")
    stable_schema(a, b)
  }, defect = "D-09")

  check("P-39", "flatten_roles handles more than 200 roles", {
    r <- tb$flatten_roles(payload_roles(n_board = 400L), "923609016")
    nrow(r) >= 400L
  })

  check("P-40", "flatten_roles person_id is stable across calls", {
    a <- tb$flatten_roles(payload_roles(), "923609016")
    b <- tb$flatten_roles(payload_roles(), "923609016")
    identical(a$person_id, b$person_id)
  })

  check("P-41", "flatten_roles empty group yields a typed empty tibble", {
    r <- tb$flatten_roles(list(rollegrupper = list()), "923609016")
    is.data.frame(r) && nrow(r) == 0L && "org_nr" %in% names(r)
  }, defect = "D-05")

  check("P-42", "flatten_roles_bulk_fast matches flatten_roles", {
    a <- tb$flatten_roles(payload_roles(with_fratraadt = TRUE), "923609016")
    b <- tb$flatten_roles_bulk_fast(list(payload_roles(with_fratraadt = TRUE)))
    stable_schema(a, b) && nrow(a) == nrow(b)
  })

  check("P-43", "bulk flatten produces identical person_id to the per-org flatten", {
    a <- tb$flatten_roles(payload_roles(), "923609016")
    b <- tb$flatten_roles_bulk_fast(list(payload_roles()))
    identical(sort(a$person_id), sort(b$person_id))
  })

  check("P-44", "bulk flatten on zero entities yields typed empty", {
    r <- tb$flatten_roles_bulk_fast(list())
    is.data.frame(r) && nrow(r) == 0L && "org_nr" %in% names(r)
  }, defect = "D-05")

  check("P-45", "lookup_role passes unknown codes through",
        identical(tb$lookup_role("ZZZZ"), "ZZZZ"))

  check("P-46", "lookup_role_vec is vectorised and order preserving", {
    v <- tb$lookup_role_vec(c("LEDE", "ZZZZ", NA))
    length(v) == 3L && identical(v[2], "ZZZZ") && is.na(v[3])
  })

  check("P-47", "role_types codes are unique",
        !any(duplicated(tidybrreg::role_types$code)))

  check("P-48", "role_groups codes are unique",
        !any(duplicated(tidybrreg::role_groups$code)))

  check("P-49", "legal_forms codes are unique",
        !any(duplicated(tidybrreg::legal_forms$code)))

  check("P-50", "annotation_infotypes codes are unique",
        !any(duplicated(tidybrreg::annotation_infotypes$code)))

  check("P-51", "signature-mode role codes are present in role_types",
        all(c("SIGN", "SIFE", "SIHV", "PROK", "POFE", "POHV") %in%
              tidybrreg::role_types$code))

  check("P-52", "reference tables carry no NA labels",
        !any(is.na(tidybrreg::role_types$name_en)) &&
          !any(is.na(tidybrreg::role_groups$name_en)) &&
          !any(is.na(tidybrreg::legal_forms$name_en)))

  check("P-53", "flatten_konsern flattens a deep tree", {
    k <- tb$flatten_konsern(payload_konsern(depth = 4L), "923609016")
    nrow(k) == 9L && max(k$level) == 4L
  })

  check("P-54", "flatten_konsern synthesises the root link form", {
    k <- tb$flatten_konsern(payload_konsern(), "923609016")
    identical(k$link_form[1], "KKKK")
  })

  check("P-55", "flatten_konsern tolerates dotted date formats", {
    k <- tb$flatten_konsern(payload_konsern(dot_dates = TRUE), "923609016")
    inherits(k$relation_date, "Date")
  }, defect = "D-17")

  check("P-56", "flatten_signatur handles ISO birth dates", {
    s <- tb$flatten_signatur(payload_signatur(iso_dates = TRUE), "923609016", "signature")
    inherits(s$birth_date, "Date") && !all(is.na(s$birth_date))
  }, defect = "D-18")

  check("P-57", "flatten_signatur handles dotted birth dates", {
    s <- tb$flatten_signatur(payload_signatur(iso_dates = FALSE), "923609016", "signature")
    !all(is.na(s$birth_date))
  })

  check("P-58", "flatten_signatur keeps rules with no persons", {
    s <- tb$flatten_signatur(payload_signatur(empty_persons = TRUE), "923609016", "signature")
    nrow(s) == 1L && is.na(s$name[1])
  })

  check("P-59", "flatten_signatur returns the documented columns", {
    s <- tb$flatten_signatur(payload_signatur(), "923609016", "signature")
    all(c("org_nr", "entity_name", "signature_type", "rule_status", "rule_text",
          "combination_id", "combination_code", "rule", "name", "birth_date",
          "role_code", "role") %in% names(s))
  })

  check("P-60", "compact drops NULLs only",
        identical(tb$compact(list(a = 1, b = NULL, c = NA)), list(a = 1, c = NA)))

  stress_flush()
}

test_parse_internals()
