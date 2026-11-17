<!-- Audit of shipped settings, 2026-11-17, against core-kit a4f438b1f, settings-sdk 06d9d1a, bottlerocket b7c6c274,
     and the EKS-D sources packaged in core-kit for Kubernetes 1.31-1.37 (containerd 1.7/2.2/2.3).
     Line numbers drift; re-run scripts/k8s-field-report.py before relying on a citation.
     Status of the findings as of this date: see ../../SKILL.md "Known open findings". -->

# containerd

Scope: settings under `settings.kubernetes.*` that are consumed by containerd rather than kubelet.
"Per version" here means per packaged containerd (1.7.36, 2.2.10, 2.3.7) and which Bottlerocket k8s variants render each.
Grove: bottlerocket `b7c6c274` (v1.69.0-2), core-kit `a4f438b1` (v18.0.0-2, the version bottlerocket's `Twoliter.toml` pins), settings-sdk `06d9d1a`.
Upstream paths are relative to each package's `src/containerd-<ver>/` and prefixed `1.7:`, `2.2:`, `2.3:`; Kubernetes paths are prefixed with the minor (`1.33:`).
The containerd cache is the unpatched upstream tarball; none of the core-kit containerd patches touch the files cited here (they touch `archive/compression`, `cmd/ctr`, `contrib/seccomp`, `core/remotes`, `core/transfer`, and 1.7 `services/server/config/config.go` for config-import merging only).

## settings.kubernetes.device-ownership-from-security-context

### Upstream per version

containerd (the consumer):

| containerd pkg | exists | TOML table . key, Go field/type | upstream default | validation | gate | notes |
|---|---|---|---|---|---|---|
| 1.7 (1.7.36) | yes | `[plugins."io.containerd.grpc.v1.cri"]` `device_ownership_from_security_context`; `PluginConfig.DeviceOwnershipFromSecurityContext bool` (1.7:pkg/cri/config/config.go:340-342), `PluginConfig` is embedded inline in the CRI plugin `Config` (config.go:405-407), registered as type `io.containerd.grpc.v1` id `cri` (1.7:pkg/cri/cri.go:41-46, 1.7:plugin/plugin.go:62) | false (Go zero value; `DefaultConfig()` 1.7:pkg/cri/config/config_unix.go:28 does not set it) | TOML bool only, no other validation. Config `version` must be <= 2, `version = 3` makes containerd refuse to start (1.7:services/server/config/config.go:106-109). Unknown keys are silently ignored (plugin config is `toml.Tree.Unmarshal`, config.go:181-190; no strict mode, inferred from go-toml v1) | none | Applied in `WithDevices` (1.7:pkg/cri/opts/spec_linux_opts.go:240-281, override at 263-279), called from both CRI servers (1.7:pkg/cri/server/container_create_linux.go:222, 1.7:pkg/cri/sbserver/container_create.go:711). No in-tree variant uses this package today. |
| 2.2 (2.2.10) | yes | `[plugins."io.containerd.cri.v1.runtime"]` `device_ownership_from_security_context`; `RuntimeConfig.DeviceOwnershipFromSecurityContext bool` (2.2:internal/cri/config/config.go:354, 389-391), registered as type `io.containerd.cri.v1` id `runtime` (2.2:plugins/cri/runtime/plugin.go:43-56, 2.2:plugins/types.go:75) | false (zero value; `DefaultRuntimeConfig()` 2.2:internal/cri/config/config_unix.go:49 does not set it; upstream doc 2.2:docs/cri/config.md:266 shows `= false`) | TOML bool. Max config version 3 (2.2:version/version.go:41). Unknown keys: warning `Ignoring unknown key in TOML for plugin`, containerd still starts (2.2:cmd/containerd/server/config/config.go:268-275) | none | `WithDevices` 2.2:internal/cri/opts/spec_linux_opts.go:314-355, call 2.2:internal/cri/server/container_create.go:846. A `version = 2` file's `plugins."io.containerd.grpc.v1.cri".device_ownership_from_security_context` is migrated to `cri.v1.runtime` (2.2:plugins/cri/runtime/plugin.go:197-212, default branch 242-245). No in-tree variant uses this package today. |
| 2.3 (2.3.7) | yes | same as 2.2: `[plugins."io.containerd.cri.v1.runtime"]` (2.3:internal/cri/config/config.go:354, 389-391; 2.3:plugins/cri/runtime/plugin.go:47-56; 2.3:plugins/types.go:77; upstream doc 2.3:docs/cri/config.md:255,266) | false (zero value, 2.3:internal/cri/config/config_unix.go:49) | TOML bool. Max config version **4** (2.3:version/version.go:41; table at 2.3:RELEASES.md:446-463). A `version = 3` file is migrated on every start with warning `Configuration migrated from version 3, use containerd config migrate...` (2.3:cmd/containerd/server/config/config.go:474-496); the v3->v4 step only moves server properties into plugins (config.go:49-54). Unknown keys: warning, still starts (config.go:421-428) | none | `WithDevices` 2.3:internal/cri/opts/spec_linux_opts.go:315-356, call 2.3:internal/cri/server/container_create.go:857. Because ConfigVersion is 4, the CRI v2->v3 migration (2.3:plugins/cri/runtime/plugin.go:204-219, 249-252) also runs for `version = 3` files. **Every in-tree k8s variant uses this package.** |

kubelet (the producer of the inputs), identical for 1.31 through 1.37:

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31-1.37 | no kubelet field or flag | n/a | n/a | n/a | none for this setting | kubelet only supplies the CRI inputs containerd acts on: `ContainerConfig.Devices` from device-plugin `DeviceSpecs` (1.31:pkg/kubelet/cm/devicemanager/pod_devices.go:305, appended in 1.31:pkg/kubelet/cm/container_manager_linux.go:675 / 1.37:...:767) and from raw-block `volumeDevices` (1.31:pkg/kubelet/kubelet_pods.go:605, 1.32:622, 1.33:627, 1.34:642, 1.35:650, 1.36:650, 1.37:672; built by `makeBlockVolumes` 1.31:kubelet_pods.go:205-234), converted by `makeDevices` (1.31:pkg/kubelet/kuberuntime/kuberuntime_container.go:366,408-421; 1.37:379,457-470); plus `RunAsUser`/`RunAsGroup` from the effective pod+container securityContext (1.31:pkg/kubelet/kuberuntime/security_context.go:108-111; 1.37:109-112), with `RunAsUser` falling back to a numeric image `USER` (1.31:security_context.go:52-56; 1.37:53-57). DRA and device-plugin CDI devices go to `CDIDevices` instead (1.37:container_manager_linux.go:757,771) and are not affected. |

What the setting does (identical code in all three packages; `diff` of `getDeviceUserGroupID`..`WithDevices` between 1.7/2.2/2.3 is empty):

- For each CRI `Device`, containerd resolves the host path symlink and calls `oci.WithDevices`, which `Lstat`s the host node and copies its type, major:minor, mode, **uid and gid** into `spec.linux.devices` (2.3:pkg/oci/spec_opts_linux.go:43-61, 2.3:pkg/oci/utils_unix.go:145-186).
- If the setting is true, for the devices just added it overwrites `UID` with `RunAsUser` and `GID` with `RunAsGroup`, each only when non-zero (2.3:internal/cri/opts/spec_linux_opts.go:338-354; `getDeviceUserGroupID` returns 0 for unset, 307-312). So `runAsUser: 0` or unset keeps the host uid, and `runAsGroup` unset keeps the host gid. Mode bits are never changed.
- runc then `mknod`s the node inside the container and `fchown`s it to the spec uid/gid (runc 1.3.6, the version core-kit packages, `libcontainer/rootfs_linux.go:1018-1068`, fetched with `gh api` at commit `491b69ba`). If the container has a user namespace, runc bind-mounts the host node instead (rootfs_linux.go:963, 1004-1005), so the override has no visible effect; containerd notes the same (2.3:internal/cri/opts/spec_linux_opts.go:300-305).
- Not affected: privileged containers' host devices (`oci.WithHostDevices` is appended after `WithDevices`, which only touches the devices it added: 2.3:internal/cri/server/container_create.go:857 vs 866, `oldDevices` at spec_linux_opts.go:324), CDI devices (2.3:internal/cri/server/container_create_linux.go:104), and hostPath volumes of type `CharDevice`/`BlockDevice` (these are bind mounts, not CRI devices).
- Upstream test: containerd unit test `TestNonRootUserAndDevices` (2.3 and 2.2:internal/cri/server/container_create_linux_test.go:1160; 1.7:pkg/cri/server/container_create_linux_test.go:1590 and pkg/cri/sbserver/container_create_linux_test.go:1411) checks only the spec uid/gid. No Kubernetes `test/e2e_node` test covers it: the sample device plugin returns `Mounts`, not `DeviceSpecs` (1.37:test/images/sample-device-plugin/sampledeviceplugin.go:70-73).

### What changes between versions

- TOML table: 1.7 reads it from `[plugins."io.containerd.grpc.v1.cri"]` (1.7:pkg/cri/cri.go:41-46). 2.2 and 2.3 read it from `[plugins."io.containerd.cri.v1.runtime"]` (2.x:plugins/cri/runtime/plugin.go:47-56). The Go type, default (false) and behavior are unchanged.
- Config version: 1.7 accepts at most `version = 2` and fails to start on 3 (1.7:services/server/config/config.go:106-109). 2.2 accepts up to 3 (2.2:version/version.go:41). 2.3 accepts up to 4 and migrates a `version = 3` file on every start, logging a warning (2.3:version/version.go:41, 2.3:cmd/containerd/server/config/config.go:474-496).
- Misplaced key: in 1.7 it is silently ignored; in 2.2/2.3 it is ignored with an `Ignoring unknown key in TOML for plugin` warning (2.2:cmd/containerd/server/config/config.go:268-275, 2.3:...:421-428). A v2-style `grpc.v1.cri` placement inside a `version = 3` file is ignored by 2.2 but migrated by 2.3 (because 3 < 4, 2.3:plugins/cri/runtime/plugin.go:204-219). Not relevant to the current templates, which use the right table.
- Kubernetes 1.31-1.37: none in the code path that feeds this setting (same functions, line numbers above). Indirectly, `UserNamespacesSupport` is Beta/off in 1.31-1.32 (1.31:pkg/features/kube_features.go:1228), Beta/on from 1.33 (1.33:pkg/features/kube_features.go:1838-1842), GA/locked from 1.36 (1.36:pkg/features/kube_features.go:2093-2098). Pods that opt into `hostUsers: false` get bind-mounted devices, and the setting has no visible effect for them (runc rootfs_linux.go:963).

### Bottlerocket implementation

**Model.** `device_ownership_from_security_context: bool` in `KubernetesSettingsV1` (bottlerocket-settings-sdk/bottlerocket-settings-models/settings-extensions/kubernetes/src/lib.rs:31-32, 97); `#[model]` makes it `Option<bool>`, and `validate` accepts everything (lib.rs:136-138). containerd also takes a plain TOML bool with no other validation. So nothing Bottlerocket accepts can make containerd fail, and nothing containerd accepts is rejected by Bottlerocket.

**Templates.** All six k8s templates render the same line, `device_ownership_from_security_context = {{default false settings.kubernetes.device-ownership-from-security-context}}`, and all of them list `default` in `required-extensions`:

| package | template | `version =` | line | table | correct for that containerd + version? |
|---|---|---|---|---|---|
| containerd-1.7 | containerd-config-toml_k8s_containerd_sock | 2 (line 7) | 24 | `[plugins."io.containerd.grpc.v1.cri"]` (23) | yes |
| containerd-1.7 | containerd-config-toml_k8s_nvidia_containerd_sock | 2 (7) | 24 | `[plugins."io.containerd.grpc.v1.cri"]` (23) | yes |
| containerd-2.2 | containerd-config-toml_k8s_containerd_sock | 3 (7) | 33 | `[plugins."io.containerd.cri.v1.runtime"]` (32) | yes |
| containerd-2.2 | containerd-config-toml_k8s_nvidia_containerd_sock | 3 (7) | 33 | `[plugins."io.containerd.cri.v1.runtime"]` (32) | yes |
| containerd-2.3 | containerd-config-toml_k8s_containerd_sock | 3 (7) | 33 | `[plugins."io.containerd.cri.v1.runtime"]` (32) | yes (table is also valid after the v3->v4 migration) |
| containerd-2.3 | containerd-config-toml_k8s_nvidia_containerd_sock | 3 (7) | 33 | `[plugins."io.containerd.cri.v1.runtime"]` (32) | yes |

(paths: `kits/bottlerocket-core-kit/packages/containerd-<v>/<template>`; 2.2 and 2.3 templates are byte-identical.)
The `_basic` templates (non-k8s variants) correctly omit it.
Helper behavior (kits/bottlerocket-core-kit/sources/api/schnauzer/src/helpers/stdlib/mod.rs:517-577): unset (null) renders `false`, `false` renders `false`, `true` renders `true`, all bare, so TOML gets a boolean. The key is always rendered, which matches upstream's default when unset.
No version supports it upstream without rendering it, and none renders it where it is unsupported.
No feature gates or related settings.

**Which variant renders which template** (current main):

The containerd package comes from each variant's `included-packages` (`bottlerocket/variants/<v>/Cargo.toml`). Every in-tree variant, k8s or not, now lists `"containerd-2.3"`. 1.7 and 2.2 are still built and shipped in core-kit (kits/bottlerocket-core-kit/Cargo.toml:18-19) for kit consumers. containerd-1.7 has the highest `package_priority_epoch` (2, containerd-1.7.spec:9 vs 0 for 2.2/2.3), so it is the default provider of the `containerd` capability for a variant that does not pin one (inferred from the epoch convention).
History: at v1.68.1, aws/vmware k8s 1.31-1.32 pinned nothing and got 1.7, 1.33-1.36 pinned 2.2, and 1.37 pinned 2.3. The bumps to 2.3 landed 2026-10-29 (for example `583ec013`, `02b80a95`) and are in v1.69.0.
The template comes from `configuration-files.containerd-config-toml.template-path`: `shared-defaults/kubernetes-containerd.toml:1-3` (`_k8s_containerd_sock`) or `shared-defaults/kubernetes-containerd-nvidia.toml:1-3` (`_k8s_nvidia_containerd_sock`), linked as `51-*` in each `sources/settings-defaults/<v>/defaults.d/`. Defaults packages map to variants in `packages/settings-defaults/settings-defaults.spec`: `-fips` shares the non-fips dir, except aws-k8s-1.31/1.32-nvidia-fips, which have their own; vmware-k8s-1.31 uses the vmware-k8s-1.32 dir (spec:369).

| variants (incl. -fips) | containerd | template | Bottlerocket default (defaults.d link) |
|---|---|---|---|
| aws-k8s-1.31 | 2.3 | k8s_containerd_sock | false (55-) |
| aws-k8s-1.31-nvidia, -nvidia-fips | 2.3 | k8s_nvidia | false (55-) |
| aws-k8s-1.32 ... 1.37 | 2.3 | k8s_containerd_sock | **true** (57-) |
| aws-k8s-1.32, 1.33, 1.34 -nvidia(-fips) | 2.3 | k8s_nvidia | false (57-...-default-false) |
| aws-k8s-1.35, 1.36, 1.37 -nvidia(-fips) | 2.3 | k8s_nvidia | **true** (57-) |
| vmware-k8s-1.31 ... 1.34 | 2.3 | k8s_containerd_sock | false (55-) |
| vmware-k8s-1.35 ... 1.37 | 2.3 | k8s_containerd_sock | **true** (55-...-default-true) |

(`sources/shared-defaults/kubernetes-device-ownership-default-{true,false}.toml`. The true variant was introduced with the 1.32 variants in `28136d8d`. The nvidia and vmware flips to true came with the 1.35 variants in `7247e6ca`, without a stated reason.)

**Runtime change: what restarts.** Both shared-defaults files set `[metadata.settings.kubernetes.device-ownership-from-security-context] affected-services = ["containerd"]` (lines 4-5). The datastore returns the deepest metadata found along the key path (kits/bottlerocket-core-kit/sources/api/datastore/src/lib.rs:95-117), so this overrides `metadata.settings.kubernetes` `["kubernetes"]` (shared-defaults/kubernetes-aws.toml:8-9, kubernetes-vmware.toml:9-11).
thar-be-settings then re-renders the `containerd` service's files, `containerd-config-toml` (`/etc/containerd/config.toml`) and `proxy-env`, and runs `/bin/systemctl try-restart containerd.service` (shared-defaults/defaults.toml:24-30; thar-be-settings/src/main.rs:169-186). kubelet's files are not re-rendered and kubelet does not need them.
kubelet is restarted anyway: every `kubelet.service` has `BindsTo=containerd.service` (kits/bottlerocket-core-kit/packages/kubernetes-1.3{1..7}/kubelet.service:6), and systemd propagates a restart of the bound unit (inferred from systemd.unit(5) Requires/BindsTo semantics; check `ActiveEnterTimestamp`, below).
Running containers survive the restart (`KillMode=process`, packages/containerd-2.3/containerd.service:14). Their device nodes were created by runc at create time, and containerd reads its config only at plugin init. **A running pod keeps its old ownership. Only containers created after the restart get the new behavior:** the pod has to be recreated, or the container restarted, which issues a new CreateContainer (inferred from the code path).

**Migration.** Present: `bottlerocket/sources/settings-migrations/archived/v1.30.0/kubernetes-device-ownership-{metadata,settings}`, listed in `Release.toml:383-386` for `(1.29.0, 1.30.0)`. On downgrade they remove the setting (`AddSettingsMigration`) and its `affected-services` metadata (`AddMetadataMigration`). The directory names are swapped relative to their contents (nit below).

**Docs.** Present: website `data/settings/1.30.x/kubernetes.toml:1-25`. Its default text is inaccurate (finding below).

**Release history.** core-kit #329 (`6da9476a2`, first tag v5.3.0) rendered the setting only in the non-NVIDIA template. #343 (`1b596392c`, first tag v5.4.0) added the NVIDIA one. Bottlerocket v1.30.0 shipped core-kit 5.3.0 (`CHANGELOG.md:1178-1190`, `Twoliter.toml` at tag v1.30.0), and v1.31.0 moved to core-kit 5.4.1 (`CHANGELOG.md:1159-1166`). So on v1.30.0 NVIDIA variants the API accepted the setting but containerd never saw it.

### How to verify it works on a node

Which device: any device that reaches containerd as a CRI `Device`. That means a device-plugin `DeviceSpec` or a raw-block PVC `volumeDevices`. A hostPath `CharDevice`/`BlockDevice` volume or a privileged container does **not** exercise the setting.
The cheapest choice on any EC2 instance, with no third-party image, is a **local PersistentVolume in `volumeMode: Block` backed by a loop device**. The loop module is `=m` with `CONFIG_BLK_DEV_LOOP_MIN_COUNT=8` (kits/bottlerocket-kernel-kit/packages/kernel-6.12/config-full-bottlerocket-x86_64:2142-2143), and `losetup` and `modprobe` ship on the host (core-kit packages/util-linux/util-linux.spec:275, packages/kmod/kmod.spec:88).
A loop device also has a restrictive mode (`0660 root:disk`, inferred from standard udev rules; check on the host), so the effect shows up both in `ls -ln` and as a real access difference. An alternative is a generic device plugin (for example squat/generic-device-plugin exposing `/dev/fuse` or a loop device). Neuron or NVIDIA devices on accelerated instances also work and are what the original PRs tested.

1. Setting and metadata (admin container):
   ```
   apiclient get os settings.kubernetes.device-ownership-from-security-context
   apiclient raw -u '/metadata/affected-services?keys=settings.kubernetes.device-ownership-from-security-context'
   # expect {"settings.kubernetes.device-ownership-from-security-context":["containerd"]}
   ```
   The expected default per variant is in the table above. The value is not visible in `kubectl get --raw /api/v1/nodes/$NODE/proxy/configz`, because it is not a kubelet field.
2. Rendered and effective containerd config (`sudo sheltie`; the host has grep but no awk or sed):
   ```
   grep -n '^version' /etc/containerd/config.toml                     # 3 on containerd-2.2/2.3 variants, 2 on 1.7
   grep -n -e '^\[' -e device_ownership /etc/containerd/config.toml | grep -B1 device_ownership
   # expect: 32:[plugins."io.containerd.cri.v1.runtime"]
   #         33:device_ownership_from_security_context = true|false
   containerd config dump | grep -n -e "^\[plugins.'io.containerd.cri.v1.runtime'\]" -e device_ownership
   # effective value after imports and migration (2.3 prints version = 4; exact formatting inferred)
   journalctl -u containerd -b --no-pager | grep -Ei 'unknown key|migrated from version'
   # expect no "unknown key" lines; on 2.3 one "Configuration migrated from version 3" warning per start is expected
   ```
3. Create a loop device (sheltie): `modprobe loop; truncate -s 16M /var/lib/devown.img; losetup --find --show /var/lib/devown.img` prints for example `/dev/loop0`. Then `ls -ln /dev/loop0` should show `brw-rw---- 1 0 6 7, 0` (record the actual owner; that is the expected value for the "false" case).
4. Apply (replace `NODE_HOSTNAME` with `kubectl get node $NODE -o jsonpath='{.metadata.labels.kubernetes\.io/hostname}'` and `/dev/loop0` with step 3's device):
   ```yaml
   apiVersion: v1
   kind: PersistentVolume
   metadata: {name: devown-pv}
   spec:
     capacity: {storage: 16Mi}
     volumeMode: Block
     accessModes: [ReadWriteOnce]
     persistentVolumeReclaimPolicy: Retain
     storageClassName: devown
     local: {path: /dev/loop0}
     nodeAffinity:
       required:
         nodeSelectorTerms:
         - matchExpressions:
           - {key: kubernetes.io/hostname, operator: In, values: [NODE_HOSTNAME]}
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata: {name: devown-pvc}
   spec:
     volumeMode: Block
     accessModes: [ReadWriteOnce]
     storageClassName: devown
     resources: {requests: {storage: 16Mi}}
   ---
   apiVersion: v1
   kind: Pod
   metadata: {name: devown}
   spec:
     securityContext: {runAsUser: 1000, runAsGroup: 2000}   # no supplementalGroups/fsGroup: they would mask the DAC result
     containers:
     - name: c
       image: public.ecr.aws/docker/library/busybox:1.36
       command: ["sh","-c","id; ls -ln /dev/xvdtest; dd if=/dev/xvdtest of=/dev/null bs=4096 count=1 && echo READ_OK || echo READ_DENIED; sleep 3600"]
       volumeDevices: [{name: blk, devicePath: /dev/xvdtest}]
     volumes:
     - {name: blk, persistentVolumeClaim: {claimName: devown-pvc}}
   ```
   `kubectl logs devown` and `kubectl exec devown -- ls -ln /dev/xvdtest`:
   - setting **true**: `brw-rw----  1 1000  2000  7,  0 ... /dev/xvdtest` and `READ_OK`.
   - setting **false**: `brw-rw----  1 0  6  7,  0 ... /dev/xvdtest` (the host owner from step 3) and `dd: can't open '/dev/xvdtest': Permission denied`, `READ_DENIED`.
   The `ls -ln` owner is the authoritative signal. The `dd` result additionally depends on Bottlerocket's SELinux policy allowing container block-device reads (inferred; EBS raw-block volumes work on Bottlerocket).
   Variations: `runAsGroup` only gives `0 2000`; `runAsUser: 0` keeps the host uid; an image with numeric `USER 1000` and no `runAsUser` still gives uid 1000; `hostUsers: false` (1.33+ by default gate) shows the host owner mapped through the user namespace, not 1000/2000 (inferred).
5. Node-side proof in the OCI spec (sheltie):
   ```
   CID=<kubectl get pod devown -o jsonpath='{.status.containerStatuses[0].containerID}' without containerd://>
   ctr -n k8s.io containers info "$CID" | grep -A6 '"path": "/dev/xvdtest"'
   # true: "uid": 1000, "gid": 2000   false: "uid": 0, "gid": 6
   ```
6. A/B on the same node, and the restart and pod-recreation claim:
   ```
   systemctl show -p ActiveEnterTimestamp containerd kubelet        # sheltie, note values
   apiclient set settings.kubernetes.device-ownership-from-security-context=false   # flip from the default
   systemctl show -p ActiveEnterTimestamp containerd kubelet        # both should advance (kubelet via BindsTo, inferred)
   kubectl exec devown -- ls -ln /dev/xvdtest                       # unchanged: running container keeps old owner
   kubectl delete pod devown && kubectl apply -f devown.yaml         # recreate
   kubectl exec devown -- ls -ln /dev/xvdtest                       # now shows the new behavior
   ```
   Cleanup: delete pod, PVC and PV, then `losetup -d /dev/loop0; rm /var/lib/devown.img` (kubelet also attaches a second loop device as an fd lock for block volumes and releases it on unmap, 1.33:pkg/volume/util/util.go:456-464).
   Expected results per version: identical on every in-tree variant (all are containerd-2.3) for Kubernetes 1.31-1.37. Only the starting default differs (table above). On an out-of-tree containerd-1.7 variant, step 2 shows `version = 2` and `[plugins."io.containerd.grpc.v1.cri"]`.
   Time: about 5 minutes on an existing node (steps 1-6), 10-15 minutes including node launch. To check the defaults of all variant families, one node per row of the defaults table is enough; the containerd behavior does not need re-testing per Kubernetes minor.

### Findings

- [bug] Website default is wrong for 1.32-1.34 NVIDIA and VMware. The docs say "`true` for k8s-1.32+ variants, `false` for other variants" (website data/settings/1.30.x/kubernetes.toml:6). Actual defaults: aws-k8s-1.32/1.33/1.34-nvidia(-fips) are **false** (`sources/settings-defaults/aws-k8s-1.3{2,3,4}-nvidia*/defaults.d/57-kubernetes-device-ownership-default-false.toml`), and vmware-k8s-1.32/1.33/1.34(-fips) are **false** (`sources/settings-defaults/vmware-k8s-1.3{2,3,4}/defaults.d/55-kubernetes-device-ownership-default-false.toml`). Effect: a user on aws-k8s-1.33-nvidia who relies on the docs gets host-owned (root) device nodes in non-root pods. Fix: document the per-variant defaults (table above) or align the defaults.
- [risk] Defaults differ between flavors of the same Kubernetes minor with no recorded rationale: aws-k8s-1.32-1.34 are true while their -nvidia flavors are false, and aws-k8s-1.32-1.34 are true while vmware-k8s-1.32-1.34 are false. The 1.35 variant-add commit `7247e6ca` flipped nvidia and vmware to true without comment. This is not a code bug, but it is easy to replicate wrongly when adding variants. Suggest a comment in shared-defaults or the docs that records the intent, or aligning the defaults.
- [risk] The containerd-only routing depends on per-variant defaults. `affected-services = ["containerd"]` exists only in `shared-defaults/kubernetes-device-ownership-default-{true,false}.toml:4-5`, linked separately into each of the 23 k8s settings-defaults dirs (all currently have it). A future k8s variant that omits the link would fall back to `metadata.settings.kubernetes` = `["kubernetes"]` (datastore/src/lib.rs:95-117; shared-defaults/kubernetes-aws.toml:8-9). `apiclient set` would then restart kubelet without re-rendering `/etc/containerd/config.toml`, so the change only takes effect at the next reboot. Neither research tool checks this. Suggest a lint: every `settings.kubernetes.*` key rendered only in containerd templates must have containerd in its effective affected-services for every variant.
- [bug, fixed] NVIDIA variants ignored the setting in Bottlerocket v1.30.0: core-kit 5.3.0 contained #329 but not #343 (`git tag --contains 6da9476a2` starts at v5.3.0, `1b596392c` at v5.4.0); fixed in v1.31.0 (core-kit 5.4.1, `CHANGELOG.md:1166`). Only users who explicitly set `true` on NVIDIA in v1.30.0 were affected, because all NVIDIA defaults were false then. No action needed.
- [nit] The migration directory names are swapped: `archived/v1.30.0/kubernetes-device-ownership-metadata/src/main.rs` runs `AddSettingsMigration`, and `.../kubernetes-device-ownership-settings/src/main.rs` runs `AddMetadataMigration`. This is harmless because both run (`Release.toml:384-385`), but it is misleading as a template for new migrations.
- [nit] The docs omit behavior users need (data/settings/1.30.x/kubernetes.toml:2-25):
  - It applies only to device-plugin `DeviceSpecs` and raw-block `volumeDevices`. It does not apply to CDI or DRA devices, which matters on NVIDIA variants defaulting to `device-list-strategy = "cdi-cri"` (shared-defaults/nvidia-k8s-device-plugin-cdi.toml), to hostPath device mounts, to privileged containers' host devices, or to `hostUsers: false` pods.
  - Zero or unset `runAsUser`/`runAsGroup` leave the host owner, and a numeric image `USER` counts as `runAsUser`.
  - The `fsGroup` in the example is irrelevant.
  - "You will need to enable ownership" is wrong on variants where the default is true.
  - Changing the setting restarts containerd (and kubelet), and only newly created containers see the change.
  - "v1.30.0+" is effectively v1.31.0+ for NVIDIA.
- [nit] The containerd-2.3 templates declare `version = 3`, but containerd 2.3's current version is 4 (2.3:version/version.go:41), so containerd migrates and logs a warning on every start (2.3:cmd/containerd/server/config/config.go:496). This is harmless for this key: v3->v4 only moves server properties (config.go:49-54), and `cri.v1.runtime` stays valid. Optional: emit `version = 4` from the 2.3 templates, which means moving `[grpc]` into the server plugin. This is outside this setting and needs its own review.

## Script feedback

- `python3 -I $T/k8s-field-report.py containerd device_ownership_from_security_context`:
  - It prints the Go struct (`PluginConfig` vs `RuntimeConfig`) but not the plugin URI and TOML table that struct is registered under. That table is what the template must use: `plugins."io.containerd.grpc.v1.cri"` comes from 1.7:pkg/cri/cri.go:41-46, and `plugins."io.containerd.cri.v1.runtime"` from 2.x:plugins/cri/runtime/plugin.go:47-56. Its "Changes between consecutive versions" diff therefore shows only a file and struct rename and hides the table move. Suggest resolving the struct to its `registry.Register`/`plugin.Register` call (type + ID) and printing the table.
  - It does not print the max config version (1.7: 2, 2.2: 3, 2.3: 4). Note that 2.3 is 4, not 3.
  - The default lookup greps for a `DeviceOwnershipFromSecurityContext:` literal, finds none, and prints nothing. It should say "not set in DefaultConfig/DefaultRuntimeConfig: Go zero value (false)".
  - Unlike `field` mode, it lists no consumers. Grepping `\.DeviceOwnershipFromSecurityContext\b` would surface `WithDevices` and its call sites, and `-rl` over `*_test.go` would surface `TestNonRootUserAndDevices`.
  - It treats 1.7, 2.2 and 2.3 as equally relevant. Printing which variants include each package would show that only 2.3 is in-tree today.
  - It does not say that the cache is unpatched upstream source, or check whether any core-kit patch touches the cited files (none do here).
- `python3 -I $T/template-drift.py containerd --matrix`:
  - Output today is "no drift found". `--matrix` in containerd mode prints only per-template key counts, not the key x template table that `--help` promises.
  - It checks key presence only, never the TOML table or `version =`. Repro: in a copy of the 2.3 templates (`a scratch copy (not kept)`), I moved the NVIDIA line under `[grpc]`, ran `CORE_KIT=a scratch copy (not kept) python3 -I $T/template-drift.py containerd --matrix`, and it printed "no drift found", exit 0. containerd 2.3 would ignore the key with a warning, and true would silently not apply.
  - Would it have caught #343? Not on the tree where the bug lived. At core-kit `2ec1472bc` (after #329, before #343) the package was `packages/containerd` with no version suffix. `CORE_KIT=a scratch copy (not kept) python3 -I $T/template-drift.py containerd --matrix` prints "no drift found", exit 0, because the glob `containerd-*` matches nothing and zero packages counts as a pass. With the same files copied into `packages/containerd-1.7/`, it correctly flags `MISSING settings.kubernetes.device-ownership-from-security-context ... not in containerd-config-toml_k8s_nvidia_containerd_sock`, exit 1. Suggest also globbing `containerd` and failing loudly when no package matches.
  - It does not cover the per-variant pieces that decide whether a containerd-consumed `settings.kubernetes.*` key works at runtime: `affected-services` metadata routing to containerd, and the template-path selection in `bottlerocket/sources/settings-defaults/*`. Those live in the bottlerocket repo (see the risk finding).
  - With `--key settings.` it reports `DRIFT settings.container-registry.{credentials,mirrors}: rendered in containerd-1.7, missing in containerd-2.2`. Those removals are intentional (2.x moved registry config out of the CRI plugin), so drift needs an allowlist or explanation mechanism.
