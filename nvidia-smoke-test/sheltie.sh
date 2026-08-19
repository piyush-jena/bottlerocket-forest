#!/usr/bin/env bash
# sheltie.sh — polling copy of ssm-executor/scripts/sheltie-command.sh.
#
# The skill's sheltie-command.sh sends the command then sleeps a FIXED 4s and returns
# StandardOutputContent — which truncates any host command that takes longer than 4s
# (image pulls, the GPU container run, etc.). This copy POLLS the SSM invocation to
# completion, then returns the host command's stdout (stderr + status go to our stderr).
#
# Runs a SINGLE host binary via:  apiclient exec admin sheltie -- <COMMAND>
# (The Bottlerocket host root is shell-less: no pipes / no `bash -c` — one binary + args.)
#
# Usage: sheltie.sh INSTANCE_ID REGION "COMMAND" [TIMEOUT_SECONDS]
#   e.g. sheltie.sh i-0abc us-west-2 "ctr -n default images pull public.ecr.aws/.../x:latest" 900
#
# NOTE: SSM returns only the last ~24000 chars of StandardOutputContent inline; fine for
# `ctr container info` / `cat /etc/cdi/nvidia.json`, but very chatty commands may be clipped.
set -euo pipefail

IID="${1:?Usage: sheltie.sh INSTANCE_ID REGION COMMAND [TIMEOUT]}"
REGION="${2:?Usage: sheltie.sh INSTANCE_ID REGION COMMAND [TIMEOUT]}"
COMMAND="${3:?Usage: sheltie.sh INSTANCE_ID REGION COMMAND [TIMEOUT]}"
TIMEOUT="${4:-600}"

# Build the parameters JSON safely (COMMAND has spaces/flags; avoid shell-quoting bugs).
PARAMS=$(python3 - "$COMMAND" <<'PY'
import json, sys
print(json.dumps({"commands": ["apiclient exec admin sheltie -- " + sys.argv[1]]}))
PY
)

CID=$(aws ssm send-command \
  --instance-ids "$IID" \
  --document-name "AWS-RunShellScript" \
  --parameters "$PARAMS" \
  --region "$REGION" \
  --query 'Command.CommandId' --output text)

st="Pending"; waited=0
while :; do
  st=$(aws ssm get-command-invocation --command-id "$CID" --instance-id "$IID" \
       --region "$REGION" --query 'Status' --output text 2>/dev/null || echo Pending)
  case "$st" in Success|Failed|Cancelled|TimedOut) break;; esac
  sleep 5; waited=$((waited+5))
  if [ "$waited" -ge "$TIMEOUT" ]; then st="TimedOut(local)"; break; fi
done

OUT=$(aws ssm get-command-invocation --command-id "$CID" --instance-id "$IID" \
      --region "$REGION" --query 'StandardOutputContent' --output text 2>/dev/null || true)
ERR=$(aws ssm get-command-invocation --command-id "$CID" --instance-id "$IID" \
      --region "$REGION" --query 'StandardErrorContent' --output text 2>/dev/null || true)

printf '%s' "$OUT"
[ -n "$ERR" ] && printf '%s\n' "$ERR" >&2
if [ "$st" != "Success" ]; then
  echo "[sheltie] status=$st cmd=$CID instance=$IID" >&2
  exit 1
fi
