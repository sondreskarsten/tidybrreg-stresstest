#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-sondreskarsten-d7d14}"
REGION="${REGION:-europe-north1}"
SCHEDULER_REGION="${SCHEDULER_REGION:-europe-west1}"
REPO="${REPO:-brreg-pipelines}"
JOB="${JOB:-tidybrreg-stresstest}"
SA="${SA:-s1sfreracct@sondreskarsten-d7d14.iam.gserviceaccount.com}"
BUILD_BUCKET="${BUILD_BUCKET:-gs://sondreskarsten-d7d14_cloudbuild}"
TAG="$(git rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/${JOB}:${TAG}"

TOKEN="$(gcloud auth print-access-token)"

echo "== 1. upload build context =="
CTX="$(mktemp -d)/context.tar.gz"
tar --exclude=".git" --exclude="tmp" --exclude="results" -czf "$CTX" \
  Dockerfile R tests run_all.R install.R cloudrun
gcloud storage cp "$CTX" "${BUILD_BUCKET}/${JOB}/context.tar.gz"

echo "== 2. submit Cloud Build via REST =="
BUILD_BODY=$(cat <<EOF
{
  "source": {
    "storageSource": {
      "bucket": "$(echo "${BUILD_BUCKET}" | sed 's|gs://||')",
      "object": "${JOB}/context.tar.gz"
    }
  },
  "steps": [
    {
      "name": "gcr.io/cloud-builders/docker",
      "args": ["build", "-t", "${IMAGE}", "."]
    }
  ],
  "images": ["${IMAGE}"],
  "timeout": "3600s",
  "options": {"machineType": "E2_HIGHCPU_8"}
}
EOF
)

BUILD_ID=$(curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://cloudbuild.googleapis.com/v1/projects/${PROJECT}/builds" \
  -d "${BUILD_BODY}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["metadata"]["build"]["id"])')

echo "build id: ${BUILD_ID}"
while true; do
  STATUS=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
    "https://cloudbuild.googleapis.com/v1/projects/${PROJECT}/builds/${BUILD_ID}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status","UNKNOWN"))')
  echo "  build status: ${STATUS}"
  [ "${STATUS}" = "SUCCESS" ] && break
  case "${STATUS}" in FAILURE|INTERNAL_ERROR|TIMEOUT|CANCELLED)
    echo "build failed"; exit 1;; esac
  sleep 20
done

DIGEST=$(gcloud artifacts docker images describe "${IMAGE}" \
  --format='value(image_summary.digest)')
IMAGE_PINNED="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/${JOB}@${DIGEST}"
echo "pinned image: ${IMAGE_PINNED}"

echo "== 3. create or update the Cloud Run Job =="
JOB_BODY=$(cat <<EOF
{
  "template": {
    "taskCount": 1,
    "template": {
      "serviceAccount": "${SA}",
      "maxRetries": 0,
      "timeout": "21600s",
      "containers": [
        {
          "image": "${IMAGE_PINNED}",
          "resources": {"limits": {"cpu": "8", "memory": "32Gi"}},
          "env": [
            {"name": "STRESS_CORES", "value": "${STRESS_CORES:-4}"},
            {"name": "STRESS_ROLLER", "value": "${STRESS_ROLLER:-1}"},
            {"name": "STRESS_JSON", "value": "${STRESS_JSON:-1}"},
            {"name": "STRESS_SAMPLE_ROWS", "value": "${STRESS_SAMPLE_ROWS:-50000}"},
            {"name": "FAIL_ON_REGRESSION", "value": "${FAIL_ON_REGRESSION:-1}"}
          ]
        }
      ]
    }
  }
}
EOF
)

if gcloud run jobs describe "${JOB}" --region "${REGION}" >/dev/null 2>&1; then
  METHOD=PATCH
  URL="https://${REGION}-run.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/jobs/${JOB}"
else
  METHOD=POST
  URL="https://${REGION}-run.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/jobs?jobId=${JOB}"
fi

curl -s -X "${METHOD}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${URL}" -d "${JOB_BODY}" | head -20

echo
echo "== 4. weekly scheduler (${SCHEDULER_REGION}) =="
TRIGGER_URI="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT}/jobs/${JOB}:run"
gcloud scheduler jobs create http "${JOB}-weekly" \
  --location "${SCHEDULER_REGION}" \
  --schedule "17 3 * * 1" \
  --time-zone "Europe/Oslo" \
  --uri "${TRIGGER_URI}" \
  --http-method POST \
  --oauth-service-account-email "${SA}" \
  2>/dev/null || \
gcloud scheduler jobs update http "${JOB}-weekly" \
  --location "${SCHEDULER_REGION}" \
  --schedule "17 3 * * 1" \
  --time-zone "Europe/Oslo" \
  --uri "${TRIGGER_URI}" \
  --http-method POST \
  --oauth-service-account-email "${SA}"

echo
echo "deployed. run now with:"
echo "  gcloud run jobs execute ${JOB} --region ${REGION}"
