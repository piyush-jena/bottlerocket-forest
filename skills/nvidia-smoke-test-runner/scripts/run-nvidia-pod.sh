#!/bin/bash
set -euo pipefail

IMAGE="public.ecr.aws/s2v1a1q8/nvidia-smoke-test:latest"
NAME="nvidia-smoke-test" TIMEOUT="180s"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

RESULTS_DIR="${RESULTS_DIR:-/tmp/pkg-test-results}"; mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/nvidia-smoke-${NAME}-$(date +%Y%m%d-%H%M%S).log"
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
      resources:
        limits:
          nvidia.com/gpu: 1
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
EOF

if kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${NAME}" --timeout="$TIMEOUT" 2>/dev/null \
   || kubectl wait --for=jsonpath='{.status.phase}'=Running "pod/${NAME}" --timeout=10s 2>/dev/null; then
  echo "PASS: GPU pod ${NAME} scheduled onto a GPU and ran."
  kubectl logs "$NAME" || true
else
  echo "FAIL: GPU pod ${NAME} did not run in ${TIMEOUT}." >&2
  kubectl describe pod "$NAME" >&2 || true
  exit 1
fi
