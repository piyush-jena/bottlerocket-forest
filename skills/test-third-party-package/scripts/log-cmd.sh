#!/bin/bash
set -euo pipefail
# Run any command and log its output to the shared results dir for review.
# Usage: log-cmd.sh TAG CMD [ARGS...]
# Example (Type 6): log-cmd.sh keyutils ../../ssm-executor/scripts/sheltie-command.sh INSTANCE REGION "keyctl --version"
TAG="${1:?Usage: log-cmd.sh TAG CMD [ARGS...]}"; shift
[[ $# -ge 1 ]] || { echo "Usage: log-cmd.sh TAG CMD [ARGS...]" >&2; exit 1; }

RESULTS_DIR="${RESULTS_DIR:-/tmp/pkg-test-results}"; mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/${TAG}-$(date +%Y%m%d-%H%M%S).log"
echo "# logging to $LOG_FILE"
"$@" 2>&1 | tee "$LOG_FILE"
exit "${PIPESTATUS[0]}"
