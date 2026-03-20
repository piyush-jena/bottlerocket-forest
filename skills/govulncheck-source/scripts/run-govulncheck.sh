#!/usr/bin/env bash
# Run govulncheck inside the SDK container against a local source directory.
#
# Usage:
#   ./run-govulncheck.sh <sdk-image> <go-major> <source-dir>
#
# Outputs govulncheck results to stdout.
# Exit code 3 = vulnerabilities found, 0 = clean, other = error.
set -euo pipefail

SDK_IMAGE="$1"
GO_MAJOR="$2"
SRC_DIR="$3"

docker run --rm \
  -v "$(cd "$SRC_DIR" && pwd):/src:ro" \
  "$SDK_IMAGE" bash -c "
    export GOBIN=/tmp/bin
    /usr/libexec/go-${GO_MAJOR}/bin/go install golang.org/x/vuln/cmd/govulncheck@latest 2>/dev/null

    export PATH=/usr/libexec/go-${GO_MAJOR}/bin:/tmp/bin:\$PATH

    gomod_dir=/src
    if [[ ! -f /src/go.mod ]]; then
      found=\$(find /src -maxdepth 3 -name go.mod -print -quit 2>/dev/null)
      if [[ -n \"\$found\" ]]; then
        gomod_dir=\$(dirname \"\$found\")
      else
        echo 'ERROR: no go.mod found' >&2
        exit 1
      fi
    fi

    govulncheck -C \"\$gomod_dir\" -show verbose ./... 2>&1
  "
