# Type 6 — host package one-liners (via sheltie)

Run each via the `ssm-executor` skill on a throwaway test node:

```bash
./scripts/sheltie-command.sh INSTANCE_ID REGION "<command>"
```

`<arch>` below is `x86_64` or `aarch64` matching the instance.

## Execution model & gotchas (validated 2026-06-04, aws-k8s-1.35 / 1.61.0)

These materially affect how the one-liners run — validated live on two
instances (`i-0b1672b357b851162` m5.8xlarge, `i-0e03b9341bb79ae3a` m5.xlarge):

1. **The admin host-container must be enabled.** `sheltie` and
   `apiclient exec admin` go through the admin container. On the m5.xlarge it was
   `host-containers.admin.enabled=false`, so **every** command failed with
   `ctr: container "admin" ... not found`. Enable it first (reversible):
   ```bash
   ./scripts/control-container-command.sh INSTANCE_ID REGION \
     "apiclient set host-containers.admin.enabled=true"
   ```
2. **`sheltie -- <cmd>` execs a single binary** via nsenter — no pipes,
   redirections, or shell builtins, and the binary must be on the **host root**
   PATH. To pipe, pipe the *output* in the control-container shell
   (`apiclient exec admin sheltie -- findmnt | head`), and rewrite `cat x | grep`
   as `grep PATTERN x`. Redirections like `echo c > /proc/sysrq-trigger` need a
   shell — wrap them: `... sheltie -- bash -c "..."` (and bash itself is only in
   the admin container; see below).
3. **Some tools live in the admin container, not the host root.** On the tested
   build, `bash` and `ping` resolve only via `apiclient exec admin <cmd>` (drop
   the `sheltie --`). `bash --version` → use the admin container.
4. **Some tools were absent on this build** (neither host nor admin PATH):
   `hwloc-ls`, `strace`, `cryptsetup`. Availability varies by variant — confirm
   the binary's location on the AMI under test before relying on the one-liner.
5. **Device-dependent commands differ by instance type.** `nvme amzn stats
   /dev/nvme2n1` failed on both (m5 has only EBS `nvme0n1`/`nvme1n1`, no
   `nvme2n1`); pick a device that exists (`nvme list` first).

### Validated results on i-0b1672b357b851162 (admin enabled)

| Command | Result |
| ------- | ------ |
| `systemctl is-active chronyd` | `active` |
| `apiclient exec admin bash --version` | bash 5.2.15 (admin container) |
| `iptables --version` | v1.8.12 (nf_tables) |
| `apiclient exec admin ping -c1 amazon.com` | DNS resolves; ICMP blocked by SG (0 received) |
| `keyctl --version` | keyutils-1.6.3 |
| `nvme version` / `nvme list` | 2.16; lists `nvme0n1`,`nvme1n1` (EBS) |
| `ps -ef` | works |
| `findmnt -V` / `findmnt` | util-linux 2.41.3 |
| `sha256sum <x86_64 sysroot>/GPL-2.0` | works (sysroot path present) |
| `ethtool --version` | 6.19 |
| `find /usr/bin -name whoami` | `/usr/bin/whoami` |
| `grep -m1 GNU <GPL-2.0>` | works |
| `ip maddress show` | works |
| `mkfs.xfs -V` / `mkfs.ext4 -V` | 6.18.0 / 1.47.3 |
| `hwloc-ls`, `strace`, `cryptsetup` | not found on host or admin container |
| `nvme amzn stats /dev/nvme2n1` | device absent on m5 |

| Package(s) | Command(s) | Notes |
| ---------- | ---------- | ----- |
| glibc, kmod | (boot an aws-dev instance) | Pass = instance boots. |
| chrony | `systemctl status chronyd` | Service active. |
| bash, readline, libncurses | `bash --version` | |
| hwloc | `hwloc-ls` | Topology prints. |
| iptables, libnftnl | `iptables --version` | |
| iputils | `ping -c1 amazon.com` | Network reachability. |
| kexec-tools, makedumpfile, libelf | `echo c > /proc/sysrq-trigger` | **DESTRUCTIVE** — crashes the node to exercise kdump. Throwaway node only. After it reboots, verify the dump landed (`/var/log/kdump`). |
| keyutils | `keyctl --version` | |
| nvme | `nvme version`; `nvme list`; `nvme amzn stats /dev/nvme2n1` | Device path varies by instance type. |
| procps | `ps -ef` | |
| strace | `strace --version`; `strace ls` | |
| util-linux | `findmnt`; `findmnt -V` | |
| libdevmapper, libcryptsetup | `cryptsetup luksFormat --pbkdf argon2id --batch-mode --key-file /tmp/passphrase /dev/nvmeXn1`; `cryptsetup open --key-file /tmp/passphrase /dev/nvmeXn1 crypt`; `ls -latr /dev/mapper/crypt`; `cryptsetup --version` | Needs an extra ~100GB EBS volume attached. |
| coreutils | `sha256sum /<arch>-bottlerocket-linux-gnu/sys-root/usr/share/licenses/xfsprogs/GPL-2.0` | **arch-specific path.** |
| xfsprogs, liburcu, mdadm, libinih | `apiclient ephemeral-storage init -t xfs`; `apiclient ephemeral-storage bind --dirs /var/lib/kubelet`; `cat /usr/share/xfsprogs/mkfs/default.conf`; `df -h /var/lib/kubelet`; `mkfs.xfs -V` | Needs instance store (ephemeral storage). |
| e2fsprogs | `apiclient ephemeral-storage init -t ext4`; `apiclient ephemeral-storage bind --dirs /var/lib/kubelet`; `df -h /var/lib/kubelet`; `mkfs.ext4 -V` | Needs instance store (ephemeral storage). |
| ethtool | `ethtool --version` | |
| findutils | `find . -name whoami` | |
| grep, libpcre | `cat /<arch>-bottlerocket-linux-gnu/sys-root/usr/share/licenses/xfsprogs/GPL-2.0 \| grep GNU` | **arch-specific path.** |
| iproute | `ip maddress` | |
| policycoreutils | `semodule -i /tmp/test.cil` | Needs a test `.cil` policy staged at `/tmp/test.cil`. |
| acpid, open-vm-tools, libffi, libglib, libisal | (confirm node boots / library loads) | No dedicated one-liner specified. |
| libmnl, libnetfilter_conntrack, libnetfilter_cthelper, libnetfilter_cttimeout, libnetfilter_queue, conntrack-tools, libnfnetlink | (exercise via iptables/conntrack) | No single one-liner specified. |
| libselinux, libsemanage, libsepol | (confirm node boots enforcing; `getenforce`, `semodule -l`) | No single one-liner specified. |

## Destructive / special-setup commands — do NOT run on shared/long-lived nodes

- `echo c > /proc/sysrq-trigger` — crashes the node (kdump test); after reboot, verify `/var/log/kdump`.
- `cryptsetup luksFormat …` — needs an extra attached EBS volume.
- `apiclient ephemeral-storage init/bind …` — needs instance store; reconfigures storage.
- `semodule -i /tmp/test.cil` — modifies SELinux policy; needs a staged `.cil`.
