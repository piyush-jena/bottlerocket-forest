#!/usr/bin/env bash
# Extract package metadata (version, url, go_major, gitrev) via rpmspec in the SDK container.
#
# Usage:
#   ./extract-metadata.sh <sdk-image> <default-go-major> <packages-dir> <package-name>
#
# Outputs a single line of tab-separated values:
#   version\turl\tgo_major\tgitrev
set -euo pipefail

SDK_IMAGE="$1"
DEFAULT_GO_MAJOR="$2"
PACKAGES_DIR="$3"
PKG="$4"

docker run --rm \
  -v "$(cd "$PACKAGES_DIR" && pwd):/packages:ro" \
  "$SDK_IMAGE" bash -c "
    cp /usr/lib/rpm/platform/x86_64-bottlerocket/macros ~/.rpmmacros
    spec='/packages/${PKG}/${PKG}.spec'

    version=\$(rpmspec --query --queryformat='%{version}\n' \"\$spec\" 2>/dev/null | head -1)
    url=\$(rpmspec --query --queryformat='%{url}\n' \"\$spec\" 2>/dev/null | head -1)

    expanded=\$(rpmspec -P \"\$spec\" 2>/dev/null)
    go_major=\$(echo \"\$expanded\" | grep -oP 'GO_MAJOR=\"\K[^\"]+' | head -1)
    go_major=\${go_major:-${DEFAULT_GO_MAJOR}}

    gitrev=\$(echo \"\$expanded\" | grep '^Source0:' | grep -oE '[0-9a-f]{40}' | head -1)
    if [[ -z \"\$gitrev\" ]]; then
      gitrev=\$(grep 'gitrev' \"\$spec\" | grep -oE '[0-9a-f]{40}' | head -1)
    fi

    printf '%s\t%s\t%s\t%s\n' \"\$version\" \"\$url\" \"\$go_major\" \"\$gitrev\"
  "
