#!/usr/bin/env bash
# Inventory every on-disk artefact the suite's function calls produce.
# No size filter: every file is catalogued with a full SHA-256, and every file is
# published by the caller. Nothing is copied here - the tmp/ tree is uploaded in
# place, so disk usage stays flat on memory-backed filesystems.
set -uo pipefail

ROOT="${TIDYBRREG_STRESS_ROOT:-/app}"
cd "$ROOT" || { echo "cannot cd to $ROOT"; exit 0; }

mkdir -p results
INV="${ROOT}/results/artifact_inventory.tsv"
printf 'path\tbytes\tmtime_utc\tsha256\n' > "$INV"

if [ ! -d tmp ]; then
  echo "no tmp/ tree to inventory"
  exit 0
fi

while IFS= read -r f; do
  bytes=$(stat -c %s "$f" 2>/dev/null || echo 0)
  mtime=$(date -u -d "@$(stat -c %Y "$f" 2>/dev/null || echo 0)" +%Y-%m-%dT%H:%M:%SZ)
  sha=$(sha256sum "$f" 2>/dev/null | cut -c1-64)
  printf '%s\t%s\t%s\t%s\n' "$f" "$bytes" "$mtime" "$sha" >> "$INV"
done < <(find tmp -type f 2>/dev/null | sort)

TOTAL=$(awk 'NR>1' "$INV" | wc -l)
BYTES=$(awk -F'\t' 'NR>1 {s+=$2} END {print s+0}' "$INV")

{
  echo "artefact inventory"
  echo "  files written by the run : ${TOTAL}"
  echo "  total bytes on disk      : ${BYTES}"
  echo
  echo "by store:"
  awk -F'\t' 'NR>1 {split($1,a,"/"); s[a[2]]+=$2; n[a[2]]++}
              END {for (k in s) printf "  %-18s %6d files %14d bytes\n", k, n[k], s[k]}' "$INV"
  echo
  echo "duplicate content (same sha256 under different paths):"
  awk -F'\t' 'NR>1 {c[$4]++; p[$4]=p[$4]" "$1}
              END {n=0; for (k in c) if (c[k]>1) {n++; printf "  %s ->%s\n", substr(k,1,16), p[k]}
                   if (n==0) print "  none"}' "$INV"
  echo
  echo "directory tree (depth 5):"
  find tmp -maxdepth 5 2>/dev/null | sed 's/^/  /' | head -120
} > "${ROOT}/results/artifact_summary.txt"

cat "${ROOT}/results/artifact_summary.txt"
