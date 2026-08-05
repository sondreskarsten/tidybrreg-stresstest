#!/usr/bin/env bash
set -uo pipefail

ROOT="${TIDYBRREG_STRESS_ROOT:-/app}"
cd "$ROOT"

RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)"
GCS_PREFIX="${GCS_PREFIX:-gs://sondre_brreg_data/raw/tidybrreg_stresstest}"
DEST="${GCS_PREFIX}/run_date=${RUN_ID}"

mkdir -p results/logs

echo "== tidybrreg stresstest ${RUN_ID} =="
Rscript --vanilla -e 'cat(R.version.string, "| tidybrreg", as.character(utils::packageVersion("tidybrreg")), "\n")'

Rscript --vanilla -e '
  env <- list(
    r_version = R.version.string,
    tidybrreg_version = as.character(utils::packageVersion("tidybrreg")),
    tidybrreg_desc = as.list(utils::packageDescription("tidybrreg")),
    exports = sort(getNamespaceExports("tidybrreg")),
    captured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  dir.create("results", showWarnings = FALSE)
  saveRDS(env, "results/environment.rds")'

Rscript --vanilla run_all.R
RUN_STATUS=$?

Rscript --vanilla run_all.R summarise | tee results/summary.txt

echo "== capturing artefacts written by the run =="
bash "${ROOT}/cloudrun/capture_artifacts.sh" || echo "artefact capture failed (non-fatal)"
echo "run_all exit status: ${RUN_STATUS}"

if command -v gcloud >/dev/null 2>&1; then
  echo "publishing results to ${DEST}"
  gcloud storage cp -r results "${DEST}/results" 2>&1 | tail -3

  for item in tests R run_all.R install.R Dockerfile cloudrun; do
    if [ -e "$item" ]; then
      gcloud storage cp -r "$item" "${DEST}/code/$item" 2>&1 | tail -2
    else
      echo "  skip (absent in image): $item"
    fi
  done

  PUBLISHED=$(gcloud storage ls "${DEST}/results/**" 2>/dev/null | wc -l)
  echo "published objects under ${DEST}/results: ${PUBLISHED}"
  if [ "${PUBLISHED}" -eq 0 ]; then
    echo "FATAL: publish produced no objects" >&2
    UPLOAD_FAILED=1
  fi
else
  echo "FATAL: gcloud not available in image; results cannot be published" >&2
  echo "results left in ${ROOT}/results" >&2
  UPLOAD_FAILED=1
fi

REGRESSIONS=$(Rscript --vanilla -e '
  s <- tryCatch(readRDS("results/summary.rds"), error = function(e) NULL)
  cat(if (is.null(s)) 0L else sum(s$results$outcome == "regression"))' 2>/dev/null)

echo "unexplained regressions: ${REGRESSIONS:-unknown}"
if [ "${FAIL_ON_REGRESSION:-1}" = "1" ] && [ "${REGRESSIONS:-0}" != "0" ]; then
  exit 1
fi
exit 0
