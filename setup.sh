#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y --no-install-recommends \
  ca-certificates gnupg wget lsb-release software-properties-common \
  libcurl4-openssl-dev libssl-dev libxml2-dev

CODENAME="$(lsb_release -cs)"

wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
  > /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
echo "deb [arch=amd64] https://cloud.r-project.org/bin/linux/ubuntu ${CODENAME}-cran40/" \
  > /etc/apt/sources.list.d/cran.list

wget -qO- https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc \
  > /etc/apt/trusted.gpg.d/cranapt_key.asc
echo "deb [arch=amd64] https://r2u.stat.illinois.edu/ubuntu ${CODENAME} main" \
  > /etc/apt/sources.list.d/cranapt.list

cat > /etc/apt/preferences.d/99cranapt <<'EOF'
Package: *
Pin: release o=CRAN-Apt Project
Pin: origin "r2u.stat.illinois.edu"
Pin-Priority: 700
EOF

apt-get update -qq

apt-get install -y --no-install-recommends \
  r-base-core r-base-dev \
  r-cran-arrow r-cran-nanoparquet r-cran-duckdb \
  r-cran-dplyr r-cran-tibble r-cran-tidyr r-cran-readr r-cran-rlang r-cran-cli \
  r-cran-httr2 r-cran-jsonlite r-cran-yyjsonr r-cran-curl \
  r-cran-tidygraph r-cran-igraph r-cran-tsibble r-cran-klassr \
  r-cran-testthat r-cran-withr r-cran-httptest2 r-cran-jsonvalidate

Rscript install.R
