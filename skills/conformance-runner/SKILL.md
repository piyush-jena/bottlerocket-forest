---
name: conformance-runner
description: Run Kubernetes conformance tests against a Bottlerocket AMI by standing up a throwaway EKS cluster with kubetest2 eksapi, running ginkgo conformance, then tearing it down.
---

# Skill: Conformance Runner

Runs Kubernetes `[Conformance]` tests against a given Bottlerocket AMI.
Unlike rolling an existing cluster, this skill uses `kubetest2 eksapi` with
`--up --down --unmanaged-nodes` to create a dedicated cluster, join nodes built
from the AMI, run the ginkgo conformance suite, and destroy everything on exit.

This replaces the old `hydrophone-runner` skill.

## When to Use

- Verifying a freshly built Bottlerocket K8s AMI passes Kubernetes conformance.
- Validating `kubernetes-1.30` … `kubernetes-1.36` package updates (Type 2).
- Running conformance once per cluster type (Kubernetes minor version).

## Required Inputs

| Parameter      | Description                                              |
| -------------- | -------------------------------------------------------- |
| `--ami`        | AMI ID to test (e.g. `ami-0123…`).                       |
| `--arch`       | `x86_64` or `aarch64`. Selects the instance type.        |

## Optional Inputs

| Flag                  | Default       | Purpose                                              |
| --------------------- | ------------- | ---------------------------------------------------- |
| `--kubernetes-version`| `1.35`        | Cluster + test-package version. Match the AMI/variant.|
| `--region`            | `us-west-2`   | AWS region.                                          |
| `--nodes`             | `15`          | Number of unmanaged nodes to join.                   |
| `--install`           | (off)         | `go install` the kubetest2 binaries before running.  |

Instance type is derived from `--arch`:

| arch      | instance type |
| --------- | ------------- |
| `x86_64`  | `m5.xlarge`   |
| `aarch64` | `m6g.xlarge`  |

The ginkgo test-package marker is derived from `--kubernetes-version`
(e.g. `1.35` → `latest-1.35.txt`).

## Prerequisites

- Go toolchain on `PATH` (for `go install`).
- AWS credentials with EKS/EC2/IAM/CloudFormation permissions to create and
  destroy an EKS cluster and unmanaged nodes.
- `kubetest2`, `kubetest2-tester-ginkgo`, and `kubetest2-ec2` on `PATH`
  (or pass `--install` to install them).

Install the tooling (also done by `--install`):

```bash
go install sigs.k8s.io/kubetest2/...@latest
go install sigs.k8s.io/kubetest2/kubetest2-tester-ginkgo@latest
go install sigs.k8s.io/provider-aws-test-infra/kubetest2-ec2@latest
export PATH="$PATH:$HOME/go/bin"
```

## Usage

```bash
./scripts/run-conformance.sh --ami ami-0123456789abcdef0 --arch x86_64
```

Pick the Kubernetes version (must match the variant under test) and install the
tooling first:

```bash
./scripts/run-conformance.sh \
  --ami ami-0123456789abcdef0 \
  --arch aarch64 \
  --kubernetes-version 1.34 \
  --install
```

## What It Does

The script runs (with derived `INSTANCE_TYPE` and `MARKER`):

```bash
kubetest2 eksapi \
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
```

`--up --down` means the cluster is created before the run and destroyed after,
so no manual cleanup is needed even on failure.

## Validation

- [ ] kubetest2 reports the cluster came up and `--nodes` nodes joined.
- [ ] The ginkgo suite finishes with `SUCCESS!` and a `0` exit code.
- [ ] The cluster is torn down (kubetest2 logs the `--down` phase).

## Common Issues

**`kubetest2: command not found`** — run with `--install`, or `go install` the
three binaries above and add `$HOME/go/bin` to `PATH`.

**Nodes never join** — usually a bad AMI or user-data. kubetest2 leaves the
CloudFormation stack briefly on failure; inspect node logs via the
`ssm-executor` skill before the `--down` phase cleans up.

**Wrong test-package version** — the marker must match the cluster version.
The script derives it from `--kubernetes-version`; pass the version that matches
the AMI's variant (a `1.35` AMI needs `latest-1.35.txt`).

**Capacity errors for the instance type** — `m5.xlarge`/`m6g.xlarge` in another
AZ; retry, or the AWS account/region is out of capacity.

## Supporting Files

| Script               | Purpose                                                       |
| -------------------- | ------------------------------------------------------------- |
| `run-conformance.sh` | Derives instance type + marker from arch/version and runs kubetest2 eksapi `--up --down`. |

## Reference

- [kubetest2](https://github.com/kubernetes-sigs/kubetest2)
- [provider-aws-test-infra (kubetest2-ec2 / eksapi)](https://github.com/kubernetes-sigs/provider-aws-test-infra)
