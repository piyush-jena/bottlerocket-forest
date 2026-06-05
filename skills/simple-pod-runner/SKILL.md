---
name: simple-pod-runner
description: Smoke-test a Bottlerocket K8s node by scheduling a simple pod and confirming it pulls its image and runs. Used to validate runc/pigz-tier (Type 1) package updates.
---

# Skill: Simple Pod Runner

Deploys a minimal pod to a Bottlerocket node and confirms it is scheduled,
pulls its image, and runs. This exercises the container runtime path
(containerd + runc + image decompression via pigz), which is enough to validate
Type 1 package updates (`runc`, `pigz`).

## When to Use

- After updating `runc` or `pigz` (Type 1).
- As a quick "can this node run a container at all?" check.

## Prerequisites

- `kubectl` access to a cluster whose nodes run the AMI under test.
- Network/IAM access to pull the test image (default lives in ECR
  `533267423195.dkr.ecr.us-west-2.amazonaws.com`).

## Input

| Flag        | Default                                                                 | Purpose          |
| ----------- | ----------------------------------------------------------------------- | ---------------- |
| `--image`   | `533267423195.dkr.ecr.us-west-2.amazonaws.com/hello-nodejs:latest`      | Image to run.    |
| `--name`    | `hello-nodejs`                                                          | Pod name.        |
| `--timeout` | `120s`                                                                  | Wait budget.     |

## Procedure

```bash
./scripts/run-pod.sh                 # defaults (hello-nodejs)
./scripts/run-pod.sh --image <img>   # custom image
```

The script applies this manifest, waits for the pod to reach `Running`, prints
its logs, then deletes it:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello-nodejs
  labels:
    app: hello-nodejs
spec:
  restartPolicy: Never
  containers:
    - name: hello-nodejs
      image: 533267423195.dkr.ecr.us-west-2.amazonaws.com/hello-nodejs:latest
      imagePullPolicy: Always
```

## Validation

- [ ] Pod reaches `Running` (or `Succeeded`) — image pulled and container started.
- [ ] `kubectl logs` shows the app output.
- [ ] No `ImagePullBackOff` / `CreateContainerError` / `CrashLoopBackOff`.

## Common Issues

**`ImagePullBackOff`** — node IAM role lacks ECR pull permission, or no network
path to the registry. Confirm the node role has `AmazonEC2ContainerRegistryReadOnly`.

**`CreateContainerError` / runc errors** — most relevant after a `runc` update;
inspect with `kubectl describe pod <name>` and the node's containerd logs via the
`ssm-executor` skill (`journalctl -u containerd`).

**Pod stuck `Pending`** — no schedulable node on the target AMI; check
`kubectl get nodes` and taints.

## Supporting Files

| Script       | Purpose                                              |
| ------------ | ---------------------------------------------------- |
| `run-pod.sh` | Apply the pod, wait, print logs, and clean up.       |
