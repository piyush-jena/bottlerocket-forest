<!-- Audit of shipped settings, 2026-11-17, against core-kit a4f438b1f, settings-sdk 06d9d1a, bottlerocket b7c6c274,
     and the EKS-D sources packaged in core-kit for Kubernetes 1.31-1.37 (containerd 1.7/2.2/2.3).
     Line numbers drift; re-run scripts/k8s-field-report.py before relying on a citation.
     Status of the findings as of this date: see ../../SKILL.md "Known open findings". -->

# pods-runtime

Scope: `settings.kubernetes.ids-per-pod`, `settings.kubernetes.static-pods-enabled`, `settings.kubernetes.container-runtime-endpoint`.
Upstream citations are `<minor>:<path>:<line>` relative to the cached EKS-D `src/` for that minor (1.31.14, 1.32.13, 1.33.13, 1.34.12, 1.35.9, 1.36.5, 1.37.1).
Grove paths are relative to `/home/fedora/Repositories/bottlerocket-forest/groves/k8s-settings`.
Scratch probes I wrote (not upstream code) are in a scratch probe (not kept).

Facts about the node that matter for all three settings:

- Every k8s variant 1.31-1.37 ships `containerd-2.3` (2.3.7) and runc 1.3.6 (`bottlerocket/variants/*k8s*/Cargo.toml`, `kits/bottlerocket-core-kit/packages/runc/runc.spec:5`).
- Kernels: 6.1 for 1.31/1.32 and also for `aws-k8s-1.33-fips` and `vmware-k8s-1.33-fips` (`bottlerocket/variants/aws-k8s-1.33-fips/Cargo.toml:25`, `vmware-k8s-1.33-fips/Cargo.toml:38`), 6.12 for the other 1.33-1.35 variants and the 1.36 FIPS variants, 6.18 for the other 1.36/1.37 variants.
- There is no `kubelet` user (only the users in `kits/bottlerocket-core-kit/packages/*/*-sysusers.conf`: chrony, dbus, tss, plus groups) and no `getsubids`/shadow-utils package, so no `/etc/subuid`/`/etc/subgid` for kubelet.
- Settings changes run `systemctl try-restart kubelet.service` (`bottlerocket/sources/shared-defaults/kubernetes-services.toml:15-17`). thar-be-settings runs `systemctl daemon-reload` for anything it writes under `/etc/systemd/` (`kits/bottlerocket-core-kit/sources/api/thar-be-settings/src/config.rs:108-143,204-206`), so changes to `exec-start.conf` do take effect on restart.
- `/var/lib/kubelet` lives on persistent storage and is not wiped at boot. Only `cpu_manager_state` is removed (`kits/bottlerocket-core-kit/packages/kubernetes-1.35/kubernetes-tmpfiles.conf`, `prepare-var-lib-kubelet.service`).
- kubelet unit: `Restart=always`, `RestartSec=5`, `BindsTo=containerd.service` (`packages/kubernetes-1.35/kubelet.service:4-6,17-19`).

---

## settings.kubernetes.ids-per-pod

### Upstream per version

| version | exists | JSON path, Go type | upstream default | validation (kubelet refuses to start) | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | no | - | fixed 65536 per pod (`1.31:pkg/kubelet/userns/userns_manager.go:43`) | - | UserNamespacesSupport Beta/false (`1.31:pkg/features/kube_features.go:1228`) | not rendered by BR |
| 1.32 | no | - | fixed 65536 | - | Beta/false (`1.32:pkg/features/versioned_kube_features.go:801-804`) | not rendered by BR |
| 1.33 | yes | `userNamespaces.idsPerPod` `*int64` (`1.33:staging/src/k8s.io/kubelet/config/v1beta1/types.go:928,1136`) | 65536 (`1.33:pkg/kubelet/config/defaults.go:33`), no v1beta1 defaulting, so configz omits it when unset | `>= 65536`, `% 65536 == 0`, `<= MaxUint32` (`1.33:pkg/kubelet/apis/config/validation/validation_linux.go:44-55`), called unconditionally (`validation.go:328`) | Beta/true (`1.33:pkg/features/kube_features.go:1838-1842`). The field tag misspells it `UserNamespaceSupport` (`types.go:1134`) | **The value is validated, then ignored at runtime**, see below |
| 1.34 | yes | same (`1.34:.../types.go:928,1136`) | 65536 (`1.34:pkg/kubelet/config/defaults.go:33`) | same (`1.34:.../validation_linux.go:44-55`) | Beta/true (`1.34:pkg/features/kube_features.go:1841-1845`) | **The value is validated, then ignored at runtime** |
| 1.35 | yes | same (`1.35:.../types.go:928,1136`) | 65536 (`1.35:pkg/kubelet/kubeletconfig/defaults.go:33`) | same (`1.35:.../validation_linux.go:44-55`, `validation.go:331`) | Beta/true (`1.35:pkg/features/kube_features.go:1894-1898`) | Honored. Default mapping depends on the value (see below) |
| 1.36 | yes | same (`1.36:.../types.go:961,1168`), featureGate tag removed | 65536 (`1.36:.../kubeletconfig/defaults.go:34`) | same (`1.36:.../validation_linux.go:43-54`, `validation.go:334`) | GA/true locked (`1.36:pkg/features/kube_features.go:2093-2097`) | Honored |
| 1.37 | yes | same (`1.37:.../types.go:967,1174`) | 65536 (`1.37:.../kubeletconfig/defaults.go:34`) | same (`1.37:.../validation_linux.go:43-54`, `validation.go:362`) | GA/true locked (`1.37:pkg/features/kube_features.go:2259-2263`) | Honored. The upstream fix for the "range ends at 2^32-1" bug is not in 1.37.1 |

### What changes between versions

- 1.31/1.32: the field does not exist and the per-pod length is a hard-coded 65536 (`1.31:pkg/kubelet/userns/userns_manager.go:43`). The gate is off by default.
- 1.33: the field and its validation are added and the gate turns on by default (`1.33:pkg/features/kube_features.go:1841`).
- **1.33 and 1.34 ignore the value.** `MakeUserNsManager` reads it through `GetUserNamespacesIDsPerPod()`, and that getter reads `kl.kubeletConfiguration.UserNamespaces` (`1.33:pkg/kubelet/kubelet_getters.go:144-156`, `1.33:pkg/kubelet/userns/userns_manager.go:137`). But the manager is built at `1.33:pkg/kubelet/kubelet.go:1050`, and `klet.kubeletConfiguration = *kubeCfg` is only assigned at `kubelet.go:1058` (1.34: built at `kubelet.go:1081`, assigned at `:1090`). So the getter always sees nil and returns 65536.
  - Upstream bug kubernetes#133144, fixed only in 1.35 by kubernetes#133373 ("The kubelet now honors the configuration userNamespaces.idsPerPod. Before it was ignored").
  - The bug is still present in the packaged 1.33.13 and 1.34.12.
  - Because the value is never used, the user-namespace manager's own checks (`userns_manager.go:139-154`) always run with 65536 and always pass.
- 1.35: the value is passed directly into `MakeUserNsManager(logger, klet, usernsIDsPerPod)` (`1.35:pkg/kubelet/kubelet.go:1110-1114`).
  - With no kubelet user (the Bottlerocket case), the default mapping becomes `firstID = idsPerPod` and `len = 2^32 - idsPerPod` (`1.35:pkg/kubelet/kubelet_pods.go:130-137`). In 1.33/1.34 it was `firstID = 65536`, `len = 2^32 - 65536` (`1.33:pkg/kubelet/kubelet_pods.go:127-128`).
  - The manager then requires `len % idsPerPod == 0` and `len / idsPerPod >= maxPods` (`1.35:pkg/kubelet/userns/userns_manager.go:160,163`). With that default mapping, this holds only when idsPerPod is a power of two and `2^32/idsPerPod - 1 >= maxPods`.
  - In 1.35 the manager is not created at all when the gate is off (`userns_manager.go:134`).
- 1.35+: on startup, kubelet re-reads the per-pod `userns` file of every pod directory under `/var/lib/kubelet/pods` (`1.37:pkg/kubelet/userns/userns_manager.go:177-190`, file name `userns` at `1.35:.../userns_manager.go:87`). It refuses to start if any recorded length differs from the current idsPerPod (`1.37:.../userns_manager.go:241-244`; error `record pod mappings for existing pod %q` at `:188`).
  - Upstream considers this intended: kubernetes#137930 says "the kubelet failing is the right thing".
- 1.36: the gate is GA and locked on. The field comment drops the featureGate tag.
- Not in the packaged sources:
  - kubernetes#141345, cherry-picked to release-1.35/1.36/1.37 on 2026-10-29 as #143213-#143215. It shrinks the default range by one block (`len = 2^32 - 2*idsPerPod`) so that no pod is given the range ending at 2^32-1.
  - The same PR fixes "kubelet user exists but getsubids missing" (`os.IsNotExist` is replaced by `errors.Is(err, exec.ErrNotFound)`).
  - All of 1.35.9, 1.36.5 and 1.37.1 still have `defaultLen := uint32((1 << 32) - uint64(defaultFirstID))` (`1.37:pkg/kubelet/kubelet_pods.go:140`).

Runtime prerequisites for `hostUsers: false` at all, independent of ids-per-pod:

- **Gate.** The kubelet gate is on by default from 1.33 (table above). On 1.31/1.32 kubelet rejects `hostUsers` with "the feature gate ... is disabled: can't set spec.HostUsers" (`1.31:pkg/kubelet/userns/userns_manager.go:398`). The API server gate must also be on.
- **Runtime support.** kubelet allows a userns pod only if the CRI runtime handler reports `UserNamespaces` (`1.35:pkg/kubelet/userns/userns_manager.go:426-435`, `1.33:pkg/kubelet/kubelet_getters.go:121-133`).
  - containerd 2.3 sets that flag only if the runc `features` output contains the `user` namespace and `mountExtensions.idmap.enabled` (`containerd-2.3.7/internal/cri/server/service.go:440,503-518`).
  - runc 1.3.6 is at least 1.2, so this should be true (inferred; check with `runc features` on a node).
  - containerd 1.7 does not report runtime handlers at all (no `RuntimeHandlers` in `containerd-1.7.36/pkg/cri`). This is moot because no k8s variant uses 1.7.
- **Kernel.**
  - idmap mounts on tmpfs need Linux 6.3 (containerd comment `containerd-2.3.7/internal/cri/server/container_create.go:1220-1221`; the kubernetes.io user-namespaces page lists Linux 6.3 as the minimum).
  - kubelet mounts projected and secret volumes on tmpfs. So on the 6.1-kernel 1.33 FIPS variants, userns pods with a service-account token volume will likely fail at container start (inferred, not run).
  - No kubelet code checks the kernel version (none found in `1.33:pkg/kubelet`).
- **Snapshotter.** For snapshotters without the `remap-ids` capability, containerd falls back to a chowned copy of the snapshot (`containerd-2.3.7/client/snapshotter_opts_unix.go:62-110`). So `soci` should work, but more slowly (inferred).
- **subuid/subgid.** Not needed on Bottlerocket. With no `kubelet` user, `user.Lookup` returns UnknownUserError and kubelet uses the default mapping (`1.37:pkg/kubelet/kubelet_pods.go:152-158`). If someone added a `kubelet` user without `getsubids`, the packaged 1.33-1.37 kubelet would fail to start: `exec.LookPath` returns `exec.ErrNotFound`, which `os.IsNotExist` does not match (`1.37:pkg/kubelet/kubelet_pods.go:164-170`; fixed only by #141345).

### Bottlerocket implementation

- **Model**
  - Field: `ids_per_pod: KubernetesIdsPerPodValue` (`bottlerocket-settings-sdk/bottlerocket-settings-models/settings-extensions/kubernetes/src/lib.rs:106`).
  - Type: `i64`, accepted when `input % 65536 == 0 && input < (1i64 << 32)` (`bottlerocket-settings-sdk/bottlerocket-settings-models/modeled-types/src/kubernetes.rs:1598-1617`). The unit tests accept `0` and `4294901760` (`:1632`).
  - BR accepts but kubelet rejects (node never joins), all of 1.33-1.37:
    - Any negative multiple of 65536, for example `-65536`. Rust `%` gives 0 and the value is `< 2^32`. Handlebars `#if` is truthy for any non-zero number (`~/.cargo/registry/src/*/handlebars-4.5.0/src/json/value.rs:148-157`, `is_normal()`), so it renders as `idsPerPod: -65536` and kubelet fails with "userNamespaces.idsPerPod must not be less than 65536".
  - BR accepts, kubelet's config validation also accepts, but the kubelet build used by Bottlerocket refuses to start (1.35-1.37 only):
    - Any multiple that is not a power of two. For example, `196608` fails with "create user namespace manager: kubelet user assigned IDs length 4294770688 is not a multiple of 196608" (`1.35:pkg/kubelet/userns/userns_manager.go:160`); `327680` and `4294901760` fail the same way.
    - Any power of two with `2^32/N - 1 < max-pods`. For example `N = 67108864` (2^26) gives 63 slots, which fails for max-pods 110 with "kubelet user assigned IDs are not enough to support 110 pods" (`:163`).
    - pluto takes max-pods straight from `packages/os/eni-max-pods`, which goes up to 1514. At 1514 the largest working value is 2^21.
    - Arithmetic from a scratch probe (not kept) (python one-liner in my transcript): 65536 gives 65535 slots, 131072 gives 32767, 2^24 gives 255, 2^25 gives 127.
  - On 1.33/1.34, every value that passes kubelet validation is accepted and silently ignored.
  - kubelet accepts but BR rejects: none. Both cap at 4294901760.
  - `0` is accepted by BR and not rendered (`{{#if}}` skips 0), so it means "unset". Kubelet would reject it if rendered.
- **Templates**
  - Rendered as `{{#if settings.kubernetes.ids-per-pod}}` then `userNamespaces:` and `  idsPerPod: {{...}}` (an unquoted YAML int) at:
    - `kits/bottlerocket-core-kit/packages/kubernetes-1.33/kubelet-config:228-231`
    - `1.34/kubelet-config:226-229`
    - `1.35/kubelet-config:235-238`
    - `1.36/kubelet-config:223-226`
    - `1.37/kubelet-config:229-232`
  - Behavior: unset or 0 renders nothing. Negative values render (see the bug below). No featureGates entry is needed.
  - Not rendered on 1.31/1.32, which is correct because the field does not exist there. The setting is still accepted by the API on those variants, so it is a silent no-op.
  - History: core-kit #689 (Bottlerocket v1.51.0) rendered a root-level `idsPerPod:` (scratch copy, not kept). kubelet decodes leniently, so it ignored the key, and the settings-sdk #104 test "Node joined the cluster" passed for that reason.
  - core-kit #1060 (core-kit 17.1.0, Bottlerocket v1.67.0, `bottlerocket/CHANGELOG.md` v1.67.0 entry) fixed the path. Its "Testing done" section is empty.
  - `kubelet-config-lint.py` now reports every rendered path as existing upstream.
- **Migration and docs**
  - Migration: `bottlerocket/sources/settings-migrations/v1.51.0/kubernetes-additional-settings/src/main.rs:14` (AddSettingsMigration), registered at `bottlerocket/Release.toml:451`. Present.
  - Docs: `bottlerocket-project-website/data/settings/1.51.x/kubernetes.toml:19-26` only says "Number of UIDs/GIDs allocated for each user namespace... only available for Kubernetes 1.33 and later". It does not mention:
    - the constraints;
    - that the setting has no effect on 1.33/1.34;
    - the power-of-two and max-pods relation;
    - that changing it with userns pods present stops kubelet.

### How to verify it works on a node

Pod used in all cases (pin it to the node under test):

```yaml
apiVersion: v1
kind: Pod
metadata: {name: userns-test}
spec:
  nodeName: NODE
  hostUsers: false
  restartPolicy: Never
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:latest
    command: ["sh", "-c", "cat /proc/self/uid_map /proc/self/gid_map; id; sleep 3600"]
```

Steps:

1. Check prerequisites, before setting anything:

   ```
   kubectl get node $NODE -o jsonpath='{.status.runtimeHandlers}'
   ```

   On 1.33+ expect `userNamespaces:true` for `""` and `runc`, set by `1.33:pkg/kubelet/nodestatus/setters.go:521-538`. In `sheltie`, run `runc features | jq .linux.mountExtensions.idmap` and expect `{"enabled":true}`.
2. Set the value on a node with no `hostUsers: false` pods, either in user-data `[settings.kubernetes] ids-per-pod = 131072` or with `apiclient set settings.kubernetes.ids-per-pod=131072`. Then check:
   - `sheltie; grep -A1 '^userNamespaces' /etc/kubernetes/kubelet/config` shows `idsPerPod: 131072`.
   - `kubectl get --raw /api/v1/nodes/$NODE/proxy/configz | jq .kubeletconfig.userNamespaces` shows `{"idsPerPod":131072}` on 1.33-1.37. **This is not proof of effect on 1.33/1.34.**
3. Apply the pod, then run `kubectl logs userns-test`. Each uid_map line reads inside-ID, host-ID, length. Expected first line:

   | case | 1.33 / 1.34 | 1.35 / 1.36 / 1.37 |
   |---|---|---|
   | setting unset (A) | `0 65536 65536` | `0 65536 65536` |
   | `ids-per-pod=131072` (B) | `0 65536 65536` (ignored, the upstream bug) | `0 131072 131072` |

   - Rule: host-ID is `(slot + 1) * length`, so the second userns pod gets `0 196608 65536` or `0 262144 131072`.
   - A `hostUsers`-default pod shows `0 0 4294967295`.
   - On 1.31/1.32 with the API server gate off, the field is dropped and you see `0 0 4294967295`. With it on, kubelet emits a `can't set spec.HostUsers` event.
4. Host-side check in `sheltie`:
   - `cat /var/lib/kubelet/pods/<podUID>/userns` shows JSON with `"length":131072`.
   - Get the container PID with `crictl --runtime-endpoint unix:///run/containerd/containerd.sock inspect <ctr> | jq .info.pid`, then `cat /proc/$PID/uid_map` (same three numbers) and `ps -o uid= -p $PID` (host UID 131072).
5. Negative checks on 1.35+, reverting after each:
   - `ids-per-pod=196608`: `journalctl -u kubelet | grep 'create user namespace manager'` shows the "not a multiple of" error, and the node goes NotReady.
   - `ids-per-pod=-65536`: `apiclient` accepts it (bug), and the journal shows "must not be less than 65536".
   - With the step 3 pod still present, change the value: the journal shows "record pod mappings for existing pod ... wrong user namespace length 131072".
6. Cost: about 5 min to launch a node, plus about 1 min per setting change and pod. Doing all versions in parallel takes about 15 min.
7. Matching upstream tests:
   - `test/e2e_node/user_namespaces_test.go` "honors idsPerPod in userns pods" (1.35+, `1.35:test/e2e_node/user_namespaces_test.go:108-150`, uses 131072 and reads field 3 of `/proc/self/uid_map`; skips if a `kubelet` user has mappings).
   - The gate-off test at `:56-105`.
   - The `HostUsers` uid_map checks in `test/e2e/common/node/security_context.go:66-280`.

### Findings

- [bug] **ids-per-pod has no effect on 1.33/1.34.**
  - Evidence: on aws-k8s-1.33/1.34, `ids-per-pod=131072` renders correctly and shows in configz, but pods get 65536 IDs. The manager is built before the config is stored (`1.33:pkg/kubelet/kubelet.go:1050` vs `:1058`; `1.34:pkg/kubelet/kubelet.go:1081` vs `:1090`). This is upstream kubernetes#133144, fixed in 1.35 by #133373 and not present in 1.33.13/1.34.12.
  - Fix: state in the docs that the setting takes effect only from 1.35. Optionally stop rendering it on 1.33/1.34, or carry the #133373 patch, which changes behavior and so needs the same release notes as 1.35.
- [bug] **The model accepts negative values, and kubelet then fails to start.**
  - Evidence: `apiclient set settings.kubernetes.ids-per-pod=-65536` passes `modeled-types/src/kubernetes.rs:1611-1614`. It is rendered by `kubelet-config:235-238` (1.35) because `#if` treats non-zero numbers as true. kubelet then fails validation at `validation_linux.go:46-47`. All 1.33-1.37; the node never joins.
  - Fix: `ensure!(input >= 65536 && input % 65536 == 0 && input <= 4294901760)`. Decide whether 0 is rejected or kept as "unset" and document the choice.
- [bug] **On 1.35-1.37, most values that pass validation stop kubelet on Bottlerocket.**
  - Evidence: Bottlerocket has no `kubelet` user, so kubelet uses the default mapping `firstID = N`, `len = 2^32 - N` (`1.35:pkg/kubelet/kubelet_pods.go:130-137`). With that mapping:
    - Non-power-of-two multiples (196608, 327680, ...) fail `userns_manager.go:160`.
    - Powers of two with `2^32/N - 1 < max-pods` fail `:163`; for max-pods 110 that is anything above 2^25.
    - The error is `failed to run Kubelet: create user namespace manager: ...` (`kubelet.go:1114-1116`), and the node never joins.
  - Fix:
    - Restrict the model to powers of two from 2^16 to 2^24. That is safe for max-pods up to 255 before #141345 and 254 after it.
    - Document `ids-per-pod * (max-pods + 2) <= 2^32`. This is the post-#141345 rule and is safe for both.
    - Or validate across settings in a generator.
    - Note in the docs that this applies to 1.35+.
- [risk] **Changing the value with userns pods on disk stops kubelet (1.35-1.37).**
  - Evidence: kubelet re-reads `/var/lib/kubelet/pods/*/userns` at startup and rejects any length mismatch (`1.37:pkg/kubelet/userns/userns_manager.go:185-189,241-244`). `/var/lib/kubelet` persists across reboots, and Bottlerocket restarts kubelet on every `apiclient set`. Two concrete triggers:
    1. `apiclient set settings.kubernetes.ids-per-pod=131072` on a live node that has a `hostUsers: false` pod. kubelet crash-loops every 5 s until the pod directories are removed.
    2. A 1.35/1.36/1.37 node that had `ids-per-pod` (not 65536) set while it was still a no-op (Bottlerocket v1.51.0-v1.66.x, root-level key), running userns pods, and updated to v1.67.0 or later (#1060). After the reboot, kubelet sees length 65536 on disk against the new value and fails. This is inferred from source, not reproduced.
  - Fix: document "drain userns pods before changing ids-per-pod". Consider a v1.67.0 release note, or rejecting live changes.
- [risk] **The packaged 1.35.9/1.36.5/1.37.1 can hand a pod the range ending at 2^32-1**, which the kernel treats as an invalid ID. It is reachable only when `2^32/N - 1` is close to max-pods.
  - When the cherry-picks #143213-#143215 land in a patch bump, each value loses one slot. For example 2^25 with max-pods 127 will stop working.
  - Fix: pick up the patch release and use the `(max-pods + 2)` rule above.
- [risk] **User namespaces probably do not work on aws-k8s-1.33-fips and vmware-k8s-1.33-fips** (kernel 6.1; tmpfs idmap needs 6.3). Inferred from the containerd comment `container_create.go:1220-1221` and kubernetes.io; not run.
  - Fix: verify on a node and document, or move those variants to 6.12.
- [nit] Accepted on 1.31/1.32 but never rendered (silent no-op). `0` silently means "unset". The website entry has no constraints or version caveats.
- [nit] The core-kit #1060 PR had no testing. The settings-sdk #104 test showed root-level rendering and "node joined", which tested nothing. The verification above should become the bar.

---

## settings.kubernetes.static-pods-enabled

### Upstream per version

| version | exists | JSON path / flag, Go type | upstream default | validation | gate | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `staticPodPath` `string` (`1.31:staging/src/k8s.io/kubelet/config/v1beta1/types.go:100`); deprecated flag `--pod-manifest-path` (`1.31:cmd/kubelet/app/options/options.go:364`) | `""`, meaning no file source (no entry in `v1beta1/defaults.go`) | none | none | file source added only `if kubeCfg.StaticPodPath != ""` (`1.31:pkg/kubelet/kubelet.go:303-305`) |
| 1.32 | yes | `types.go:100` | `""` | none | none | `1.32:pkg/kubelet/kubelet.go:341-343` |
| 1.33 | yes | `types.go:119` | `""` | none | none | `1.33:pkg/kubelet/kubelet.go:375-377` |
| 1.34 | yes | `types.go:119` | `""` | none | none | `1.34:pkg/kubelet/kubelet.go:376-378` |
| 1.35 | yes | `types.go:119` | `""` | none | none | `1.35:pkg/kubelet/kubelet.go:383-385` |
| 1.36 | yes | `types.go:131` | `""` | none | none | `1.36:pkg/kubelet/kubelet.go:385-387` |
| 1.37 | yes | `types.go:131` | `""` | none | none | `1.37:pkg/kubelet/kubelet.go:388-390` |

### What changes between versions

None that matter. Only the logging call changes (`klog.InfoS` becomes `logger.Info` in 1.36). The log message "Adding static pod path" is the same in every version and is logged at the default verbosity.

### Bottlerocket implementation

- **Model:** `static_pods_enabled: bool` (`settings-extensions/kubernetes/src/lib.rs:99`). Any bool is valid upstream. There is nothing to compare.
- **Templates:** every version uses the same block:

  ```
  {{#if_not_null settings.kubernetes.static-pods-enabled}}
  {{#if settings.kubernetes.static-pods-enabled}}
  staticPodPath: "/etc/kubernetes/static-pods/"
  {{/if}}
  {{else}}
  staticPodPath: "/etc/kubernetes/static-pods/"
  {{/if_not_null}}
  ```

  - Locations: `kubernetes-1.31/kubelet-config:162-168`, `1.32:166-172`, `1.33:169-175`, `1.34:167-173`, `1.35:175-181`, `1.36:163-169`, `1.37:163-169`.
  - The `{{else}}` belongs to `if_not_null`, because the inner `#if` is closed first. `if_not_null` takes the inverse branch only for null or missing values (`kits/bottlerocket-core-kit/sources/api/schnauzer/src/helpers/stdlib/mod.rs:693-703`; tests at `:726-782`).
  - Result: unset renders the path, `true` renders the path, `false` renders nothing, so kubelet's default is `""` and it adds no file source. The path is a quoted YAML string.
  - core-kit #641 tested all three cases on a node. Correct in every version; there are no versions that support it but don't render it, or vice versa.
- **Interactions:**
  - `/etc/kubernetes/static-pods` is created by tmpfiles, and `/etc/kubernetes/manifests` is symlinked to it (`packages/kubernetes-1.35/kubernetes-tmpfiles.conf`).
  - The `static-pods` agent writes `settings.kubernetes.static-pods.<name>` manifests into that directory regardless of `static-pods-enabled` (`kits/bottlerocket-core-kit/sources/static-pods/src/main.rs:31,117-149`; the service is restarted only on `settings.kubernetes.static-pods` changes, `bottlerocket/sources/shared-defaults/kubernetes-services.toml:72-77`).
  - So with `static-pods-enabled=false`, configured static pods are written but never run, with no warning.
  - No Bottlerocket default static pod exists.
  - On toggling to false: kubelet restarts with no file source. Its housekeeping then removes the now-orphaned mirror pods and pods (`1.35:pkg/kubelet/kubelet_pods.go:1315`; the end-to-end outcome is inferred).
- **Migration and docs**
  - Migration: `bottlerocket/sources/settings-migrations/v1.46.0/kubernetes-static-pods-enabled-setting/src/main.rs:8-10`, registered at `Release.toml:438`. Present.
  - On a downgrade below 1.46.0 the key is removed and static pods turn back on, which is expected for AddSettingsMigration.
  - Docs: **missing**. There is no `static-pods-enabled` anywhere in `bottlerocket-project-website/`.

### How to verify it works on a node

1. Create a static pod with the setting unset (A):

   ```
   M=$(printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: sp-test\n  namespace: default\nspec:\n  containers:\n  - name: c\n    image: public.ecr.aws/docker/library/busybox:latest\n    command: ["sleep","3600"]\n' | base64 -w0)
   apiclient set settings.kubernetes.static-pods.sp-test.enabled=true settings.kubernetes.static-pods.sp-test.manifest="$M"
   kubectl get pod -n default sp-test-$NODE -o jsonpath='{.metadata.annotations.kubernetes\.io/config\.source}'
   ```

   Expect `file`.
2. Disable static pods (B): `apiclient set settings.kubernetes.static-pods-enabled=false`. Then check:
   - `sheltie; grep staticPodPath /etc/kubernetes/kubelet/config` prints nothing.
   - `kubectl get --raw /api/v1/nodes/$NODE/proxy/configz | jq -r '.kubeletconfig.staticPodPath // "unset"'` prints `unset`. In A it prints `/etc/kubernetes/static-pods/`.
   - `ls /etc/kubernetes/static-pods/` still shows `sp-test`, which proves that the file is ignored rather than missing.
   - `journalctl -u kubelet -b | grep 'Adding static pod path'` has no entry after the last restart.
   - `kubectl get pod -n default sp-test-$NODE` becomes NotFound within about 1 min.
   - `crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps --name c` is empty.
3. Set `true` and the pod comes back. The expected results are the same for 1.31 through 1.37.
4. Cost: about 5 min to launch, plus about 2 min.
5. Upstream tests: `test/e2e_node/mirror_pod_test.go` (all versions) and `test/e2e_node/static_pod_test.go` (1.36+).

### Findings

- [risk] **`static-pods-enabled=false` silently disables `settings.kubernetes.static-pods`.**
  - Evidence: the manifests are still written by `static-pods/src/main.rs:117-149`, and kubelet has no file source.
  - In standalone mode (`settings.kubernetes.standalone-mode=true`) this leaves a node that runs nothing.
  - Fix: document the interaction. Optionally have the static-pods agent log a warning when static pods are disabled.
- [nit] The setting is not documented on the website (it shipped in v1.46.0).
- No template bugs: unset, true and false are correct in every version.

---

## settings.kubernetes.container-runtime-endpoint

### Upstream per version

| version | exists | JSON path / flag, Go type | upstream default | validation | gate | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | flag `--container-runtime-endpoint` (`1.31:cmd/kubelet/app/options/options.go:376`), deprecated as a config-file flag (`options.go:339-356`); field `containerRuntimeEndpoint string` (`1.31:staging/src/k8s.io/kubelet/config/v1beta1/types.go:848`) | `unix:///run/containerd/containerd.sock` (`1.31:pkg/kubelet/apis/config/v1beta1/defaults.go:283-284`) | non-empty (`1.31:pkg/kubelet/apis/config/validation/validation.go:284`). At connect time: Linux allows unix sockets only, and a string with no scheme is retried as `unix://` + string (`1.31:staging/src/k8s.io/cri-client/pkg/util/util_unix.go:81-124`) | none | flag beats config file and drop-ins (`1.35:cmd/kubelet/app/server.go:222,231`); `imageServiceEndpoint` falls back to this value (`1.31:pkg/kubelet/kubelet.go:324-325`) |
| 1.32 | yes | flag `options.go:376`; field `types.go:859` | same (`defaults.go:301-302`) | `validation.go:325`; `util_unix.go` identical | none | `kubelet.go:362` |
| 1.33 | yes | flag `options.go:376`; field `types.go:908` | `defaults.go:304-305` | `validation.go:352`; identical | none | `kubelet.go:396` |
| 1.34 | yes | flag `options.go:367`; field `types.go:908` | `defaults.go:304-305` | `validation.go:348`; identical | none | `kubelet.go:397` |
| 1.35 | yes | flag `options.go:377`; field `types.go:908` | `defaults.go:304-305` | `validation.go:351`; identical | none | `kubelet.go:404` |
| 1.36 | yes | flag `options.go:379`; field `types.go:942` | `defaults.go:308-309` | `validation.go:365`; identical | none | `kubelet.go:406` |
| 1.37 | yes | flag `options.go:379`; field `types.go:948` | `defaults.go:303-304` | `validation.go:394`; `util_unix.go:80-123` identical | none | `kubelet.go:409-421` (builder) |

Connecting to the endpoint: kubelet calls `Version()` on startup and returns `validate service connection: validate CRI v1 runtime API for endpoint %q` on failure (`1.35:staging/src/k8s.io/cri-client/pkg/remote_runtime.go:84-139,157-167`), which ends with `failed to run Kubelet` (`1.35:cmd/kubelet/app/server.go:533`).

### What changes between versions

- None for the endpoint flag or field. Endpoint parsing is byte-identical from 1.31 to 1.37.
- The flag is a deprecated KubeletConfiguration flag in every version and prints "Flag --container-runtime-endpoint has been deprecated, This parameter should be set via the config file...".
- Related flag in the same template: cadvisor's `--containerd` exists, deprecated, in 1.31-1.36 (`1.31:cmd/kubelet/app/options/globalflags_linux.go:52`, `1.36:...:51`) and is gone in 1.37. Bottlerocket correctly drops it from the 1.37 template.

### Bottlerocket implementation

- **Model:** `container_runtime_endpoint: Url` (`settings-extensions/kubernetes/src/lib.rs:108`).
  - `Url` (`modeled-types/src/shared.rs:508-540`) rejects control characters. It then accepts anything that `url::Url` parses, or that parses after prefixing `http://`.
  - I ran a replica of that logic against url 2.5.8 (a scratch probe (not kept)) and a replica of kubelet's `parseEndpointWithFallbackProtocol` plus the unix-only check (a scratch probe (not kept), net/url).

  | input | Bottlerocket | kubelet (Linux, all versions) |
  |---|---|---|
  | `unix:///run/containerd/containerd.sock`, `unix:///run/x.sock`, `unix:/run/x.sock`, `/run/x.sock` | accept | ok, dials the given path |
  | `unix://run/x.sock`, `run/x.sock` | accept | dials `/x.sock` (host `run` is dropped), so it fails to connect |
  | `tcp://127.0.0.1:9000` | accept | "only support unix socket endpoint" |
  | `https://example.com`, `npipe:////./pipe/runtime`, `localhost:8080` | accept | "protocol %q not supported" |
  | `example.com`, `unix://` | accept | empty dial address, so it fails to connect |
  | `unix:///run/a b.sock`, `unix:///run/a%20b.sock`, `unix:///run/$X.sock` | accept | see the systemd quoting bug below |
  | `""` | reject | (kubelet would use its default) |

  - Every "fails" row means kubelet exits and systemd restarts it every 5 s, so the node never joins.
  - kubelet accepts but Bottlerocket rejects: nothing realistic.
- **Templates:**
  - `--container-runtime-endpoint={{default "unix:///run/containerd/containerd.sock" settings.kubernetes.container-runtime-endpoint}} \` at `kits/bottlerocket-core-kit/packages/kubernetes-1.3{1..7}/kubelet-exec-start-conf:18`, rendered to `/etc/systemd/system/kubelet.service.d/exec-start.conf`.
  - Unset renders the containerd default.
  - The value is unquoted inside a systemd `ExecStart=`. The `default` helper writes the raw string with no escaping (`schnauzer/src/helpers/stdlib/mod.rs:517-577`).
  - All versions that support the flag render it. There is no config-field rendering.
  - The 1.31-1.36 templates also pass `--containerd=/run/containerd/containerd.sock` (`:19`) and every version passes `--runtime-cgroups=/runtime.slice/containerd.service`. Both are fixed to containerd.
- **Things that do not follow the setting:**
  - containerd always listens on `/run/containerd/containerd.sock`, and no setting changes it (`packages/containerd-2.3/containerd-config-toml_k8s_containerd_sock:22-23`).
  - The pause image is imported into that containerd by `ctr` in ExecStartPre (`packages/kubernetes-1.35/prestart-load-pause-ctr.conf`) and pinned in its config (`containerd-config-toml_k8s_containerd_sock:29-30`).
  - `kubelet.service` `BindsTo=containerd.service`.
  - `/run/dockershim.sock` is symlinked to containerd (`dockershim-symlink.conf`).
  - With `settings.container-runtime.snapshotter=soci`, a config.d drop-in sets `imageServiceEndpoint: unix:///run/soci-snapshotter/soci-snapshotter.sock` (`kits/bottlerocket-core-kit/packages/soci-snapshotter/k8s-snapshotter-conf:8-12`). Image calls then bypass the custom endpoint.
  - There is no `/etc/crictl.yaml` (`packages/cri-tools/cri-tools.spec`), so `crictl` keeps using containerd's socket.
  - The image credential provider does not use the endpoint.
  - Practical result: a non-default endpoint only works if it is a CRI proxy in front of the same containerd that exists before kubelet starts. There is no ordering dependency. SELinux labels on the socket may also matter (inferred).
- **Migration and docs**
  - Migration: `bottlerocket/sources/settings-migrations/v1.64.0/kubernetes-container-runtime-endpoint/src/main.rs:8-10`, registered at `Release.toml:479`. Present.
  - Docs: **missing** from the website.

### How to verify it works on a node

1. **A/B with the same runtime through a different path.**
   - Set `apiclient set settings.kubernetes.container-runtime-endpoint=unix:///run/dockershim.sock`. That symlink is recreated by ExecStartPre before kubelet starts.
   - `sheltie; tr '\0' '\n' < /proc/$(pidof kubelet)/cmdline | grep runtime-endpoint` shows `--container-runtime-endpoint=unix:///run/dockershim.sock`.
   - `kubectl get --raw /api/v1/nodes/$NODE/proxy/configz | jq -r .kubeletconfig.containerRuntimeEndpoint` shows the new value. On the A node it shows `unix:///run/containerd/containerd.sock`.
   - The node stays Ready.
   - `journalctl -u kubelet -b | grep 'container-runtime-endpoint has been deprecated'` shows the deprecation line.
2. **Negative check, which proves kubelet dials the configured path.**
   - Set `apiclient set settings.kubernetes.container-runtime-endpoint=unix:///run/nonexistent.sock`.
   - `journalctl -u kubelet | grep 'validate CRI v1 runtime API for endpoint "unix:///run/nonexistent.sock"'` matches.
   - `systemctl status kubelet` shows it restarting, and the node goes NotReady after the node-monitor grace period.
   - Revert. Repeat with `tcp://127.0.0.1:1` and expect "only support unix socket endpoint".
   - Repeat with `unix:///run/a%20b.sock` and expect `systemctl status kubelet` to report a bad unit setting.
3. **Optional: a real different endpoint** (inferred, not run).
   - Run a forwarding proxy, for example `socat -v UNIX-LISTEN:/.bottlerocket/rootfs/mnt/cri.sock,fork UNIX-CONNECT:/.bottlerocket/rootfs/run/containerd/containerd.sock` in the admin container. `/.bottlerocket/rootfs/mnt` is the only rw/rshared host bind (`kits/bottlerocket-core-kit/sources/host-ctr/cmd/host-ctr/main.go:822-827`).
   - Set the endpoint to `unix:///mnt/cri.sock`. Pod create and delete traffic should then appear in socat's `-v` output.
   - Watch for SELinux AVCs in the journal.
   - `kubectl get node $NODE -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}'` reports whatever answered `Version()`.
4. The expected results are the same for 1.31 through 1.37. Cost: about 5 min to launch, plus about 1 min per value.
5. Upstream pattern: `test/e2e_node/criproxy_test.go` with `1.35:test/e2e_node/e2e_node_suite_test.go:255-266`, which points `ContainerRuntimeEndpoint` and `ImageServiceEndpoint` at a proxy socket (`criproxy/endpoint.go:26`).

### Findings

- [bug] **`Url` accepts endpoints kubelet cannot use, so the node never joins.**
  - Evidence: `tcp://...`, `https://...`, `npipe://...`, `localhost:8080`, `example.com`, `unix://`, and relative `unix://run/x.sock` all pass `shared.rs:515-539` and all fail in kubelet `util_unix.go:81-124` (every version; probe table above).
  - Fix: a dedicated type such as `KubernetesCriEndpoint` that requires `unix://` followed by an absolute path, or a bare absolute path. It should reject whitespace, `%`, `$`, `;`, `\` and quotes.
- [bug] **The value is rendered unquoted into systemd `ExecStart=`.**
  - Evidence:
    - `unix:///run/a%20b.sock` is accepted by `Url`. `systemd-analyze verify` on an equivalent unit reports "Failed to resolve unit specifiers ... Invalid slot ... Unit configuration has fatal error" (a scratch probe (not kept)), so kubelet never starts.
    - `unix:///run/a b.sock` is split by systemd into a second argument, and kubelet exits with "unknown command" (`1.35:cmd/kubelet/app/server.go:185-188`).
    - `$VAR` is expanded by systemd.
  - Fix: the type restriction above. Better still, render `containerRuntimeEndpoint: "<value>"` in `kubelet-config` (the field exists 1.31-1.37) and drop the deprecated flag, which also removes the deprecation warning.
- [risk] **Undocumented constraints for a non-default endpoint.**
  - Evidence: the pause image is imported and pinned only in Bottlerocket's containerd. `--containerd`, `--runtime-cgroups` and `BindsTo` are fixed to containerd. With soci, the image service bypasses the endpoint (`k8s-snapshotter-conf:10`). crictl has no config.
  - A non-containerd runtime at the endpoint will fail sandbox creation when pulling `localhost/kubernetes/pause:0.1.0` (inferred).
  - Fix: document "CRI proxy in front of Bottlerocket's containerd only; socket must exist before kubelet starts; with soci the image service is not proxied".
- [nit] It uses a deprecated flag in all versions. It is not documented on the website. core-kit #968 was tested only with `make build`.

## Script feedback

1. `python3 -I $T/k8s-field-report.py field userNamespaces.idsPerPod`
   - It prints no gate line for 1.33 because the upstream tag is misspelled `+featureGate=UserNamespaceSupport` (`1.33:.../types.go:1134`).
   - It prints no gate line for 1.36/1.37 because the tag is removed at GA, even though the gate is GA and locked there.
   - Its diff therefore reports "gate removed" in 1.36 rather than "GA locked".
   - Suggest: resolve gates by matching against the known gate list, and keep reporting GA gates after the tag is gone.
2. Same command: there is no `validation @` line for any version. The idsPerPod checks live in `pkg/kubelet/apis/config/validation/validation_linux.go:44-55`, and the tool apparently scans only `validation.go`. Suggest scanning `validation*.go`.
3. Same command: the "consumers" list shows the getter (`kubelet_getters.go:149`) but not who calls it (`userns_manager.go:137`) or the runtime constraints at `userns_manager.go:139-163`. Those constraints are what break Bottlerocket on 1.35+. Suggest expanding one level of callers and printing `return ... fmt.Errorf` lines in those callers.
4. `python3 -I $T/k8s-field-report.py flag containerd` reports **ABSENT in all versions**. That is wrong: the flag is registered through `registerDeprecated` in `cmd/kubelet/app/options/globalflags_linux.go:52` (1.31-1.35) and `:51` (1.36), and removed in 1.37. A false ABSENT here would wrongly suggest that Bottlerocket passes an unknown flag, which would make kubelet exit. Suggest scanning `globalflags*.go` as well as `options.go`.
5. `python3 -I $T/k8s-field-report.py flag container-runtime-endpoint` does not say that the flag is deprecated (all `AddKubeletConfigFlags` flags are, via `options.go:339-356` in 1.31) or that it maps to the config field `containerRuntimeEndpoint`. Suggest printing "deprecated config-file flag -> <field>".
6. `python3 -I $T/kubelet-config-lint.py` covers only `kubelet-config`. Flags in `kubelet-exec-start-conf` (`--containerd`, `--pod-infra-container-image`, `--container-runtime-endpoint`) are never checked for existence or deprecation. Suggest a flag pass over `kubelet-exec-start-conf` that uses the corrected flag lookup from item 4.
7. `python3 -I $T/template-drift.py kubernetes --matrix` was correct for this group: ids-per-pod is rendered in 1.33+ only, and the other two in all versions. It does flag unrelated drift for `topology-manager-policy-options.*` between 1.35 and 1.36, which belongs to another group.
8. Cross-check caution, not a script: a WebFetch summary of kubernetes.io/docs/concepts/workloads/pods/user-namespaces invented a `--userns-id-count` flag and an example subuid range (`kubelet:100000:65536`) that would fail kubelet's multiple-of-idsPerPod check. Use source as ground truth.
