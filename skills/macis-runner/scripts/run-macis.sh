#!/bin/bash
set -euo pipefail
# Best-effort: requires Amazon-internal isengard + git.amazon.com access.
# Will not run from a standard dev environment.

AMI_ID="" INSTANCE_TYPE="m5.8xlarge" TASK_ARN="" WAIT=600 ACCOUNT="932817054917" ROLE="Administrator"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ami-id) AMI_ID="$2"; shift 2 ;;
    --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
    --task-arn) TASK_ARN="$2"; shift 2 ;;
    --wait) WAIT="$2"; shift 2 ;;          # seconds to wait before fetching results (default 600 = 10 min)
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

RESULTS_DIR="${RESULTS_DIR:-/tmp/pkg-test-results}"; mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/macis-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "# logging to $LOG_FILE"

command -v isengard >/dev/null || { echo "isengard not found: run this on an Amazon-internal host." >&2; exit 2; }

fetch_results() { isengard "$ACCOUNT" "$ROLE" exec -- ./macis-get-tests-results.sh --task-arn "$1"; }

# Fetch-only mode.
if [[ -n "$TASK_ARN" ]]; then fetch_results "$TASK_ARN"; exit 0; fi

: "${AMI_ID:?--ami-id is required (ECS-variant AMI)}"
[[ -d Bottlerocket-release-scripts ]] || git clone ssh://git.amazon.com/pkg/Bottlerocket-release-scripts

echo "Starting MACIS tests for $AMI_ID ($INSTANCE_TYPE)..."
START_OUT=$(isengard "$ACCOUNT" "$ROLE" exec -- \
  ./Bottlerocket-release-scripts/bin/macis-start-tests.sh \
  --instance-type "$INSTANCE_TYPE" --ami-id "$AMI_ID")
echo "$START_OUT"

TASK_ARN=$(grep -oE 'arn:aws[^[:space:]]*task[^[:space:]]*' <<<"$START_OUT" | head -1)
[[ -n "$TASK_ARN" ]] || { echo "Could not parse a task ARN from the start output; fetch manually with --task-arn." >&2; exit 1; }
echo "Task ARN: $TASK_ARN"

echo "Waiting ${WAIT}s (~$((WAIT/60)) min) for MACIS results..."
sleep "$WAIT"
fetch_results "$TASK_ARN"
