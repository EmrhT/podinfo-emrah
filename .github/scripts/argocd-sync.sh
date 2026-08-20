#!/usr/bin/env bash

set -euo pipefail

: "${ARGOCD_SERVER:?ARGOCD_SERVER is required}"
: "${ARGOCD_AUTH_TOKEN:?ARGOCD_AUTH_TOKEN is required}"
: "${CF_ACCESS_CLIENT_ID:?CF_ACCESS_CLIENT_ID is required}"
: "${CF_ACCESS_CLIENT_SECRET:?CF_ACCESS_CLIENT_SECRET is required}"
: "${ARGOCD_APP:?ARGOCD_APP is required}"
: "${IAC_REVISION:?IAC_REVISION is required}"
: "${IMAGE_DIGEST:?IMAGE_DIGEST is required}"

argo=(
  argocd
  --server "$ARGOCD_SERVER"
  --auth-token "$ARGOCD_AUTH_TOKEN"
  --grpc-web
  --header "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID"
  --header "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET"
)

echo "Waiting for $ARGOCD_APP to observe Git revision $IAC_REVISION"
for _ in {1..60}; do
  app_json=$("${argo[@]}" app get "$ARGOCD_APP" --refresh -o json)
  observed_revision=$(jq -r '.status.sync.revision // ""' <<<"$app_json")
  if [[ $observed_revision == "$IAC_REVISION" ]]; then
    break
  fi
  sleep 10
done

if [[ ${observed_revision:-} != "$IAC_REVISION" ]]; then
  echo "$ARGOCD_APP did not observe Git revision $IAC_REVISION within 10 minutes" >&2
  "${argo[@]}" app get "$ARGOCD_APP"
  exit 1
fi

# Argo CD remains the only component that writes to Kubernetes. The runner asks
# it to reconcile the Git revision already merged into the GitOps repository.
"${argo[@]}" app sync "$ARGOCD_APP" --timeout 600
"${argo[@]}" app wait "$ARGOCD_APP" --sync --health --operation --timeout 600

app_json=$("${argo[@]}" app get "$ARGOCD_APP" --refresh -o json)
if ! jq -e --arg digest "$IMAGE_DIGEST" \
  '.status.summary.images | any(endswith("@" + $digest))' <<<"$app_json" >/dev/null; then
  echo "$ARGOCD_APP is healthy, but it does not report the expected image digest $IMAGE_DIGEST" >&2
  jq '.status.summary.images' <<<"$app_json" >&2
  exit 1
fi

echo "$ARGOCD_APP is Synced and Healthy on $IMAGE_DIGEST"

