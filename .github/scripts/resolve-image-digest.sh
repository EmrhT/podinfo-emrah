#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <image-reference>" >&2
  exit 2
fi

image_reference=$1
manifest=$(docker buildx imagetools inspect "$image_reference" --format '{{json .Manifest}}')
digest=$(jq -er '.digest' <<<"$manifest")

if [[ ! $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "registry returned an invalid digest for $image_reference: $digest" >&2
  exit 1
fi

printf '%s\n' "$digest"
