#!/bin/bash
set -euo pipefail

IMAGE="533267423195.dkr.ecr.us-west-2.amazonaws.com/hello-nodejs:latest"
NAME="hello-nodejs" TIMEOUT="120s"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

RESULTS_DIR="${RESULTS_DIR:-/tmp/pkg-test-results}"; mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/simple-pod-${NAME}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "# logging to $LOG_FILE"

cleanup() { kubectl delete pod "$NAME" --ignore-not-found --wait=false; }
trap cleanup EXIT

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}
  labels:
    app: ${NAME}
spec:
  restartPolicy: Never
  containers:
    - name: ${NAME}
      image: ${IMAGE}
      imagePullPolicy: Always
EOF

# Pass when the pod is Running (server-style) or already Succeeded (batch-style).
if kubectl wait --for=jsonpath='{.status.phase}'=Running "pod/${NAME}" --timeout="$TIMEOUT" 2>/dev/null \
   || kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${NAME}" --timeout=10s 2>/dev/null; then
  echo "PASS: pod ${NAME} pulled its image and ran."
  kubectl logs "$NAME" || true
else
  echo "FAIL: pod ${NAME} did not run in ${TIMEOUT}." >&2
  kubectl describe pod "$NAME" >&2 || true
  exit 1
fi
