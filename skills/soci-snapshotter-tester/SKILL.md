---
name: soci-snapshotter-tester
description: Validate the soci-snapshotter package by enabling the soci snapshotter on a Bottlerocket node (via settings) and confirming a pod pulls and runs through it.
---

# Skill: SOCI Snapshotter Tester

Validates the `soci-snapshotter` package (Type 4) by switching a Bottlerocket
node's snapshotter to `soci` with parallel pull-unpack settings, then scheduling
a pod and confirming it pulls its image through soci and runs.

## When to Use

- After updating the `soci-snapshotter` package.

## Prerequisites

- A Bottlerocket K8s node on the AMI under test (the snapshotter is a host
  setting, so this targets a specific node).
- `ssm-executor` connectivity to that node **or** the ability to set the
  snapshotter via user-data at launch (`launch-bottlerocket-ec2`).
- `kubectl` access to the cluster.

## Procedure

### 1. Enable the soci snapshotter on the node

Either bake these settings into the instance **user-data** at launch, or apply
them to a running node. The settings:

```toml
[settings.container-runtime]
snapshotter = "soci"
[settings.container-runtime-plugins.soci-snapshotter]
pull-mode = "parallel-pull-unpack"
[settings.container-runtime-plugins.soci-snapshotter.parallel-pull-unpack]
concurrent-download-chunk-size = "8mb"
discard-unpacked-layers = true
max-concurrent-downloads = 12
max-concurrent-downloads-per-image = 5
max-concurrent-unpacks = 8
max-concurrent-unpacks-per-image = 4
```

Apply to a running node over SSM (wraps `apiclient apply` via sheltie):

```bash
./scripts/configure-node.sh INSTANCE_ID REGION
```

Equivalent manual form on the node:

```bash
sheltie
bash# apiclient apply <<EOF
[settings.container-runtime]
snapshotter = "soci"
...
EOF
```

### 2. Deploy a pod and verify it pulls through soci

```bash
./scripts/run-soci-pod.sh
```

Applies and waits on:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: soci-smoke-test
spec:
  containers:
  - name: rabbitmq
    image: public.ecr.aws/docker/library/rabbitmq:4.1.0
```

Then checks:

```bash
kubectl get pod soci-smoke-test
kubectl logs soci-smoke-test
```

## Validation

- [ ] `apiclient get settings.container-runtime.snapshotter` returns `soci` on the node.
- [ ] `soci-smoke-test` reaches `Running` and `kubectl logs` shows RabbitMQ start-up.
- [ ] On the node, `journalctl -u soci-snapshotter-grpc` (via `ssm-executor`)
      shows pull/unpack activity and no errors.

## Common Issues

**Pod runs but soci was not used** — the snapshotter setting did not take effect
before the image was pulled. Confirm `settings.container-runtime.snapshotter=soci`
on the node and that containerd restarted, then delete/re-create the pod so the
image is pulled fresh.

**`apiclient apply` rejected** — a key name changed between soci versions; check
`apiclient get settings.container-runtime-plugins.soci-snapshotter` for the valid
schema on the AMI under test.

## Supporting Files

| Script              | Purpose                                                       |
| ------------------- | ------------------------------------------------------------- |
| `configure-node.sh` | Apply the soci snapshotter settings to a running node via SSM/sheltie. |
| `run-soci-pod.sh`   | Deploy the `soci-smoke-test` pod, wait, print logs, clean up. |
