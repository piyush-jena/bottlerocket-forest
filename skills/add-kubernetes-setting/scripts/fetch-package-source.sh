#!/usr/bin/env bash
# Fetch and unpack the exact upstream source tarball a core-kit package builds from.
#
# Usage: fetch-package-source.sh PACKAGE [PACKAGE...]
#   PACKAGE is a directory under core-kit packages/, e.g. kubernetes-1.35 or containerd-2.2.
#   With no PACKAGE, fetches every kubernetes-1.* package.
#
# Env:
#   CORE_KIT      core-kit checkout (default: ./kits/bottlerocket-core-kit)
#   BR_SRC_CACHE  cache root (default: ~/.cache/br-package-src)
#   BR_SRC_VENDOR set to 1 to keep vendor/ (needed to compile from the source; separate cache entry)
#
# Prints one line per package: "<package> <version> <source-root>".
# The tarball is verified against the sha512 in the package's Cargo.toml.
# This script only reads the sources. kubelet-validate.sh compiles kubelet's config code from a
# vendor copy, inside the Bottlerocket SDK container with no network access.
set -euo pipefail

core_kit=${CORE_KIT:-./kits/bottlerocket-core-kit}
cache=${BR_SRC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/br-package-src}

[ -d "$core_kit/packages" ] || { echo "core-kit not found at '$core_kit' (set CORE_KIT)" >&2; exit 1; }

if [ $# -eq 0 ]; then
  mapfile -t default_packages < <(find "$core_kit/packages" -mindepth 1 -maxdepth 1 -type d -name 'kubernetes-1.*' -printf '%f\n' | sort -V)
  set -- "${default_packages[@]}"
fi

# Print the value of KEY from the first [[...external-files]] table in a Cargo.toml.
external_file_field() {
  awk -F'"' -v key="$2" '
    /^\[\[package\.metadata\.build-package\.external-files\]\]/ { inside = 1; next }
    /^\[/ { inside = 0 }
    inside && $0 ~ "^" key " *=" { print $2; exit }
  ' "$1"
}

for pkg in "$@"; do
  manifest=$core_kit/packages/$pkg/Cargo.toml
  [ -f "$manifest" ] || { echo "no such package: $manifest" >&2; exit 1; }
  url=$(external_file_field "$manifest" url)
  sha=$(external_file_field "$manifest" sha512)
  if [ -z "$url" ] || [ -z "$sha" ]; then
    echo "$pkg: no external source in $manifest" >&2
    exit 1
  fi
  version=$(grep -m1 -oP '^%global gover \K\S+' "$core_kit/packages/$pkg/$pkg.spec" || echo unknown)

  suffix=""
  [ "${BR_SRC_VENDOR:-0}" = 1 ] && suffix=-vendor
  dest=$cache/$pkg-$version-${sha:0:12}$suffix
  if [ ! -f "$dest/.complete" ]; then
    rm -rf "$dest"
    mkdir -p "$dest/download" "$dest/src"
    curl -fsSL --retry 3 -o "$dest/download/source.tar.gz" "$url"
    echo "$sha  $dest/download/source.tar.gz" | sha512sum -c --quiet - \
      || { echo "$pkg: sha512 mismatch for $url" >&2; rm -rf "$dest"; exit 1; }
    # vendor/ is large and not needed to read kubelet or containerd behavior.
    excludes=(--exclude='*/vendor/*' --exclude='vendor/*')
    [ -n "$suffix" ] && excludes=()
    tar -xzf "$dest/download/source.tar.gz" -C "$dest/src" \
      --no-same-owner --no-same-permissions "${excludes[@]}"
    rm -f "$dest/download/source.tar.gz"
    printf 'package=%s\nversion=%s\nurl=%s\n' "$pkg" "$version" "$url" > "$dest/META"
    touch "$dest/.complete"
  fi

  # The source root is the shallowest directory holding go.mod.
  root=$(find "$dest/src" -maxdepth 2 -name go.mod -printf '%h\n' | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2-)
  echo "$pkg $version ${root:-$dest/src}"
done
