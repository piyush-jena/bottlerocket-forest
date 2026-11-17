#!/usr/bin/env bash
# rustc-cov-wrapper.sh - RUSTC_WRAPPER that adds LLVM source-based coverage to the crates named
# in COV_CRATES (space-separated rustc crate names, `-` written as `_`) and to no others.
set -euo pipefail
rustc="$1"; shift
crate="" prev=""
for a in "$@"; do
  [[ "$prev" == "--crate-name" ]] && crate="$a"
  prev="$a"
done
if [[ -n "$crate" && " ${COV_CRATES:?COV_CRATES is not set} " == *" $crate "* ]]; then
  exec "$rustc" "$@" -C instrument-coverage
fi
exec "$rustc" "$@"
