---
name: eks-smoke-test
description: Verify a Bottlerocket AMI joins an EKS cluster — launch a node on the AMI and confirm it registers and reaches Ready. Node-join smoke test only; conformance is the conformance-runner skill.
---

# Skill: EKS Smoke Test (node join)

Confirms a node booted from a given Bottlerocket AMI **joins an existing EKS
cluster and reaches `Ready`**. This is the fast "does it join?" gate — it does
**not** run conformance (use the `conformance-runner` skill for that).

## When to Use

- After building an AMI / updating packages, to confirm nodes still join.
- As the node-join gate before heavier tests (conformance, MACIS, etc.).

## Prerequisites

- `kubectl` access to the target EKS cluster.
- `jq` and the AWS CLI on `PATH`.
- The `launch-bottlerocket-ec2` prerequisites for launching into the cluster:
  `SUBNET_ID`, `SG_ID`, `INSTANCE_PROFILE` (the EKS node instance profile),
  and a `REGION`.

## Input

- **AMI ID** to test.
- **Cluster name** and **region**.
- **Instance type** (match the variant arch, e.g. `m5.large` x86 / `m6g.large` aarch64).

## Procedure

### 1. Launch a node on the AMI into the cluster

Delegate to the `launch-bottlerocket-ec2` skill (it builds the cluster user-data
fresh so the CA cert can't go stale):

```bash
cd ../launch-bottlerocket-ec2
./scripts/get-eks-details.sh CLUSTER_NAME /tmp/userdata.toml

export REGION=us-west-2 SUBNET_ID=subnet-... SG_ID="sg-cluster sg-controlplane" \
       INSTANCE_PROFILE=eks-node-profile INSTANCE_TYPE=m5.large
INSTANCE_ID=$(./scripts/launch-instance.sh AMI_ID /tmp/userdata.toml)
./scripts/wait-for-instance.sh "$INSTANCE_ID"
```

### 2. Verify the node joins

```bash
cd ../eks-smoke-test
./scripts/wait-for-node-join.sh "$INSTANCE_ID"        # default 300s timeout
```

Polls the cluster for the node whose `providerID` matches the instance and waits
for its `Ready` condition to be `True`. Matching on `providerID` is reliable
regardless of the node's registered name.

### 3. Clean up

```bash
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
```

## Validation

- [ ] The node registers (a node with `providerID` containing the instance ID
      appears in `kubectl get nodes`).
- [ ] The node reaches `Ready` within the timeout.

## Common Issues

**Node never registers** — usually bad user-data or a stale cluster certificate
(re-run `get-eks-details.sh` so it is fetched fresh), or the security
group/IAM role blocks the control plane. EKS nodes typically need both the
cluster SG and the control-plane SG (`SG_ID` accepts a space-separated list).

**Node registers but stays `NotReady`** — CNI not initialized or kubelet
failing. Inspect the node with the `ssm-executor` or `k8s-node-executor` skill
(`journalctl -u kubelet`).

## Supporting Files

| Script                  | Purpose                                                  |
| ----------------------- | -------------------------------------------------------- |
| `wait-for-node-join.sh` | Poll the cluster until the instance's node is `Ready`.   |

## Reference

- `launch-bottlerocket-ec2` — launches the node on the AMI.
- `conformance-runner` — Kubernetes conformance (separate, heavier test).
