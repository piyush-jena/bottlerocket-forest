#!/usr/bin/env bash
# Check rendered kubelet config files with each kubelet version's own startup code, offline.
#
# Usage: kubelet-validate.sh RENDERED_DIR [MINOR...]
#   RENDERED_DIR  output of render-template.sh --kubelet-config or counterfactual.py
#                 (files named kubernetes-1.X__kubelet-config)
#   MINOR         versions to check, like 1.35 (default: every rendered file found)
#
# For each version it compiles a small program against the exact Kubernetes source core-kit builds
# (fetched with vendor/), and runs what kubelet runs on --config: the strict decode it silently
# falls back from, the config loader, feature gates from the file, ValidateKubeletConfiguration,
# the reserved-resource, eviction-threshold and qosReserved parsing done later in startup, and the
# CPU and topology manager policy option checks. Output per file:
#   OK                    kubelet would start with this config
#   IGNORED (...)         keys kubelet would drop with only a log warning (for example a field that
#                         does not exist in this version)
#   FATAL (...)           kubelet would exit, so the node never joins
# followed by kubelet's own log warnings, once each. Exit status 1 if any file is not OK.
#
# Not covered: command-line flags (kubelet-exec-start-conf), drop-in config dirs, and checks that
# need the host (cgroup v1 vs v2 is taken from the container host, which is cgroup v2; user
# namespace ID ranges; NUMA topology). Those need a node: see references/verification.md.
#
# Compilation and runs happen in the Bottlerocket SDK image with --network=none, with the source
# mounted read-only: the generated files are added with go build -overlay and kept, with the binary,
# under $BR_SRC_CACHE/kubelet-validate/. The first run per version compiles for about 30 seconds.
# Env: CORE_KIT, BR_SRC_CACHE, BR_SDK_IMAGE (default: the sdk in core-kit's Twoliter.toml)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
rendered=$(cd "${1:?usage: kubelet-validate.sh RENDERED_DIR [MINOR...]}" && pwd)
shift
core_kit=$(cd "${CORE_KIT:-./kits/bottlerocket-core-kit}" && pwd)
cache=${BR_SRC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/br-package-src}
sdk=${BR_SDK_IMAGE:-$(awk -F'"' '/^\[sdk\]/{f=1} f&&/^version/{v=$2} f&&/^vendor/{print "public.ecr.aws/bottlerocket/bottlerocket-sdk:v" v; exit}' "$core_kit/Twoliter.toml")}

minors=("$@")
if [ ${#minors[@]} -eq 0 ]; then
  for f in "$rendered"/kubernetes-1.*__kubelet-config; do
    m=${f##*/kubernetes-}
    minors+=("${m%%__*}")
  done
fi
for m in "${minors[@]}"; do
  [[ $m =~ ^1\.[0-9]+$ ]] || { echo "invalid version '$m': give minors like 1.35" >&2; exit 2; }
done

# Write the per-version Go sources for one source tree into a tool directory.
generate() {
  local src=$1 tool=$2 ctx="" ctximport="" logger=""
  # Call forms differ between versions; detect them from this version's source.
  if grep -q '^func loadConfigFile(ctx context.Context' "$src/cmd/kubelet/app/server.go"; then
    ctx="context.Background(), "
    ctximport='"context"'
  fi
  if grep -q '^func NewPolicyOptions(logger' "$src/pkg/kubelet/cm/topologymanager/policy_options.go"; then
    logger="klog.Background(), "
  fi
  {
    echo 'package app'
    echo
    echo 'import ('
    [ -n "$ctximport" ] && printf '\t%s\n' "$ctximport"
    printf '\tv1 "k8s.io/api/core/v1"\n'
    printf '\tkubeletconfiginternal "k8s.io/kubernetes/pkg/kubelet/apis/config"\n'
    echo ')'
    echo
    echo '// BRLoadConfigFile and BRParseResourceList expose unexported kubelet startup code to'
    echo '// br-kubelet-validate. Added through a go build overlay by kubelet-validate.sh.'
    echo 'func BRLoadConfigFile(name string) (*kubeletconfiginternal.KubeletConfiguration, error) {'
    printf '\treturn loadConfigFile(%sname)\n' "$ctx"
    echo '}'
    echo
    echo 'func BRParseResourceList(m map[string]string) (v1.ResourceList, error) {'
    printf '\treturn parseResourceList(m)\n'
    echo '}'
  } > "$tool/zz_br_validate_export.go"
  sed "s/@TOPOLOGY_LOGGER@/$logger/" "$HERE/kubelet-validate/main.go.in" > "$tool/main.go"
  printf '%s\n' '{"Replace": {' \
    '  "/src/cmd/kubelet/app/zz_br_validate_export.go": "/tool/zz_br_validate_export.go",' \
    '  "/src/cmd/br-kubelet-validate/main.go": "/tool/main.go"' \
    '}}' > "$tool/overlay.json"
}

mkdir -p "$cache/gocache"
status=0
for m in "${minors[@]}"; do
  line=$(CORE_KIT=$core_kit BR_SRC_VENDOR=1 "$HERE/fetch-package-source.sh" "kubernetes-$m")
  src=${line##* }
  tool=$cache/kubelet-validate/$(basename "$(dirname "$src")")
  bin=$tool/br-kubelet-validate
  if [ ! -x "$bin" ] || [ "$HERE/kubelet-validate/main.go.in" -nt "$bin" ] || [ "$0" -nt "$bin" ]; then
    mkdir -p "$tool"
    generate "$src" "$tool"
    echo "compiling kubelet $m config checks in $sdk (once per version)" >&2
    docker run --rm --network=none --user "$(id -u):$(id -g)" \
      -e HOME=/tmp -e GOCACHE=/gocache -e GOFLAGS=-mod=vendor -e GOTOOLCHAIN=local -e CGO_ENABLED=0 \
      -v "$src:/src:ro" -v "$tool:/tool" -v "$cache/gocache:/gocache" -w /src --entrypoint /bin/bash "$sdk" \
      -c 'go build -overlay /tool/overlay.json -o /tool/br-kubelet-validate ./cmd/br-kubelet-validate' >&2
  fi
  file=$rendered/kubernetes-${m}__kubelet-config
  if [ ! -f "$file" ]; then
    echo "missing $file" >&2
    status=1
    continue
  fi
  echo "== kubelet $m"
  log=$(mktemp)
  docker run --rm --network=none --user "$(id -u):$(id -g)" \
    -v "$tool:/tool:ro" -v "$rendered:/in:ro" --entrypoint /tool/br-kubelet-validate "$sdk" \
    "/in/${file##*/}" 2>"$log" | sed "s|/in/||" || status=1
  # kubelet's own warnings (for example GA gates that will be removed), once each.
  sed -E 's/^[IWE][0-9]{4} [0-9:.]+ +[0-9]+ [a-z_]+\.go:[0-9]+\] //' "$log" | sort -u | sed 's/^/  kubelet log: /'
  rm -f "$log"
done
exit $status
