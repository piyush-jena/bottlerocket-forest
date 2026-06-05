---
name: nvidia-smoke-test-runner
description: Smoke-test GPU support on a Bottlerocket NVIDIA node by scheduling a pod that requests a GPU and confirming it runs. Validates the NVIDIA package stack.
---

# Skill: NVIDIA Smoke Test Runner

Schedules a pod that requests `nvidia.com/gpu: 1` onto a Bottlerocket GPU node
and confirms it pulls, schedules onto a GPU, and runs. This exercises the full
NVIDIA stack: device plugin, container toolkit, libnvidia-container, and the
driver.

## When to Use

- After updating NVIDIA-tier packages (`nvidia-k8s-device-plugin`,
  `nvidia-container-toolkit`, `libnvidia-container`, etc.).
- Validating GPU scheduling on an `aws-k8s-*-nvidia` variant AMI.

## Prerequisites

- `kubectl` access to a cluster with at least one Bottlerocket **GPU** node on
  the AMI under test (e.g. a `g`/`p`-family instance).
- The NVIDIA device plugin is advertising `nvidia.com/gpu` capacity
  (`kubectl get nodes -o json | jq '.items[].status.allocatable'`).
- Network access to pull `public.ecr.aws/s2v1a1q8/nvidia-smoke-test:latest`.

## Input

| Flag        | Default                                            | Purpose       |
| ----------- | -------------------------------------------------- | ------------- |
| `--image`   | `public.ecr.aws/s2v1a1q8/nvidia-smoke-test:latest` | Image to run. |
| `--name`    | `nvidia-smoke-test`                                | Pod name.     |
| `--timeout` | `180s`                                             | Wait budget.  |

## Procedure

```bash
./scripts/run-nvidia-pod.sh
```

Applies this manifest, waits for it to run/complete, prints logs, then deletes it:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nvidia-smoke-test
  labels:
    app: nvidia-smoke-test
spec:
  restartPolicy: Never
  containers:
    - name: nvidia-smoke-test
      image: public.ecr.aws/s2v1a1q8/nvidia-smoke-test:latest
      imagePullPolicy: Always
      resources:
        limits:
          nvidia.com/gpu: 1
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
EOF
```

## Validation

- [ ] Pod is scheduled (not `Pending` for lack of `nvidia.com/gpu`).
- [ ] Pod reaches `Running`/`Succeeded` and logs show the GPU was detected
      (e.g. `nvidia-smi` output / device info).
- [ ] No `UnexpectedAdmissionError` or runtime/toolkit errors.

## Common Issues

**Pod stuck `Pending`, `Insufficient nvidia.com/gpu`** — the device plugin is
not running or not advertising GPUs. Check the `nvidia-device-plugin` DaemonSet
and the node's driver via the `ssm-executor` skill.

**`failed to create shim` / OCI runtime hook error** — most relevant after a
`nvidia-container-toolkit`/`libnvidia-container` update; inspect containerd and
the NVIDIA runtime hook logs on the node.

**Driver/CUDA mismatch in logs** — the container's CUDA version may exceed the
node driver; use an image compatible with the driver shipped in the AMI.

## Supporting Files

| Script              | Purpose                                          |
| ------------------- | ------------------------------------------------ |
| `run-nvidia-pod.sh` | Apply the GPU pod, wait, print logs, clean up.   |
