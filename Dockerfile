FROM europe-north1-docker.pkg.dev/sondreskarsten-d7d14/r-images/r-base:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends r-base-core r-recommended \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
      r-cran-tidygraph r-cran-igraph r-cran-tsibble r-cran-klassr \
      r-cran-yyjsonr r-cran-httptest2 r-cran-nanoparquet \
    && rm -rf /var/lib/apt/lists/* \
    && Rscript -e 'pkgs <- c("rlang","cli","vctrs","tibble","dplyr","tidyr","readr","vroom","httr2","jsonlite","arrow","nanoparquet","tidygraph","igraph","tsibble","klassR","yyjsonr","curl"); bad <- pkgs[!vapply(pkgs, function(p) suppressWarnings(requireNamespace(p, quietly = TRUE)), logical(1))]; if (length(bad)) stop("ABI/load failure: ", paste(bad, collapse=", ")); cat("all", length(pkgs), "packages load\n")'

RUN Rscript -e 'install.packages("tidybrreg", repos = c(sondreskarsten = "https://sondreskarsten.r-universe.dev", CRAN = "https://cloud.r-project.org"))' \
    && Rscript -e 'stopifnot(requireNamespace("tidybrreg", quietly = TRUE))'

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      curl gnupg ca-certificates python3 \
    && curl -sS https://packages.cloud.google.com/apt/doc/apt-key.gpg \
       | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
       > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update -qq && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/* \
    && gcloud --version | head -1

WORKDIR /app
COPY R /app/R
COPY tests /app/tests
COPY run_all.R install.R Dockerfile compare_to_evaluation.R EVALUATION.md /app/
COPY cloudrun /app/cloudrun
RUN chmod +x /app/cloudrun/*.sh && cp /app/cloudrun/entrypoint.sh /app/entrypoint.sh

ENV TIDYBRREG_STRESS_ROOT=/app
ENTRYPOINT ["/app/entrypoint.sh"]
