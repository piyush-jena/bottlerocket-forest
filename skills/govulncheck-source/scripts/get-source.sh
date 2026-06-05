#!/usr/bin/env bash
# Download an upstream source archive from a package's Cargo.toml and extract it.
#
# Usage:
#   ./get-source.sh <cargo-toml> <package-name>
#
# Picks the first source archive URL in [[package.metadata.build-package.external-files]],
# downloads it with wget, and extracts it to /tmp/govulncheck-<package>.
# Prints the extracted source directory (containing go.mod) on stdout.
set -euo pipefail

CARGO="$1"
PKG="$2"
DEST="/tmp/govulncheck-${PKG}"

url=$(python3 - "$CARGO" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
bp = d.get("package", {}).get("metadata", {}).get("build-package", {})
exts = (".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar.zst", ".zip")
for ef in bp.get("external-files", []):
    u = ef.get("url", "")
    if (ef.get("path") or u).endswith(exts):
        print(u)
        break
PY
)

if [[ -z "$url" ]]; then
  echo "ERROR: no source archive URL found in $CARGO" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
wget -q "$url" -O "$DEST/src.archive"
if [[ "$url" == *.zip ]]; then
  unzip -q "$DEST/src.archive" -d "$DEST"
else
  tar -xf "$DEST/src.archive" -C "$DEST"
fi
rm -f "$DEST/src.archive"

# Descend into a single top-level directory (typical for archives) so go.mod sits at the root.
shopt -s nullglob dotglob
entries=("$DEST"/*)
srcdir="$DEST"
if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
  srcdir="${entries[0]}"
fi

# docker/moby ship vendor.mod/vendor.sum instead of go.mod.
if [[ ! -f "$srcdir/go.mod" && -f "$srcdir/vendor.mod" ]]; then
  cp "$srcdir/vendor.mod" "$srcdir/go.mod"
  [[ -f "$srcdir/vendor.sum" ]] && cp "$srcdir/vendor.sum" "$srcdir/go.sum"
fi

echo "$srcdir"
