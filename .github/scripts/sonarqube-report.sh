#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <output-zip>" >&2
  exit 2
fi

: "${SONAR_HOST_URL:?SONAR_HOST_URL is required}"
: "${SONAR_TOKEN:?SONAR_TOKEN is required}"
: "${SONAR_PROJECT_KEY:?SONAR_PROJECT_KEY is required}"
: "${SONAR_MTLS_PKCS12_PATH:?SONAR_MTLS_PKCS12_PATH is required}"

# OpenSSL permits PKCS#12 bundles with an empty import password. The existing
# Sonar scanner configuration supports that, so the report exporter must too.
SONAR_MTLS_KEYSTORE_PASSWORD=${SONAR_MTLS_KEYSTORE_PASSWORD:-}

output_zip=$1
report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT

[[ -f $SONAR_MTLS_PKCS12_PATH ]] || {
  echo "SonarQube mTLS keystore does not exist: $SONAR_MTLS_PKCS12_PATH" >&2
  exit 2
}

fetch_pages() {
  local endpoint=$1
  local project_parameter=$2
  local result_property=$3
  local file_prefix=$4
  local filter_parameter=${5:-}
  local -a filter_arguments=()
  local page=1
  local page_size=500
  local total=0
  local fetched=0
  local output_file

  if [[ -n $filter_parameter ]]; then
    filter_arguments=(--data-urlencode "$filter_parameter")
  fi

  while :; do
    output_file="$report_dir/${file_prefix}-${page}.json"

    curl \
      --silent \
      --show-error \
      --fail-with-body \
      --connect-timeout 20 \
      --max-time 120 \
      --retry 3 \
      --retry-all-errors \
      --cert-type P12 \
      --cert "$SONAR_MTLS_PKCS12_PATH:$SONAR_MTLS_KEYSTORE_PASSWORD" \
      --header "Accept: application/json" \
      --header "Authorization: Bearer $SONAR_TOKEN" \
      --get \
      --data-urlencode "$project_parameter=$SONAR_PROJECT_KEY" \
      --data-urlencode "p=$page" \
      --data-urlencode "ps=$page_size" \
      "${filter_arguments[@]}" \
      --output "$output_file" \
      "$SONAR_HOST_URL$endpoint"

    jq -e \
      --arg property "$result_property" \
      '.paging.total >= 0 and (.[$property] | type == "array")' \
      "$output_file" >/dev/null

    total=$(jq -r '.paging.total' "$output_file")
    fetched=$((fetched + $(jq -r --arg property "$result_property" '.[$property] | length' "$output_file")))

    (( fetched >= total )) && break
    ((page++))

    if (( page > 1000 )); then
      echo "SonarQube pagination exceeded 1000 pages for $endpoint" >&2
      exit 1
    fi
  done

  echo "Exported $fetched SonarQube $result_property"
}

fetch_pages '/api/issues/search' 'projects' 'issues' 'issues' 'resolved=false'
fetch_pages '/api/hotspots/search' 'projectKey' 'hotspots' 'hotspots' 'status=TO_REVIEW'

mkdir -p "$(dirname "$output_zip")"
rm -f "$output_zip"
zip -q -j "$output_zip" "$report_dir"/*.json
unzip -tq "$output_zip" >/dev/null

echo "Created SonarQube report: $output_zip"
