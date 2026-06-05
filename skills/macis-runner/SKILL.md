---
name: macis-runner
description: Run MACIS tests against a Bottlerocket ECS-variant AMI via the Bottlerocket-release-scripts macis harness. Validates ECS-tier packages (Type 3). Requires Amazon-internal access.
---

# Skill: MACIS Runner

Runs the MACIS test suite against a Bottlerocket **ECS-variant** AMI to validate
Type 3 packages: `amazon-ssm-agent`, `docker-cli`, `docker-engine`, `ecs-agent`,
`ecs-gpu-init`.

> **Best-effort skill.** MACIS runs through Amazon-internal tooling
> (`isengard`, `ssh://git.amazon.com`, account `932817054917`). It **cannot be
> run from this development environment** — it must be run from a host with
> Midway/Isengard credentials and access to `git.amazon.com`. The commands below
> are the tested procedure to run there.

## When to Use

- After updating any Type 3 / ECS-tier package, against an `aws-ecs-*` AMI.

## Prerequisites

- Amazon-internal host with `isengard` CLI and Midway auth.
- SSH access to `ssh://git.amazon.com/pkg/Bottlerocket-release-scripts`.
- Isengard access to account `932817054917` (role `Administrator`).
- A published **ECS-variant** AMI ID.

## Procedure

### 1. Clone the release scripts (once)

```bash
git clone ssh://git.amazon.com/pkg/Bottlerocket-release-scripts
```

### 2. Start the MACIS tests

```bash
AMI_ID="<ami_id of the ecs variant>"
isengard 932817054917 Administrator exec -- \
  ./Bottlerocket-release-scripts/bin/macis-start-tests.sh \
  --instance-type "m5.8xlarge" \
  --ami-id "${AMI_ID}"
```

This prints a **task ARN** — capture it.

### 3. Fetch the results

```bash
TASK_ARN="<task_arn from the previous command>"
isengard 932817054917 Administrator exec -- \
  ./macis-get-tests-results.sh \
  --task-arn "${TASK_ARN}"
```

`scripts/run-macis.sh` wraps steps 2–3: it starts the tests, parses the task
ARN, **waits `--wait` seconds (default 600 = 10 min) for results, then fetches
them automatically**. Pass `--task-arn <arn>` to skip starting and only fetch.
All output is logged to `$RESULTS_DIR/macis-<timestamp>.log` (default
`/tmp/pkg-test-results`). It fails fast with a clear message if
`isengard`/`git` are unavailable, which is expected here.

```bash
./scripts/run-macis.sh --ami-id "$AMI_ID"                 # start, wait 10 min, fetch
./scripts/run-macis.sh --ami-id "$AMI_ID" --wait 900      # wait 15 min instead
./scripts/run-macis.sh --task-arn "$TASK_ARN"             # fetch results only
```

## Validation

- [ ] `macis-start-tests.sh` returns a task ARN.
- [ ] `macis-get-tests-results.sh` reports all MACIS tests passed for the ARN.

## Common Issues

**`isengard: command not found` / `git.amazon.com` unreachable** — you are not on
an Amazon-internal host. This skill cannot run here; run it from an environment
with Midway/Isengard.

**Wrong variant** — MACIS targets the ECS variant. Pass an `aws-ecs-*` AMI, not a
`aws-k8s-*` one.

## Supporting Files

| Script         | Purpose                                                       |
| -------------- | ------------------------------------------------------------- |
| `run-macis.sh` | Best-effort wrapper around `macis-start-tests.sh` / `macis-get-tests-results.sh`. |
