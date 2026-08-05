FROM europe-north1-docker.pkg.dev/sondreskarsten-d7d14/r-images/r-base:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      r-cran-tidygraph r-cran-igraph r-cran-tsibble r-cran-klassr \
      r-cran-yyjsonr r-cran-httptest2 r-cran-nanoparquet \
    && rm -rf /var/lib/apt/lists/*

RUN Rscript -e 'install.packages("tidybrreg", repos = c(sondreskarsten = "https://sondreskarsten.r-universe.dev", CRAN = "https://cloud.r-project.org"))' \
    && Rscript -e 'stopifnot(requireNamespace("tidybrreg", quietly = TRUE))'

WORKDIR /app
COPY R /app/R
COPY tests /app/tests
COPY run_all.R install.R /app/
COPY cloudrun/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV TIDYBRREG_STRESS_ROOT=/app
ENTRYPOINT ["/app/entrypoint.sh"]
