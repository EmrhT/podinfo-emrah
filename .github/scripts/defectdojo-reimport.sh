#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <scan-type> <test-title> <report-file>" >&2
  exit 2
fi

: "${DEFECTDOJO_URL:?DEFECTDOJO_URL is required}"
: "${DEFECTDOJO_API_TOKEN:?DEFECTDOJO_API_TOKEN is required}"
: "${DEFECTDOJO_ENGAGEMENT_ID:?DEFECTDOJO_ENGAGEMENT_ID is required}"
: "${DEFECTDOJO_PRODUCT_NAME:?DEFECTDOJO_PRODUCT_NAME is required}"
: "${CF_ACCESS_CLIENT_ID:?CF_ACCESS_CLIENT_ID is required}"
: "${CF_ACCESS_CLIENT_SECRET:?CF_ACCESS_CLIENT_SECRET is required}"

scan_type=$1
test_title=$2
report_file=$3

[[ -f $report_file ]] || {
  echo "DefectDojo report does not exist: $report_file" >&2
  exit 2
}
[[ $DEFECTDOJO_ENGAGEMENT_ID =~ ^[1-9][0-9]*$ ]] || {
  echo "DEFECTDOJO_ENGAGEMENT_ID must be a positive integer" >&2
  exit 2
}

response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

http_status=$(curl \
  --silent \
  --show-error \
  --connect-timeout 20 \
  --max-time 300 \
  --output "$response_file" \
  --write-out '%{http_code}' \
  --header "Accept: application/json" \
  --header "Authorization: Token $DEFECTDOJO_API_TOKEN" \
  --header "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
  --header "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  --form "scan_type=$scan_type" \
  --form "test_title=$test_title" \
  --form "engagement=$DEFECTDOJO_ENGAGEMENT_ID" \
  --form "product_name=$DEFECTDOJO_PRODUCT_NAME" \
  --form "file=@$report_file" \
  --form 'minimum_severity=Info' \
  --form 'active=true' \
  --form 'verified=false' \
  --form 'close_old_findings=true' \
  --form "build_id=${GITHUB_RUN_ID:-manual}-${GITHUB_RUN_ATTEMPT:-1}" \
  --form "commit_hash=${SOURCE_SHA:-unknown}" \
  --form "branch_tag=${GITHUB_HEAD_REF:-unknown}" \
  "$DEFECTDOJO_URL/api/v2/reimport-scan/")

if [[ $http_status != 200 && $http_status != 201 ]]; then
  echo "DefectDojo rejected '$scan_type' with HTTP $http_status" >&2
  jq . "$response_file" >&2 2>/dev/null || head -c 2000 "$response_file" >&2
  exit 1
fi

jq -e . "$response_file" >/dev/null
test_id=$(jq -r '.test // .id // "unknown"' "$response_file")
echo "DefectDojo accepted '$scan_type' as test $test_id"
