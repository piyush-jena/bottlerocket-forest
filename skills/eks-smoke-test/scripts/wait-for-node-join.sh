#!/bin/bash
set -euo pipefail
INSTANCE_ID="${1:?Usage: wait-for-node-join.sh INSTANCE_ID [TIMEOUT_SECONDS]}"
TIMEOUT="${2:-300}"
INTERVAL=10
deadline=$(( $(date +%s) + TIMEOUT ))

echo "Waiting for instance $INSTANCE_ID to register and become Ready (timeout ${TIMEOUT}s)..."
while :; do
  node=$(kubectl get nodes -o json 2>/dev/null \
    | jq -r --arg id "$INSTANCE_ID" '.items[] | select((.spec.providerID // "") | contains($id)) | .metadata.name' \
    | head -1)
  if [[ -n "$node" ]]; then
    ready=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$ready" == "True" ]]; then
      echo "PASS: node $node (instance $INSTANCE_ID) joined and is Ready."
      kubectl get node "$node"
      exit 0
    fi
  fi
  if (( $(date +%s) >= deadline )); then
    echo "FAIL: instance $INSTANCE_ID did not reach Ready within ${TIMEOUT}s." >&2
    if [[ -n "$node" ]]; then kubectl describe node "$node" >&2; else echo "(node never registered)" >&2; fi
    exit 1
  fi
  sleep "$INTERVAL"
done
