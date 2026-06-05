#!/usr/bin/env bash
# List all Go packages in a kit's packages directory.
#
# Usage:
#   ./list-go-packages.sh <packages-dir>
#
# A package is Go if its spec uses any of the SDK's Go build macros, which all
# share the substring "cross_go" (set_cross_go_env, set_cross_go_flags[_static],
# cross_go_setup, cross_go_configure). Note: cross_go_configure internally calls
# set_cross_go_flags, so grepping for "set_cross_go_flags" alone misses packages.
set -euo pipefail

PACKAGES_DIR="$1"

grep -rl 'cross_go' --include='*.spec' "$PACKAGES_DIR" \
  | xargs -n1 dirname | xargs -n1 basename | sort -u
