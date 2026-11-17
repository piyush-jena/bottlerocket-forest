#!/usr/bin/env bash
# Collect evidence that a setting reached a Bottlerocket node and that the kubelet (or containerd)
# actually applied it. Prints a markdown evidence block suitable for a PR "Testing done" section.
#
# Usage:
#   verify-node.sh --instance ID --region REGION [--setting KEY] [--kubelet PATH] [--expect VALUE]
#                  [--flag NAME] [--file FILE --file-path PATH]
#
#   --setting KEY    settings.kubernetes.KEY to read back from the API (e.g. max-container-restart-period)
#   --kubelet PATH   dotted KubeletConfiguration path (e.g. crashLoopBackOff.maxContainerRestartPeriod)
#                    checked in the rendered /etc/kubernetes/kubelet/config and in the live /configz
#   --expect VALUE   value /configz must report, as the kubelet prints it (durations are normalized:
#                    60s is reported as 1m0s); "absent" requires the path to be missing or empty
#   --flag NAME      kubelet command-line flag to read from the running process (e.g. container-runtime-endpoint)
#   --file FILE      another rendered file to inspect (e.g. /etc/containerd/config.toml)
#   --file-path P    dotted path inside FILE; quote keys containing dots: plugins."io.containerd.grpc.v1.cri".x
#
# Needs: aws, jq, kubectl (current context = the node's cluster), python3 with PyYAML.
# Exit status: 0 when every requested check passes, 1 otherwise.
set -euo pipefail

SSM=$(cd "$(dirname "$0")/../../ssm-executor/scripts" && pwd)
instance="" region="" setting="" kpath="" expect="" flag="" file="" file_path=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) instance=$2; shift 2 ;;
    --region) region=$2; shift 2 ;;
    --setting) setting=$2; shift 2 ;;
    --kubelet) kpath=$2; shift 2 ;;
    --expect) expect=$2; shift 2 ;;
    --flag) flag=$2; shift 2 ;;
    --file) file=$2; shift 2 ;;
    --file-path) file_path=$2; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$instance" ] || [ -z "$region" ]; then
  echo "--instance and --region are required" >&2
  exit 2
fi

failed=0
fail() { echo "**FAIL:** $*"; failed=1; }
pass() { echo "**PASS:** $*"; }
# Host reads go through the admin container (sheltie). Abort rather than parse an error message.
on_host() {
  local out
  if ! out=$("$SSM/sheltie-command.sh" "$instance" "$region" "$1" 2>&1); then
    echo "host command failed: $1" >&2
    echo "$out" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

# sheltie needs the admin host container; it is disabled by default.
admin=$("$SSM/control-container-command.sh" "$instance" "$region" \
  "apiclient get settings.host-containers.admin.enabled" | jq -r '.settings["host-containers"].admin.enabled // false')
if [ "$admin" != "true" ]; then
  echo "The admin container is not enabled on $instance, so host files cannot be read." >&2
  echo "Launch test nodes with [settings.host-containers.admin] enabled = true, or run:" >&2
  echo "  $SSM/control-container-command.sh $instance $region 'apiclient set host-containers.admin.enabled=true'" >&2
  exit 2
fi

# Read a dotted path from YAML or TOML on stdin; prints JSON, or nothing when absent.
extract() {
  python3 -I -c '
import json, re, sys
fmt, path = sys.argv[1], sys.argv[2]
text = sys.stdin.read()
if fmt == "toml":
    import tomllib
    doc = tomllib.loads(text)
else:
    import yaml
    doc = yaml.safe_load(text.split("+++", 1)[-1])
for part in re.findall(r"\"[^\"]+\"|[^.]+", path):
    part = part.strip("\"")
    if not isinstance(doc, dict) or part not in doc:
        sys.exit(0)
    doc = doc[part]
print(json.dumps(doc))
' "$1" "$2"
}

node=$(kubectl get nodes -o json | jq -r --arg id "$instance" \
  '.items[] | select((.spec.providerID // "") | contains($id)) | .metadata.name' | head -1)
version=$(kubectl get node "$node" -o jsonpath='{.status.nodeInfo.kubeletVersion} {.status.nodeInfo.osImage}' 2>/dev/null || true)

echo "### Evidence: instance $instance, node ${node:-<not registered>}"
echo
echo "kubelet / OS: ${version:-unknown}"
echo

if [ -n "$setting" ]; then
  echo '```'
  echo "$ apiclient get settings.kubernetes.$setting"
  "$SSM/control-container-command.sh" "$instance" "$region" "apiclient get settings.kubernetes.$setting" || true
  echo '```'
fi

if [ -n "$kpath" ]; then
  rendered=$(on_host "cat /etc/kubernetes/kubelet/config" | extract yaml "$kpath")
  echo
  echo "Rendered \`/etc/kubernetes/kubelet/config\` at \`$kpath\`: \`${rendered:-<absent>}\`"
  if [ -z "$node" ]; then
    fail "node is not registered, so /configz cannot be read"
  else
    live=$(kubectl get --raw "/api/v1/nodes/$node/proxy/configz" | jq -c --arg p "$kpath" \
      '.kubeletconfig | getpath($p | split(".")) // empty')
    echo
    echo '```'
    echo "$ kubectl get --raw /api/v1/nodes/$node/proxy/configz | jq '.kubeletconfig.$kpath'"
    echo "${live:-null}"
    echo '```'
    if [ -n "$expect" ]; then
      if [ "$expect" = "absent" ]; then
        if [ -z "$live" ] || [ "$live" = "{}" ] || [ "$live" = "null" ]; then pass "$kpath is absent from /configz"
        else fail "$kpath is $live in /configz, expected absent"; fi
      elif [ "$live" = "$(jq -cn --arg v "$expect" '$v | fromjson? // $v')" ]; then
        pass "/configz reports $kpath = $live"
      else
        fail "/configz reports $kpath = ${live:-<absent>}, expected $expect"
      fi
    fi
  fi
fi

if [ -n "$flag" ]; then
  args=$(on_host "sh -c 'tr \"\\\\0\" \"\\\\n\" < /proc/\$(pgrep -o -x kubelet)/cmdline'" | grep -E -- "^--$flag(=|$)" || true)
  echo
  echo "Running kubelet flag \`--$flag\`: \`${args:-<not set>}\`"
  [ -n "$args" ] || [ -z "$expect" ] || fail "--$flag is not on the kubelet command line"
fi

if [ -n "$file" ]; then
  fmt=yaml; case "$file" in *.toml) fmt=toml ;; esac
  value=$(on_host "cat $file" | extract "$fmt" "$file_path")
  echo
  echo "Rendered \`$file\` at \`$file_path\`: \`${value:-<absent>}\`"
  if [ -n "$expect" ] && [ -z "$kpath" ]; then
    if [ "$value" = "$(jq -cn --arg v "$expect" '$v | fromjson? // $v')" ]; then
      pass "$file_path = $value"
    else
      fail "$file_path = ${value:-<absent>}, expected $expect"
    fi
  fi
fi

# kubelet ignores unknown keys with only a warning, and refuses to start on invalid ones.
warnings=$(on_host "journalctl -u kubelet -b --no-pager -o cat" \
  | grep -iE 'strict decoding|unknown field|invalid configuration|failed to validate kubelet' | tail -5 || true)
echo
if [ -n "$warnings" ]; then
  echo '```'
  echo "$warnings"
  echo '```'
  fail "kubelet logged configuration warnings or errors this boot"
else
  pass "no kubelet configuration warnings this boot"
fi

exit "$failed"
