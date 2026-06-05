#!/bin/bash
set -euo pipefail

AMI="" ARCH="" K8S_VERSION="1.35" REGION="us-west-2" NODES="15" INSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ami) AMI="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --kubernetes-version) K8S_VERSION="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --nodes) NODES="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${AMI:?--ami is required}"
case "$ARCH" in
  x86_64)  INSTANCE_TYPE="m5.xlarge" ;;
  aarch64) INSTANCE_TYPE="m6g.xlarge" ;;
  *) echo "--arch must be x86_64 or aarch64" >&2; exit 1 ;;
esac
MARKER="latest-${K8S_VERSION}.txt"

RESULTS_DIR="${RESULTS_DIR:-/tmp/pkg-test-results}"; mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/conformance-${K8S_VERSION}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "# logging to $LOG_FILE"

if [[ "$INSTALL" == 1 ]]; then
  go install sigs.k8s.io/kubetest2/...@latest
  go install sigs.k8s.io/kubetest2/kubetest2-tester-ginkgo@latest
  go install sigs.k8s.io/provider-aws-test-infra/kubetest2-ec2@latest
fi
export PATH="$PATH:$HOME/go/bin"
export AWS_REGION="$REGION"

exec kubetest2 eksapi \
  --region "$REGION" \
  --kubernetes-version "$K8S_VERSION" \
  --user-data-format bottlerocket \
  --unmanaged-nodes \
  --ami "$AMI" \
  --instance-types "$INSTANCE_TYPE" \
  --nodes "$NODES" \
  --down --up \
  --test ginkgo \
  -- \
  --test-package-marker "$MARKER" \
  --parallel "$NODES" \
  --ginkgo-args --flake-attempts=3 \
  --focus-regex='\[Conformance\]' \
  --skip-regex='\[Serial\]|\[Disruptive\]|\[Slow\]|Garbage.collector'
