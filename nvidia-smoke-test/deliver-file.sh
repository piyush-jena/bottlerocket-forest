#!/usr/bin/env bash
# deliver-file.sh INSTANCE_ID REGION LOCAL_FILE HOST_DEST_PATH [CHUNK]
# Copies a local file to the Bottlerocket HOST filesystem at HOST_DEST_PATH by base64-piping
# it through the admin container's view of host root (/.bottlerocket/rootfs). The host root is
# shell-less, so we run bash INSIDE the admin container. Large files are chunked (the apiclient
# exec websocket resets on very large argv): append base64 chunks, then decode.
# (Copied from planning/mantle-e2e-test-suite/scripts/deliver-file.sh — self-contained.)
set -euo pipefail
INSTANCE_ID="${1:?}"; REGION="${2:?}"; LOCAL_FILE="${3:?}"; HOST_DEST="${4:?}"
CHUNK="${5:-6000}"
HOSTPATH="/.bottlerocket/rootfs${HOST_DEST}"
B64FILE="${HOSTPATH}.b64"
B64=$(base64 -w0 "$LOCAL_FILE")

send() {  # send a single AWS-RunShellScript command (one array element), wait
  local inner="$1"
  local pf; pf=$(mktemp)
  python3 - "$inner" > "$pf" <<'PY'
import json,sys
print(json.dumps({"commands":[sys.argv[1]]}))
PY
  local cid; cid=$(aws ssm send-command --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" --parameters "file://$pf" \
    --region "$REGION" --query 'Command.CommandId' --output text)
  local st="Pending"
  for _ in $(seq 1 30); do
    sleep 2
    st=$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$INSTANCE_ID" \
      --region "$REGION" --query 'Status' --output text 2>/dev/null || echo Pending)
    case "$st" in Success|Failed|Cancelled|TimedOut) break;; esac
  done
  rm -f "$pf"
  [ "$st" = "Success" ] || { echo "chunk failed: $st"; aws ssm get-command-invocation \
     --command-id "$cid" --instance-id "$INSTANCE_ID" --region "$REGION" \
     --query 'StandardErrorContent' --output text; return 1; }
}

# start fresh
send "apiclient exec admin bash -c \"rm -f ${B64FILE} ${HOSTPATH}\""
# append base64 in chunks
n=${#B64}; i=0; idx=0
while [ $i -lt $n ]; do
  part="${B64:$i:$CHUNK}"
  send "apiclient exec admin bash -c \"printf %s ${part} >> ${B64FILE}\""
  i=$((i+CHUNK)); idx=$((idx+1))
done
# decode + cleanup
send "apiclient exec admin bash -c \"base64 -d ${B64FILE} > ${HOSTPATH} && rm -f ${B64FILE}\""
echo "### DELIVER OK: $LOCAL_FILE -> $HOST_DEST ($idx chunks of $CHUNK)"
