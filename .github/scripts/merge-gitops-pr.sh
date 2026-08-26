#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <repository> <pull-request-number>" >&2
  exit 2
fi

repository=$1
pull_request=$2
last_error=

for _ in {1..12}; do
  metadata=$(gh pr view "$pull_request" \
    --repo "$repository" \
    --json state,mergeStateStatus,isDraft)
  state=$(jq -r '.state' <<<"$metadata")
  merge_state=$(jq -r '.mergeStateStatus' <<<"$metadata")
  is_draft=$(jq -r '.isDraft' <<<"$metadata")

  if [[ $state == MERGED ]]; then
    echo "GitOps PR #$pull_request is already merged."
    exit 0
  fi
  if [[ $state != OPEN ]]; then
    echo "GitOps PR #$pull_request is $state and cannot be merged" >&2
    exit 1
  fi
  if [[ $is_draft == true || $merge_state == DIRTY ]]; then
    echo "GitOps PR #$pull_request is not safely mergeable: $merge_state" >&2
    exit 1
  fi

  if [[ $merge_state == CLEAN ]]; then
    if merge_output=$(gh pr merge "$pull_request" \
      --repo "$repository" --squash 2>&1); then
      printf '%s\n' "$merge_output"
      exit 0
    fi
    last_error=$merge_output
  elif [[ $merge_state != UNKNOWN ]]; then
    if merge_output=$(gh pr merge "$pull_request" \
      --repo "$repository" --auto --squash 2>&1); then
      printf '%s\n' "$merge_output"
      exit 0
    fi
    last_error=$merge_output
  fi

  # GitHub can change BLOCKED to CLEAN between the view and merge calls.
  # Re-read mergeability instead of treating that harmless race as fatal.
  sleep 2
done

echo "GitOps PR #$pull_request did not reach a mergeable state" >&2
[[ -z $last_error ]] || printf '%s\n' "$last_error" >&2
exit 1

