#!/usr/bin/env bash
# Inventory and selectively publish the on-disk artefacts the suite's function calls
# produce. Large payloads (bulk caches, full state parquet) are catalogued but not
# uploaded; everything small enough to be inspectable is uploaded verbatim.
set -uo pipefail

ROOT="${TIDYBRREG_STRESS_ROOT:-/app}"
OUT="${1:-${ROOT}/results/artifacts}"
MAX_UPLOAD_BYTES="${MAX_UPLOAD_BYTES:-52428800}"   # 50 MB per file

mkdir -p "$OUT"
cd "$ROOT" || exit 0

INV="${ROOT}/results/artifact_inventory.tsv"
printf 'path\tbytes\tmtime_utc\tsha256\tuploaded\n' > "$INV"

[ -d tmp ] || { echo "no tmp/ tree to inventory"; exit 0; }

while IFS= read -r f; do
  bytes=$(stat -c %s "$f" 2>/dev/null || echo 0)
  mtime=$(date -u -d "@$(stat -c %Y "$f" 2>/dev/null || echo 0)" +%Y-%m-%dT%H:%M:%SZ)

  if [ "$bytes" -le "$MAX_UPLOAD_BYTES" ]; then
    sha=$(sha256sum "$f" 2>/dev/null | cut -c1-64)
    dest="${OUT}/${f#tmp/}"
    mkdir -p "$(dirname "$dest")"
    cp -p "$f" "$dest" 2>/dev/null && up=yes || up=copy_failed
  else
    # too large to publish: still fingerprint the head so content is identifiable
    sha=$(head -c 1048576 "$f" 2>/dev/null | sha256sum | cut -c1-64)
    sha="head1m:${sha}"
    up=no_too_large
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$bytes" "$mtime" "$sha" "$up" >> "$INV"
done < <(find tmp -type f 2>/dev/null | sort)

TOTAL=$(awk 'NR>1' "$INV" | wc -l)
UP=$(awk -F'\t' 'NR>1 && $5=="yes"' "$INV" | wc -l)
BYTES=$(awk -F'\t' 'NR>1 {s+=$2} END {print s+0}' "$INV")

{
  echo "artefact inventory"
  echo "  files written by the run : ${TOTAL}"
  echo "  files published verbatim : ${UP}"
  echo "  total bytes on disk      : ${BYTES}"
  echo
  echo "by store:"
  awk -F'\t' 'NR>1 {split($1,a,"/"); s[a[2]]+=$2; n[a[2]]++}
              END {for (k in s) printf "  %-18s %6d files %12d bytes\n", k, n[k], s[k]}' "$INV"
  echo
  echo "directory tree (depth 4):"
  find tmp -maxdepth 4 2>/dev/null | sed 's/^/  /' | head -60
} > "${ROOT}/results/artifact_summary.txt"

cat "${ROOT}/results/artifact_summary.txt"
