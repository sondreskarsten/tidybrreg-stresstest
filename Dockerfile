FROM europe-north1-docker.pkg.dev/sondreskarsten-d7d14/r-images/r-base:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      r-base-core r-recommended \
      r-cran-rlang r-cran-cli r-cran-vctrs r-cran-tibble r-cran-dplyr \
      r-cran-httr2 r-cran-jsonlite r-cran-readr r-cran-arrow \
      r-cran-tidygraph r-cran-igraph r-cran-tsibble r-cran-klassr \
      r-cran-yyjsonr r-cran-httptest2 r-cran-nanoparquet r-cran-tidyr \
    && rm -rf /var/lib/apt/lists/* \
    && Rscript -e 'stopifnot(requireNamespace("rlang", quietly = TRUE), requireNamespace("arrow", quietly = TRUE))'

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
COPY run_all.R install.R /app/
COPY cloudrun/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV TIDYBRREG_STRESS_ROOT=/app
ENTRYPOINT ["/app/entrypoint.sh"]
