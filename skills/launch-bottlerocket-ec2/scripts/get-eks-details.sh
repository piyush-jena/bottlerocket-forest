#!/bin/bash
set -euo pipefail
CLUSTER_NAME="${1:?Usage: get-eks-details.sh CLUSTER_NAME [OUTFILE]}"
OUTFILE="${2:-/tmp/userdata.toml}"

# Fetch cluster details and produce a ready-to-use userdata TOML atomically.
# This eliminates the gap where a cached or hand-copied certificate can go stale.
CLUSTER_JSON=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query 'cluster.{endpoint:endpoint,ca:certificateAuthority.data,name:name}' \
  --output json)

ENDPOINT=$(echo "$CLUSTER_JSON" | jq -r '.endpoint')
CA=$(echo "$CLUSTER_JSON" | jq -r '.ca')
NAME=$(echo "$CLUSTER_JSON" | jq -r '.name')

cat > "$OUTFILE" <<EOF
[settings.kubernetes]
api-server = "$ENDPOINT"
cluster-name = "$NAME"
cluster-certificate = "$CA"
EOF

echo "Wrote $OUTFILE" >&2
echo "$OUTFILE"
