---
name: update-freshness-binary
description: Git pull BottlerocketAICapabilities and build the freshness-rust binary. Use when you need to update or build the freshness tool before running a scan.
always: false
---

# Update Freshness Binary

Pulls latest BottlerocketAICapabilities and builds the freshness-rust tool.

## Prerequisites

- Git access to BottlerocketAICapabilities
- Rust toolchain (cargo)

## Workflow

### Step 1: Locate the repository

Check these locations in order:
1. `$MESHCLAW_PROJECT_DIR/../BottlerocketAICapabilities/` (if MESHCLAW_PROJECT_DIR is set)
2. `~/workplace/BottlerocketAICapabilities/src/BottlerocketAICapabilities/`

If neither exists, clone or prompt user for location.

### Step 2: Update the repository

```bash
cd <repo-path>
git pull
```

### Step 3: Build the binary

```bash
cd <repo-path>/tools/freshness-rust
cargo build --release
```

The binary will be at `<repo-path>/tools/freshness-rust/target/release/freshness_tool`.

### Step 4: Verify build

Confirm the binary exists and is executable:
```bash
ls -la <repo-path>/tools/freshness-rust/target/release/freshness_tool
```

## Skip Conditions

If `~/.cargo/bin/freshness_tool` exists and is recent (modified within last 7 days), you may skip the build and use the installed binary instead.

## Error Handling

- Repository not found → prompt user for location
- Git pull fails → report error, check network/auth
- Cargo build fails → report error with build output
