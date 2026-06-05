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
- **Package name(s)** to scan (e.g., `runc`, `containerd-2.1`) — if omitted, scan **all** Go packages (see step 0)
- **Kit name** — defaults to `bottlerocket-core-kit`

## Procedure

### 0. Discover Go packages (when no package is specified)

```bash
bash skills/govulncheck-source/scripts/list-go-packages.sh kits/<kit-name>/packages
```

A package is Go if its spec uses any SDK Go build macro; these all share the substring
`cross_go`. Grepping for `%set_cross_go_flags` alone is **not** sufficient — packages that
use `%cross_go_configure` (which internally calls `%set_cross_go_flags`) would be missed.

### 1. Pull the SDK image

```bash
python3 skills/govulncheck-source/scripts/pull-sdk.py kits/<kit-name>/Twoliter.toml
```

This outputs two lines to stdout:
1. The fully-qualified SDK image (e.g., `public.ecr.aws/bottlerocket/bottlerocket-sdk:v0.70.0`)
2. The default Go version in the SDK (e.g., `1.25`)

The SDK ships two Go versions; the **default is the lower one**.
Use this default for govulncheck unless the package's spec file pins a version (see step 2).

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
- `go_major` — Go toolchain version to use; this is the spec file's `GO_MAJOR` if it pins one, otherwise the SDK default (lower) version from step 1
- `gitrev` — commit hash if the package is pinned to a specific commit (informational)

### 3. Determine source type and obtain source

Read `kits/<kit-name>/packages/<package-name>/Cargo.toml` to determine the source type:

**Upstream packages** (have `[[package.metadata.build-package.external-files]]`):
Download the source archive (the `url` of the first `external-files` entry that points to a
tarball/zip — skip `.asc` signatures and `.patch` files) and extract it to
`/tmp/govulncheck-<package>`. Do **not** `git clone`; the published archive is the exact
source that ships in the package, whereas a clone may drift from it.

```bash
bash skills/govulncheck-source/scripts/get-source.sh \
  kits/<kit-name>/packages/<package-name>/Cargo.toml <package-name>
```

This prints the extracted source directory (the one containing `go.mod`) on stdout — pass it
to step 4. The script handles single top-level archive dirs and the moby/docker
`vendor.mod` layout automatically.

**Internal packages** (have `source-groups = ["<group>"]`):
Source lives in `kits/<kit-name>/sources/<group>/`.
No download needed — use the local path directly.

### 4. Run govulncheck

`<source-dir>` is the directory printed by `get-source.sh` (upstream) or the
`sources/<group>/` path (internal).

```bash
bash skills/govulncheck-source/scripts/run-govulncheck.sh \
  <sdk-image> <go-major> <source-dir>
```

Save the output to `govulncheck-results/<package>/govulncheck.txt`.

Count vulnerabilities by looking for `Vulnerability #` lines in the output.

### 5. Clean up and report

Remove any extracted source directories (`/tmp/govulncheck-<package>`).

Present results as a summary table:

| Package | Version | Go | Vulns | Status |
|---------|---------|-----|-------|--------|
| runc    | 1.2.8   | 1.25 | 0    | clean  |

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
Some upstream archives have `go.mod` in a subdirectory.
The `run-govulncheck.sh` script searches up to 3 levels deep automatically.
moby/docker ship `vendor.mod` instead of `go.mod`; `get-source.sh` copies it over.

**Download fails:**
Verify the `external-files` URL in `Cargo.toml` is reachable.
The archive URL is the upstream source that ships in the package — use it as-is rather than cloning.
