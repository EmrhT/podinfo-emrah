#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <lab-a dev/prod kustomization> <sha256 digest>" >&2
  exit 2
fi

kustomization=$1
digest=$2

case "$kustomization" in
  argocd/applications/podinfo/clusters/lab-a/dev/kustomization.yaml | \
    argocd/applications/podinfo/clusters/lab-a/prod/kustomization.yaml) ;;
  *)
    echo "refusing to modify an unexpected GitOps path: $kustomization" >&2
    exit 2
    ;;
esac

if [[ ! $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "invalid OCI image digest: $digest" >&2
  exit 2
fi

if [[ ! -f $kustomization ]]; then
  echo "GitOps kustomization does not exist: $kustomization" >&2
  exit 2
fi

digest_lines=$(grep -Ec '^[[:space:]]*digest: sha256:[0-9a-f]{64}$' "$kustomization" || true)
if [[ $digest_lines -ne 1 ]]; then
  echo "expected exactly one image digest in $kustomization, found $digest_lines" >&2
  exit 1
fi

sed -E -i "s|^([[:space:]]*digest: )sha256:[0-9a-f]{64}$|\\1${digest}|" "$kustomization"

if ! grep -Fqx "    digest: $digest" "$kustomization"; then
  echo "failed to set the requested digest in $kustomization" >&2
  exit 1
fi

