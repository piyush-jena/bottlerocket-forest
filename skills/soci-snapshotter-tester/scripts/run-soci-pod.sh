#!/bin/bash
set -euo pipefail
NAME="soci-smoke-test"
IMAGE="public.ecr.aws/docker/library/rabbitmq:4.1.0"
TIMEOUT="180s"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

RESULTS_DIR="${RESULTS_DIR:-/tmp/pkg-test-results}"; mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/soci-pod-${NAME}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "# logging to $LOG_FILE"

cleanup() { kubectl delete pod "$NAME" --ignore-not-found --wait=false; }
trap cleanup EXIT

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}
spec:
  containers:
  - name: rabbitmq
    image: ${IMAGE}
EOF

if kubectl wait --for=jsonpath='{.status.phase}'=Running "pod/${NAME}" --timeout="$TIMEOUT" 2>/dev/null; then
  echo "PASS: ${NAME} pulled through soci and is Running."
  kubectl get pod "$NAME"
  kubectl logs "$NAME" || true
else
  echo "FAIL: ${NAME} did not reach Running in ${TIMEOUT}." >&2
  kubectl describe pod "$NAME" >&2 || true
  exit 1
fi
