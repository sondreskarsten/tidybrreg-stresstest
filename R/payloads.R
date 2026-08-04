payload_entity <- function(org_nr = "923609016", name = "EQUINOR ASA",
                           nested_depth = 2L, with_links = TRUE) {
  out <- list(
    organisasjonsnummer = org_nr,
    navn = name,
    organisasjonsform = list(kode = "ASA", beskrivelse = "Allmennaksjeselskap"),
    registreringsdatoEnhetsregisteret = "1995-05-18",
    registrertIMvaregisteret = TRUE,
    naeringskode1 = list(kode = "06.100", beskrivelse = "Utvinning av rovolje"),
    antallAnsatte = 21000L,
    forretningsadresse = list(
      land = "Norge", landkode = "NO", postnummer = "4035",
      poststed = "STAVANGER", adresse = list("Forusbeen 50"),
      kommune = "STAVANGER", kommunenummer = "1103"
    ),
    stiftelsesdato = "1972-09-14",
    konkurs = FALSE,
    underAvvikling = FALSE
  )
  if (nested_depth >= 3L) {
    out$dypNode <- list(niva2 = list(niva3 = list(verdi = "x")))
  }
  if (with_links) {
    out[["_links"]] <- list(self = list(href = "https://data.brreg.no/x"))
  }
  out
}

payload_roles <- function(org_nr = "923609016", with_fratraadt = FALSE,
                          n_board = 3L, with_auditor = TRUE) {
  mk_person <- function(i) {
    r <- list(
      type = list(kode = if (i == 1L) "LEDE" else "MEDL"),
      person = list(
        navn = list(fornavn = paste0("Fornavn", i), etternavn = paste0("Etternavn", i)),
        fodselsdato = sprintf("19%02d-01-0%d", 60 + i, i),
        erDoed = FALSE
      ),
      rekkefolge = i - 1L,
      avregistrert = FALSE
    )
    if (with_fratraadt) r$fratraadt <- FALSE
    r
  }
  grupper <- list(list(
    type = list(kode = "STYR"),
    sistEndret = "2025-04-01",
    roller = lapply(seq_len(n_board), mk_person)
  ))
  if (with_auditor) {
    grupper <- c(grupper, list(list(
      type = list(kode = "REVI"),
      sistEndret = "2025-04-01",
      roller = list(list(
        type = list(kode = "REVI"),
        enhet = list(organisasjonsnummer = "976389387",
                     navn = list(navnelinje1 = "KPMG AS")),
        avregistrert = FALSE
      ))
    )))
  }
  list(organisasjonsnummer = org_nr, rollegrupper = grupper)
}

payload_patch <- function(depth = 1L) {
  base <- list(
    list(op = "replace", path = "/antallAnsatte", value = 42L),
    list(op = "remove", path = "/hjemmeside"),
    list(op = "add", path = "/forretningsadresse/adresse", value = list("Gate 1", "Gate 2")),
    list(op = "move", path = "/postadresse", from = "/forretningsadresse")
  )
  if (depth >= 2L) {
    base <- c(base, list(list(op = "replace", path = "/naeringskode1",
                              value = list(kode = "62.010", beskrivelse = "Programmering"))))
  }
  if (depth >= 3L) {
    base <- c(base, list(list(op = "replace", path = "/dypNode",
                              value = list(niva2 = list(niva3 = "verdi")))))
  }
  base
}

payload_update_page <- function(n = 3L, with_changes = TRUE, first_id = 1000L,
                                change_types = c("Endring", "Ny", "Sletting")) {
  lapply(seq_len(n), function(i) {
    ct <- change_types[((i - 1L) %% length(change_types)) + 1L]
    u <- list(
      oppdateringsid = first_id + i,
      organisasjonsnummer = sprintf("9236090%02d", i),
      endringstype = ct,
      dato = sprintf("2026-03-0%dT12:00:00.000Z", i)
    )
    if (with_changes && ct == "Endring") u$endringer <- payload_patch(depth = 2L)
    u
  })
}

payload_konsern <- function(org_nr = "923609016", depth = 3L, dot_dates = FALSE) {
  mk <- function(level, idx) {
    node <- list(
      organisasjonsnummer = sprintf("9%08d", 10000000 + level * 100 + idx),
      navn = paste0("Node L", level, "-", idx),
      nivaa = level,
      knytningsform = list(kode = "KDAT", beskrivelse = "Konsern datter"),
      grunnlag = "100%",
      dato = if (dot_dates) "24.06.2026" else "2026-06-24",
      organisasjonsform = list(kode = "AS", beskrivelse = "Aksjeselskap")
    )
    if (level < depth) node$children <- list(mk(level + 1L, idx))
    node
  }
  list(
    organisasjonsnummer = org_nr,
    navn = "ROOT ASA",
    nivaa = 0L,
    grunnlag = NULL,
    dato = if (dot_dates) "24.06.2026" else "2026-06-24",
    organisasjonsform = list(kode = "ASA", beskrivelse = "Allmennaksjeselskap"),
    children = list(mk(1L, 1L), mk(1L, 2L))
  )
}

payload_signatur <- function(org_nr = "923609016", iso_dates = FALSE, empty_persons = FALSE) {
  person <- list(navn = "Ola Nordmann",
                 fodselsdato = if (iso_dates) "1965-03-12" else "12.03.1965",
                 rolle = list(kode = "SIGN"))
  komb <- list(list(
    kombinasjonsId = "1",
    kode = "SIFE",
    tekstforklaring = "Styret i fellesskap",
    personRolleKombinasjon = if (empty_persons) list() else list(person)
  ))
  list(
    enhet = list(navn = "EQUINOR ASA", organisasjonsnummer = org_nr),
    status = list(regelStatus = list(kode = "RF")),
    signeringsGrunnlag = list(signaturProkuraRoller = list(signaturProkuraFritekst = "Fritekst")),
    signeringsKombinasjon = list(kombinasjon = komb)
  )
}

synthetic_bulk_csv <- function(path = tempfile(fileext = ".csv.gz"),
                               n = 50L, bad_integers = 25L) {
  ansatte <- as.character(seq_len(n))
  if (bad_integers > 0) {
    ansatte[seq_len(min(bad_integers, n))] <- "ikke_tall"
  }
  df <- data.frame(
    organisasjonsnummer = sprintf("9%08d", seq_len(n)),
    navn = paste("Firma", seq_len(n)),
    `organisasjonsform.kode` = "AS",
    antallAnsatte = ansatte,
    registreringsdatoEnhetsregisteret = "2020-01-01",
    check.names = FALSE
  )
  con <- gzfile(path, "w")
  utils::write.csv(df, con, row.names = FALSE, quote = TRUE)
  close(con)
  path
}

synthetic_roles_state <- function(org_nr = "900000001", n = 3L, shift = 0L) {
  tibble::tibble(
    org_nr = org_nr,
    role_group_code = "STYR",
    role_group = "Board of Directors",
    role_code = c("LEDE", rep("MEDL", n - 1L))[seq_len(n)],
    role = c("Chair of the Board", rep("Board member", n - 1L))[seq_len(n)],
    first_name = paste0("F", seq_len(n) + shift),
    middle_name = NA_character_,
    last_name = paste0("L", seq_len(n) + shift),
    birth_date = as.Date("1970-01-01") + seq_len(n),
    deceased = FALSE,
    entity_org_nr = NA_character_,
    entity_name = NA_character_,
    deregistered = FALSE,
    ordering = seq_len(n) - 1L,
    elected_by = NA_character_,
    group_modified = as.Date("2025-01-01"),
    person_id = paste0(as.Date("1970-01-01") + seq_len(n), "_l", seq_len(n) + shift,
                       "_f", seq_len(n) + shift, "_")
  )
}
