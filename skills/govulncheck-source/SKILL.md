---
name: govulncheck-source
description: Run govulncheck against Go packages in bottlerocket-core-kit using the bottlerocket-sdk container
---

# Skill: Govulncheck Source

**Keywords:** govulncheck, go, vulnerability, security, scanning, core-kit, packages, sdk, docker

## Purpose

Scan Go packages in `bottlerocket-core-kit` for known vulnerabilities using `govulncheck` in source mode.
The scan runs inside the `bottlerocket-sdk` Docker container, using the correct Go version for each package.

## When to Use

- Auditing Go dependencies for known vulnerabilities before a release
- Checking if a package update introduces or resolves vulnerabilities
- Periodic security review of Go packages in core-kit

## Prerequisites

Before starting, verify:
- Docker is installed and running (`docker info`)
- Python 3.11+ is available (`python3 --version`) — needed for `tomllib`
- You are working from within a grove directory
- `kits/bottlerocket-core-kit` exists in the grove

## Input

The user provides:
- **Package name(s)** to scan (e.g., `runc`, `containerd-2.1`)
- **Kit name** — defaults to `bottlerocket-core-kit`

## Procedure

### 1. Pull the SDK image

```bash
python3 skills/govulncheck-source/scripts/pull-sdk.py kits/<kit-name>/Twoliter.toml
```

This outputs two lines to stdout:
1. The fully-qualified SDK image (e.g., `public.ecr.aws/bottlerocket/bottlerocket-sdk:v0.70.0`)
2. The default Go version in the SDK (e.g., `1.24`)

Capture both values — they are needed by subsequent steps.

### 2. Extract package metadata

For each package, run:

```bash
bash skills/govulncheck-source/scripts/extract-metadata.sh \
  <sdk-image> <default-go-major> kits/<kit-name>/packages <package-name>
```

This outputs a single tab-separated line: `version\turl\tgo_major\tgitrev`

- `version` — upstream version (e.g., `1.2.8`)
- `url` — upstream repository URL (e.g., `https://github.com/opencontainers/runc`)
- `go_major` — Go toolchain version to use (e.g., `1.24`)
- `gitrev` — commit hash if the package is pinned to a specific commit (may be empty)

### 3. Determine source type and obtain source

Read `kits/<kit-name>/packages/<package-name>/Cargo.toml` to determine the source type:

**Upstream packages** (have `[[package.metadata.build-package.external-files]]`):
Clone the upstream repo at the correct ref.
Try tags in this order:
1. `v<version>` (most common)
2. `<version>` (bare)
3. For moby/docker-engine: `docker-v<version>`
4. Fall back to `gitrev` commit hash if tags fail

```bash
git clone --depth 1 --branch v<version> <url> /tmp/govulncheck-<package>
```

**Internal packages** (have `source-groups = ["<group>"]`):
Source lives in `kits/<kit-name>/sources/<group>/`.
No cloning needed — use the local path directly.

### 4. Run govulncheck

```bash
bash skills/govulncheck-source/scripts/run-govulncheck.sh \
  <sdk-image> <go-major> <source-dir>
```

Save the output to `govulncheck-results/<package>/govulncheck.txt`.

Count vulnerabilities by looking for `Vulnerability #` lines in the output.

### 5. Clean up and report

Remove any cloned source directories.

Present results as a summary table:

| Package | Version | Go | Vulns | Status |
|---------|---------|-----|-------|--------|
| runc    | 1.2.8   | 1.24 | 0    | clean  |

## Output Structure

```
govulncheck-results/
├── <package>/
│   └── govulncheck.txt
└── ...
```

## Common Issues

**Docker not running:**
Start Docker with `sudo systemctl start docker`

**SDK image pull fails (ECR auth):**
```bash
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
```

**govulncheck reports "no go.mod":**
Some upstream repos have `go.mod` in a subdirectory.
The `run-govulncheck.sh` script searches up to 3 levels deep automatically.

**Tag not found during clone:**
Try the next tag variant, then fall back to full clone with `gitrev` checkout.
