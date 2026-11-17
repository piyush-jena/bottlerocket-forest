#!/usr/bin/env bash
# Render core-kit templates with schnauzer itself, from settings files, without booting a node.
#
# Usage:
#   render-template.sh [--settings FILE]... --out DIR TEMPLATE...
#   render-template.sh [--settings FILE]... --kubelet-config [MINOR...]
#
#   --settings FILE   user-data TOML ([settings.kubernetes] ...) or API-style JSON ({"settings": ...}).
#                     Deep-merged, in order, over references/base-settings-aws-k8s.json, which holds
#                     the settings of a real aws-k8s node (sanitized).
#   --out DIR         where rendered files go (default: a new temp dir, printed at the end)
#   --kubelet-config  render packages/kubernetes-1.X/kubelet-config for each MINOR (default: all),
#                     then run kubelet-config-lint.py on every rendered file.
#
# Settings go through KubernetesSettingsV1 first, like the API, so values the API would reject fail
# here (exit 3). A strict-mode render error exits 1. The tool is built once per core-kit checkout
# against that checkout's schnauzer and settings-models pins (including a local settings-sdk override).
#
# Env: CORE_KIT (default ./kits/bottlerocket-core-kit), BR_SRC_CACHE (build cache root)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
core_kit=$(cd "${CORE_KIT:-./kits/bottlerocket-core-kit}" && pwd)
cache=${BR_SRC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/br-package-src}

settings=() out="" kubelet_config=false templates=()
while [ $# -gt 0 ]; do
  case "$1" in
    --settings) settings+=("$2"); shift 2 ;;
    --out) out=$2; shift 2 ;;
    --kubelet-config) kubelet_config=true; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) templates+=("$1"); shift ;;
  esac
done

# Build the renderer against this core-kit's schnauzer and settings-models dependency.
models_dep=$(awk '/^\[workspace\.dependencies\.bottlerocket-settings-models\]/{f=1; next} /^\[/{f=0} f && NF' \
  "$core_kit/sources/Cargo.toml" | paste -sd, - | sed 's/^/{ /; s/$/ }/')
key=$(printf '%s\n%s\n' "$core_kit" "$models_dep" | cat - "$HERE/render-template/main.rs" | sha256sum | cut -c1-12)
tool=$cache/render-template/$key
if [ ! -f "$tool/Cargo.toml" ]; then
  mkdir -p "$tool"
  cp "$HERE/render-template/main.rs" "$tool/main.rs"
  cp "$core_kit/sources/Cargo.lock" "$tool/Cargo.lock"
  cat > "$tool/Cargo.toml" <<EOF
[package]
name = "br-render-template"
version = "0.1.0"
edition = "2021"
publish = false

[[bin]]
name = "br-render-template"
path = "main.rs"

[dependencies]
bottlerocket-settings-models = $models_dep
schnauzer = { path = "$core_kit/sources/api/schnauzer" }
serde_json = "1"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }

[workspace]
EOF
  echo "building renderer in $tool (once per core-kit checkout and settings-models pin)" >&2
fi
# Always build: it is a no-op when nothing changed, and picks up edits to schnauzer's helpers.
cargo build -q --release --manifest-path "$tool/Cargo.toml" >&2

# Merge base settings with every --settings file (TOML user data or JSON).
merged=$(mktemp --suffix=.json)
python3 -I - "$HERE/../references/base-settings-aws-k8s.json" "${settings[@]}" > "$merged" <<'EOF'
import json, sys, tomllib
def merge(a, b):
    for k, v in b.items():
        a[k] = merge(a[k], v) if isinstance(v, dict) and isinstance(a.get(k), dict) else v
    return a
doc = json.load(open(sys.argv[1]))
for path in sys.argv[2:]:
    with open(path, "rb") as f:
        merge(doc, tomllib.load(f) if path.endswith(".toml") else json.load(f))
print(json.dumps(doc))
EOF

if $kubelet_config; then
  minors=("${templates[@]}")
  templates=()
  if [ ${#minors[@]} -eq 0 ]; then
    for d in "$core_kit"/packages/kubernetes-1.*; do minors+=("${d##*kubernetes-}"); done
  fi
  for m in "${minors[@]}"; do templates+=("$core_kit/packages/kubernetes-$m/kubelet-config"); done
fi
if [ ${#templates[@]} -eq 0 ]; then
  echo "no templates given" >&2
  exit 2
fi
for t in "${templates[@]}"; do
  if ! $kubelet_config && [[ $t =~ ^1\.[0-9]+$ ]]; then
    echo "'$t' looks like a Kubernetes minor: add --kubelet-config to render that version" >&2
    exit 2
  fi
done
out=${out:-$(mktemp -d)}

status=0
"$tool/target/release/br-render-template" "$merged" "$out" "${templates[@]}" || status=$?
rm -f "$merged"
[ $status -eq 0 ] || exit $status

if $kubelet_config; then
  for m in "${minors[@]}"; do
    CORE_KIT=$core_kit python3 -I "$HERE/kubelet-config-lint.py" "$m" \
      --template "$out/kubernetes-${m}__kubelet-config" || status=1
  done
fi
echo "rendered into $out" >&2
exit $status
