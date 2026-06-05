---
name: test-third-party-package
description: Decide how to test a third-party Bottlerocket package after updating it, and drive the right test. Maps each package to a test Type (0-6) and the runner skill that validates it. Pairs with the update-package skill.
---

# Skill: Test Third-Party Package

After updating a third-party package (see the `update-package` skill), use this
skill to pick and run the correct validation. Every supported package maps to a
**Type (0-6)**; each Type has a defined test and runner skill.

## When to Use

- Immediately after `update-package` rebuilds a package, to verify the change.
- To decide, for a given package, what "tested" means and which skill to invoke.

## Input

- One or more **package names** that were updated (the same names you gave
  `update-package`, e.g. `runc`, `kubernetes-1.35`, `keyutils`).
- The **AMI(s)** built with the updated package, and the **arch** (`x86_64` /
  `aarch64`).

## Step 1 — Classify the package(s)

```bash
./scripts/classify-package.sh runc kubernetes-1.35 keyutils
```

Prints the Type and the exact runner/command for each package. Then run the
indicated skill(s) below.

## Logging results for review

Every runner writes its output to a shared results directory (via `tee`, so you
still see progress live). Set `RESULTS_DIR` to collect a whole run in one place:

```bash
export RESULTS_DIR=~/pkg-test-results/runc-$(date +%Y%m%d)
```

Default is `/tmp/pkg-test-results`. Each script writes
`$RESULTS_DIR/<test>-<timestamp>.log` and prints the path it logged to.

For Type 5/6 checks that go through the `ssm-executor` skill, wrap the command
with `log-cmd.sh` so its output lands in the same place:

```bash
./scripts/log-cmd.sh keyutils \
  ../ssm-executor/scripts/sheltie-command.sh INSTANCE_ID REGION "keyctl --version"
```

After a run, review everything with `ls -t "$RESULTS_DIR"` / `cat`.

## Type → Test matrix

| Type | Packages | Test | Runner skill |
| ---- | -------- | ---- | ------------ |
| 0 | libacl, libattr, libaudit, libbpf, libcap, libxcrypt, libz, libzstd, dbus-broker, binutils, libgcc, libstd-rust, libcrypto, libjansson, libjson-c, libnl, libpopt, libudev, libdrm, cni, cni-plugins | None required (libraries validated via their dependents) | — |
| 1 | runc, pigz, containerd-1.7, containerd-2.1, containerd-2.2 | A pod schedules, pulls, and runs | `simple-pod-runner` |
| 2 | kubernetes-1.30 … kubernetes-1.36 | Kubernetes conformance, **once per cluster type / k8s minor** | `conformance-runner` |
| 3 | amazon-ssm-agent, docker-cli-*, docker-engine-*, docker-init, ecs-agent, ecs-gpu-init | MACIS suite (ECS variant) | `macis-runner` (Amazon-internal, best effort) |
| 4 | soci-snapshotter | Pod pulls through the soci snapshotter | `soci-snapshotter-tester` |
| 5 | ecr-credential-helper | Image verifier (notation) pull path | `ssm-executor` (see Type 5 below) |
| 6 | host-tier packages (see table) | Targeted host one-liner over sheltie | `ssm-executor` |

`classify-package.sh` is the authoritative source for the full package → Type mapping (it also
marks packages that are intentionally **not tested** by this skill). The table above lists
representative members per Type.

NVIDIA/GPU packages (`nvidia-k8s-device-plugin`, `nvidia-container-toolkit`,
`libnvidia-container`) are validated with `nvidia-smoke-test-runner` on a GPU node.

containerd is version-pinned to a Kubernetes stream: test `containerd-1.7` with a pod on a
Kubernetes **1.30/1.31/1.32** variant, `containerd-2.1` on a **1.33/1.34/1.35** variant, and
`containerd-2.2` on a **1.36** variant.

Always also confirm the basics first:

- **Node boots:** `launch-bottlerocket-ec2` (standalone) — the AMI comes up.
- **Node joins cluster:** `eks-smoke-test` — for K8s variants, nodes register. This is also the
  test for `aws-iam-authenticator` (the node-join auth path).

## Test node provisioning

Conformance (Type 2) instance types are chosen by `conformance-runner`
(`m5.xlarge` x86 / `m6g.xlarge` aarch64).

For Type 1/4/6 host and pod tests, launch a **general test node** with local
instance storage so ephemeral-storage tests work:

| arch | test-node instance type |
| ---- | ----------------------- |
| x86_64 | `i7ie.12xlarge` |
| aarch64 | `i8g.12xlarge` |

These have NVMe instance store, which `apiclient ephemeral-storage init` (Type 6:
xfsprogs / e2fsprogs) requires. A node **without** instance store cannot run the
ephemeral-storage tests without attaching extra volumes.

## Type 2 — conformance (one per cluster type)

`kubernetes-1.NN` maps 1:1 to a Kubernetes minor. Run conformance for each
updated version:

```bash
# in the conformance-runner skill
./scripts/run-conformance.sh --ami <ami> --arch x86_64 --kubernetes-version 1.35 --install
```

## Type 5 — ecr-credential-helper (image verifier)

On the node (via the `ssm-executor` skill, in a `sheltie` shell):

```bash
apiclient apply <<EOF
[settings.image-verifier-plugins]
enabled = true
EOF

cat /etc/containerd/image-verifiers/notation/trustpolicy.json   # verifier config present
ctr i pull docker.io/library/hello-world:latest                 # pull goes through the verifier
```

Pass = the pull succeeds with the verifier enabled and the trust policy present.

## Type 6 — host one-liners over sheltie

Run the per-package command from `references/type6-commands.md` via the
`ssm-executor` skill:

```bash
# wrap the ssm-executor call so output is saved to $RESULTS_DIR
./scripts/log-cmd.sh keyutils \
  ../ssm-executor/scripts/sheltie-command.sh INSTANCE_ID REGION "keyctl --version"
```

Notes:
- **Enable the admin container first.** `sheltie` needs
  `host-containers.admin.enabled=true`; if it is `false` every command fails
  with `ctr: container "admin" ... not found`. Set it via the control container:
  `apiclient set host-containers.admin.enabled=true`.
- `sheltie -- <cmd>` execs a **single host binary** (no pipes/redirects/builtins).
  Pipe the output in the control-container shell, and rewrite `cat x | grep` as
  `grep PATTERN x`.
- A few tools live only in the **admin container**, not the host root — run those
  with `apiclient exec admin <cmd>` (no `sheltie --`). On the validated build that
  includes `bash` and `ping`; `hwloc-ls`/`strace`/`cryptsetup` were absent
  entirely. Availability varies by variant — see `references/type6-commands.md`.
- The coreutils/grep tests reference a sysroot path that is **arch-specific**:
  `/x86_64-bottlerocket-linux-gnu/...` vs `/aarch64-bottlerocket-linux-gnu/...`.
- Device commands are instance-dependent: `nvme amzn stats /dev/nvme2n1` needs a
  device that exists (run `nvme list` first; m5 has only EBS `nvme0n1`/`nvme1n1`).
- `echo c > /proc/sysrq-trigger` (kexec-tools/makedumpfile/libelf) **crashes the
  node on purpose** to test kdump — only run it on a throwaway instance.
- ephemeral-storage tests (xfsprogs/e2fsprogs/…) require a node with instance
  store (see test-node instance types above).
- cryptsetup tests (libdevmapper/libcryptsetup) require an extra attached EBS
  volume.

## Validation

- [ ] `classify-package.sh` returned a Type for every updated package
      (no `UNKNOWN`).
- [ ] The node boots (`launch-bottlerocket-ec2`) and, for K8s variants, joins
      (`eks-smoke-test`).
- [ ] The Type-specific test passed for each package.

## Supporting Files

| File | Purpose |
| ---- | ------- |
| `scripts/classify-package.sh` | Map package name(s) → Type + runner/command. |
| `references/type6-commands.md` | Full per-package Type 6 sheltie command list. |

## Reference

- `update-package` — the skill that produces the package change this validates.
- `conformance-runner`, `simple-pod-runner`, `nvidia-smoke-test-runner`,
  `soci-snapshotter-tester`, `macis-runner`, `ssm-executor` — the runners.
