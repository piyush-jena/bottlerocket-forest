#!/usr/bin/env bash
# run-nvidia-smoke.sh — run nvidia-smoke-test on a Bottlerocket aws-mantle-1-nvidia* host via `ctr`.
#
#   Usage:  ./run-nvidia-smoke.sh [INSTANCE_ID] [REGION] [IMAGE]
#           INSTANCE_ID  arg1 OR $INSTANCE_ID env  (a running -nvidia/-nvidia-fips instance,
#                        launched with admin+control host-containers ON, SSM Online)
#           REGION       arg2 OR $REGION env       (default us-west-2)
#           IMAGE        arg3                       (default public.ecr.aws/s2v1a1q8/nvidia-smoke-test:latest)
#
#   Examples:
#           INSTANCE_ID=i-0abc123 ./run-nvidia-smoke.sh
#           ./run-nvidia-smoke.sh i-0abc123 us-west-2
#
# WHY NOT just `ctr run --device nvidia.com/gpu=all` (recorded finding, mantle-e2e-test-suite AC-6):
#   Bare `ctr run` on Bottlerocket gives the container NO SELinux label, so runc transitions it into the
#   privileged domain control_t on a READ-ONLY cache_t overlay rootfs -> every in-container write is denied
#   ("mkdir: cannot create directory '/tmp/results': Permission denied"). --device injects the GPU fine but
#   does NOT fix that. The CRI plugin / host-ctr normally apply the labels; with CRI disabled + bare `ctr`
#   we do it ourselves: writable rootfs (images mount --rw) + relabel to data_t + a custom OCI spec that sets
#   container_t/data_t + root.path=<rw rootfs> and merges the boot-generated CDI (/etc/cdi/nvidia.json).
#
# All host commands go through ./sheltie.sh (a polling copy of ssm-executor/scripts/sheltie-command.sh —
# the skill version's fixed 4s wait truncates pulls/runs). The OCI spec is delivered to the shell-less host
# with ./deliver-file.sh.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELTIE="$DIR/sheltie.sh"
DELIVER="$DIR/deliver-file.sh"
MERGE="$DIR/merge_cdi.py"

IID="${1:-${INSTANCE_ID:-}}"
[ -n "$IID" ] || { echo "ERROR: set INSTANCE_ID (arg1 or env). Usage: $0 [INSTANCE_ID] [REGION] [IMAGE]" >&2; exit 1; }
REGION="${2:-${REGION:-us-west-2}}"
IMAGE="${3:-public.ecr.aws/s2v1a1q8/nvidia-smoke-test:latest}"

NS="default"
ROOTFS="/local/nvidia-rootfs"
SPEC_HOST="/local/nvidia-oci-spec.json"
CID="nvidia-smoke1"
HELPER="nvspec"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

sh() { "$SHELTIE" "$IID" "$REGION" "$1" "${2:-600}"; }   # sh "COMMAND" [TIMEOUT]

echo "### target: $IID  region=$REGION  image=$IMAGE"

echo "### [1/9] pull image (up to ~15m)"
sh "ctr -n $NS images pull $IMAGE" 900 >/dev/null

echo "### [2/9] materialize writable rootfs -> $ROOTFS"
sh "ctr -n $NS snapshots rm $ROOTFS" 60 >/dev/null 2>&1 || true
sh "mkdir -p $ROOTFS" 60 >/dev/null
sh "ctr -n $NS images mount --rw $IMAGE $ROOTFS" 120 >/dev/null

echo "### [3/9] relabel rootfs -> data_t"
sh "chcon -R system_u:object_r:data_t:s0 $ROOTFS" 120 >/dev/null

echo "### [4/9] capture image base OCI spec via a helper container"
sh "ctr -n $NS container rm $HELPER" 60 >/dev/null 2>&1 || true
sh "ctr -n $NS container create $IMAGE $HELPER" 120 >/dev/null
sh "ctr -n $NS container info $HELPER" 60 > "$TMP/info.json"

echo "### [5/9] fetch boot-generated CDI spec (/etc/cdi/nvidia.json)"
sh "cat /etc/cdi/nvidia.json" 60 > "$TMP/cdi.json"

echo "### [6/9] merge CDI containerEdits + patch SELinux/rootfs (local)"
python3 "$MERGE" "$TMP/info.json" "$TMP/cdi.json" "$ROOTFS" > "$TMP/spec.json"
echo "    spec bytes: $(wc -c < "$TMP/spec.json")"

echo "### [7/9] deliver spec -> $SPEC_HOST"
"$DELIVER" "$IID" "$REGION" "$TMP/spec.json" "$SPEC_HOST"

echo "### [8/9] run nvidia-smoke-test via ctr (GPU) — output below"
echo "-----------------------------------------------------------------"
sh "ctr -n $NS run --rm --rootfs -c $SPEC_HOST $CID" 600
echo "-----------------------------------------------------------------"

echo "### [9/9] cleanup"
sh "ctr -n $NS container rm $HELPER" 60 >/dev/null 2>&1 || true
sh "ctr -n $NS images unmount $ROOTFS" 60 >/dev/null 2>&1 || true
sh "ctr -n $NS snapshots rm $ROOTFS" 60 >/dev/null 2>&1 || true
echo "### DONE — expect deviceQuery 'Device 0: \"NVIDIA L4\"', NumDevs = 1, Result = PASS"
