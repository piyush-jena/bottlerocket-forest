#!/usr/bin/env bash
# Behavior probe for crashLoopBackOff.maxContainerRestartPeriod (settings.kubernetes.max-container-restart-period).
# Runs a container that exits at once on each NODE (in parallel) and records when each restart
# happens. The gaps between restarts are the kubelet's effective backoff: they double from 10s
# toward 300s by default, and stop growing at the configured maximum.
#
# Usage: crashloop-backoff-probe.sh SECONDS NODE [NODE...]
# Test nodes are expected to carry the taint k8s-settings-test=...:NoSchedule; pods tolerate it.
set -euo pipefail
duration=${1:?usage: crashloop-backoff-probe.sh SECONDS NODE [NODE...]}
shift
ns=k8s-settings-test
kubectl get ns $ns >/dev/null 2>&1 || kubectl create ns $ns >/dev/null

declare -A pod
for node in "$@"; do
  name=crashloop-$(echo "$node" | cut -d. -f1)
  pod[$node]=$name
  kubectl -n $ns delete pod "$name" --ignore-not-found --wait=true >/dev/null
  kubectl -n $ns apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $name
spec:
  nodeName: $node
  tolerations:
  - {key: k8s-settings-test, operator: Exists, effect: NoSchedule}
  restartPolicy: Always
  containers:
  - name: crash
    image: public.ecr.aws/docker/library/busybox:1.36
    command: ["sh", "-c", "exit 1"]
YAML
done

start=$(date +%s)
declare -A last times
while [ $(( $(date +%s) - start )) -lt "$duration" ]; do
  for node in "$@"; do
    n=$(kubectl -n $ns get pod "${pod[$node]}" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)
    if [ "${n:-0}" != "${last[$node]:-0}" ]; then
      times[$node]="${times[$node]:-} $(( $(date +%s) - start ))"
      last[$node]=$n
    fi
  done
  sleep 1
done

for node in "$@"; do
  configz=$(kubectl get --raw "/api/v1/nodes/$node/proxy/configz" | jq -c '.kubeletconfig.crashLoopBackOff')
  gaps=$(echo "${times[$node]:-}" | awk '{for (i = 2; i <= NF; i++) printf "%s%d", (i > 2 ? " " : ""), $i - $(i-1)}')
  echo "$node: crashLoopBackOff=$configz restarts=${last[$node]:-0} in ${duration}s, gaps between restarts (s): ${gaps:-none}"
  kubectl -n $ns delete pod "${pod[$node]}" --wait=false >/dev/null
done
