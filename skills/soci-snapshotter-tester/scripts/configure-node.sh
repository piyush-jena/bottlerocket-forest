#!/bin/bash
set -euo pipefail
INSTANCE_ID="${1:?Usage: configure-node.sh INSTANCE_ID REGION}"
REGION="${2:?Usage: configure-node.sh INSTANCE_ID REGION}"

RESULTS_DIR="${RESULTS_DIR:-/tmp/pkg-test-results}"; mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/soci-configure-${INSTANCE_ID}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "# logging to $LOG_FILE"

read -r -d '' TOML <<'EOF' || true
[settings.container-runtime]
snapshotter = "soci"
[settings.container-runtime-plugins.soci-snapshotter]
pull-mode = "parallel-pull-unpack"
[settings.container-runtime-plugins.soci-snapshotter.parallel-pull-unpack]
concurrent-download-chunk-size = "8mb"
discard-unpacked-layers = true
max-concurrent-downloads = 12
max-concurrent-downloads-per-image = 5
max-concurrent-unpacks = 8
max-concurrent-unpacks-per-image = 4
EOF

# base64 the TOML so it survives SSM/JSON/sheltie quoting; decode + apply on the node.
B64=$(base64 -w0 <<<"$TOML")
NODE_CMD="apiclient exec admin sheltie -- bash -c \"echo ${B64} | base64 -d | apiclient apply\""
PARAMS=$(python3 -c 'import json,sys; print(json.dumps({"commands":[sys.stdin.read()]}))' <<<"$NODE_CMD")

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "$PARAMS" \
  --region "$REGION" \
  --query 'Command.CommandId' --output text)
sleep 6
aws ssm get-command-invocation \
  --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --region "$REGION" \
  --query 'StandardOutputContent' --output text
echo "Applied. Verify: settings.container-runtime.snapshotter should be 'soci'."
