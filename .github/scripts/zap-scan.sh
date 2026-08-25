#!/usr/bin/env bash

set -euo pipefail

: "${ZAP_API_URL:?ZAP_API_URL is required}"
: "${ZAP_API_KEY:?ZAP_API_KEY is required}"
: "${CF_ACCESS_CLIENT_ID:?CF_ACCESS_CLIENT_ID is required}"
: "${CF_ACCESS_CLIENT_SECRET:?CF_ACCESS_CLIENT_SECRET is required}"

plan_path=${ZAP_PLAN_PATH:-/zap/automation/podinfo-lab-a-dev.yaml}
target_url=${ZAP_TARGET_URL:-http://podinfo.lab-a-dev.svc.cluster.local:9898}
report_dir=${ZAP_REPORT_DIR:-reports}

mkdir -p "$report_dir"

zap_headers=(
  --header "Accept: application/json"
  --header "X-ZAP-API-Key: $ZAP_API_KEY"
  --header "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID"
  --header "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET"
)
curl_common=(
  --fail-with-body
  --silent
  --show-error
  --retry 3
  --retry-all-errors
  --connect-timeout 20
  --max-time 90
)

# Each CI scan gets a clean volatile ZAP session so old manual findings cannot
# make a later deployment fail. The automation plan and API key remain intact.
curl "${curl_common[@]}" "${zap_headers[@]}" \
  "$ZAP_API_URL/JSON/core/action/newSession/" >/dev/null

start_response=$(curl "${curl_common[@]}" "${zap_headers[@]}" --get \
  --data-urlencode "filePath=$plan_path" \
  "$ZAP_API_URL/JSON/automation/action/runPlan/")
plan_id=$(jq -er '.planId' <<<"$start_response")
echo "ZAP automation plan $plan_id started"

finished=
for _ in {1..180}; do
  progress=$(curl "${curl_common[@]}" "${zap_headers[@]}" --get \
    --data-urlencode "planId=$plan_id" \
    "$ZAP_API_URL/JSON/automation/view/planProgress/")
  printf '%s\n' "$progress" >"$report_dir/zap-plan-progress.json"
  finished=$(jq -r '.finished // empty' <<<"$progress")
  [[ -n $finished ]] && break
  sleep 10
done

if [[ -z $finished ]]; then
  echo "ZAP automation plan $plan_id did not finish within 30 minutes" >&2
  exit 1
fi

curl "${curl_common[@]}" "${zap_headers[@]}" --get \
  --data-urlencode "baseurl=$target_url" \
  "$ZAP_API_URL/JSON/core/view/alerts/" >"$report_dir/zap-alerts.json"

plan_errors=$(jq '.error | length' "$report_dir/zap-plan-progress.json")
high_alerts=$(jq '[.alerts[] | select(.risk == "High" or .riskcode == "3")] | length' \
  "$report_dir/zap-alerts.json")

echo "ZAP finished at $finished with $plan_errors plan error(s) and $high_alerts high-risk alert(s)"
if (( plan_errors > 0 )); then
  echo "ZAP automation-plan errors:" >&2
  jq -r '.error[] | if type == "string" then "- \(.)" else "- \(.message // tostring)" end' \
    "$report_dir/zap-plan-progress.json" >&2
fi
jq -r '.alerts[] | select(.risk == "High" or .riskcode == "3") | "- [\(.risk)] \(.alert): \(.url)"' \
  "$report_dir/zap-alerts.json" || true

if (( plan_errors > 0 || high_alerts > 0 )); then
  exit 1
fi
