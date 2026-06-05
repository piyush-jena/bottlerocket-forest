#!/bin/bash
set -euo pipefail
# Map a Bottlerocket third-party package name to its test Type and action.
# Usage: classify-package.sh <package> [<package> ...]
# Pairs with the update-package skill: feed it the package(s) you updated.

[[ $# -ge 1 ]] || { echo "Usage: classify-package.sh <package> [<package> ...]" >&2; exit 1; }

classify() {
  local pkg="$1"
  case "$pkg" in
    libacl|libattr|libaudit|libbpf|libcap|dbus-broker|libxcrypt|libz|libzstd)
      echo "Type 0 | no test required (transitive/library; covered by dependents)" ;;
    binutils|libgcc|libstd-rust|libcrypto|libjansson|libjson-c|libnl|libpopt|libudev|libdrm|cni|cni-plugins)
      echo "Type 0 | no test required (transitive/library; covered by dependents)" ;;

    runc|pigz|libseccomp)
      echo "Type 1 | SKILL=simple-pod-runner (confirm a pod runs)" ;;

    containerd-1.7)
      echo "Type 1 | SKILL=simple-pod-runner on a k8s 1.30/1.31/1.32 variant (confirm a pod runs)" ;;
    containerd-2.1)
      echo "Type 1 | SKILL=simple-pod-runner on a k8s 1.33/1.34/1.35 variant (confirm a pod runs)" ;;
    containerd-2.2)
      echo "Type 1 | SKILL=simple-pod-runner on a k8s 1.36 variant (confirm a pod runs)" ;;

    kubernetes-1.3[0-6])
      echo "Type 2 | SKILL=conformance-runner --kubernetes-version ${pkg#kubernetes-} (run conformance per cluster type)" ;;

    amazon-ssm-agent|docker-cli-*|docker-engine-*|docker-init|ecs-agent|ecs-gpu-init)
      echo "Type 3 | SKILL=macis-runner (ECS variant AMI; Amazon-internal, best effort)" ;;

    soci-snapshotter)
      echo "Type 4 | SKILL=soci-snapshotter-tester" ;;

    nvidia-k8s-device-plugin|nvidia-container-toolkit|libnvidia-container|nvidia-*)
      echo "GPU | SKILL=nvidia-smoke-test-runner (GPU node; confirm a GPU pod runs)" ;;

    ecr-credential-helper)
      echo "Type 5 | SKILL=ssm-executor: enable image-verifier-plugins, then 'ctr i pull' (see SKILL.md Type 5)" ;;

    aws-iam-authenticator)
      echo "EKS | SKILL=eks-smoke-test (node registers/joins the cluster)" ;;

    # ---- Type 6: SKILL=ssm-executor sheltie one-liners ----
    chrony)
      echo "Type 6 | sheltie: systemctl status chronyd" ;;
    bash|readline|libncurses)
      echo "Type 6 | sheltie: bash --version" ;;
    hwloc)
      echo "Type 6 | sheltie: hwloc-ls" ;;
    iptables|libnftnl)
      echo "Type 6 | sheltie: iptables --version" ;;
    iputils)
      echo "Type 6 | sheltie: ping -c1 amazon.com" ;;
    kexec-tools|makedumpfile|libelf)
      echo "Type 6 | sheltie: echo c > /proc/sysrq-trigger  (DESTRUCTIVE: crashes node; after reboot verify /var/log/kdump). Throwaway node only." ;;
    keyutils)
      echo "Type 6 | sheltie: keyctl --version" ;;
    nvme-cli|libnvme)
      echo "Type 6 | sheltie: nvme version; nvme list; nvme amzn stats /dev/nvme2n1" ;;
    procps)
      echo "Type 6 | sheltie: ps -ef" ;;
    strace)
      echo "Type 6 | sheltie: strace --version; strace ls" ;;
    util-linux)
      echo "Type 6 | sheltie: findmnt; findmnt -V" ;;
    libdevmapper|libcryptsetup)
      echo "Type 6 | sheltie: cryptsetup luksFormat/open/--version on an attached EBS vol (needs extra 100GB vol)" ;;
    coreutils)
      echo "Type 6 | sheltie: sha256sum /<arch>-bottlerocket-linux-gnu/sys-root/usr/share/licenses/xfsprogs/GPL-2.0" ;;
    xfsprogs|liburcu|mdadm|libinih)
      echo "Type 6 | sheltie: apiclient ephemeral-storage init -t xfs; bind /var/lib/kubelet; mkfs.xfs -V (needs ephemeral storage)" ;;
    e2fsprogs)
      echo "Type 6 | sheltie: apiclient ephemeral-storage init -t ext4; bind /var/lib/kubelet; mkfs.ext4 -V (needs ephemeral storage)" ;;
    ethtool)
      echo "Type 6 | sheltie: ethtool --version" ;;
    findutils)
      echo "Type 6 | sheltie: find . -name whoami" ;;
    grep|libpcre)
      echo "Type 6 | sheltie: cat /<arch>-bottlerocket-linux-gnu/sys-root/usr/share/licenses/xfsprogs/GPL-2.0 | grep GNU" ;;
    iproute)
      echo "Type 6 | sheltie: ip maddress" ;;
    policycoreutils)
      echo "Type 6 | sheltie: semodule -i /tmp/test.cil (needs a test .cil policy)" ;;
    glibc|kmod)
      echo "Type 6 | aws-dev instance: confirm the instance boots" ;;
    acpid|open-vm-tools|libffi|libglib|libisal|libtirpc)
      echo "Type 6 | confirm node boots / package loads (no dedicated one-liner)" ;;
    libmnl|libnetfilter_conntrack|libnetfilter_cthelper|libnetfilter_cttimeout|libnetfilter_queue|conntrack-tools|libnfnetlink)
      echo "Type 6 | netfilter stack: exercise via iptables/conntrack on the node (no single one-liner specified)" ;;
    libselinux|libsemanage|libsepol)
      echo "Type 6 | SELinux stack: confirm node boots enforcing; exercise via semodule/getenforce (no single one-liner specified)" ;;

    # ---- No test required ----
    rocm-container-toolkit|rocm-k8s-device-plugin)
      echo "No test | ROCm/AMD-GPU tooling — not tested by this skill" ;;
    systemd-252|systemd-257|early-boot-config|static-pods|netdog|login|os|release|filesystem|selinux-policy|rottweiler)
      echo "No test | core OS / config / init component — not exercised by this skill" ;;
    amazon-ecs-cni-plugins|amazon-vpc-cni-plugins|cri-tools|host-ctr|erofs-utils|libaio|libtss2|tpm2-tools|nftables|notation|aws-signer-notation-plugin|aws-signing-helper|aws-otel-collector|perf|pciutils|rdma-core|ecr-credential-provider-*)
      echo "No test | not exercised by this skill" ;;

    *)
      echo "UNKNOWN | not in the test matrix — classify manually (default: boot + relevant smoke test)" ;;
  esac
}

for pkg in "$@"; do
  printf '%-32s %s\n' "$pkg" "$(classify "$pkg")"
done
