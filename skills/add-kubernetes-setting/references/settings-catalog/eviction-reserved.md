<!-- Audit of shipped settings, 2026-11-17, against core-kit a4f438b1f, settings-sdk 06d9d1a, bottlerocket b7c6c274,
     and the EKS-D sources packaged in core-kit for Kubernetes 1.31-1.37 (containerd 1.7/2.2/2.3).
     Line numbers drift; re-run scripts/k8s-field-report.py before relying on a citation.
     Status of the findings as of this date: see ../../SKILL.md "Known open findings". -->

# eviction-reserved

Scope: `settings.kubernetes.merge-default-eviction-settings` and the `pid` key of `settings.kubernetes.kube-reserved` / `settings.kubernetes.system-reserved`, for Kubernetes 1.31 through 1.37 as packaged by core-kit.
Upstream citations are `<minor>:<path>:<line>` relative to the EKS-D `src/` in `~/.cache/br-package-src`.
Bottlerocket citations are relative to the grove root unless absolute.
Anything not verified against source is marked "inferred".

## settings.kubernetes.merge-default-eviction-settings

### Upstream per version

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | no | none; no CLI flag | n/a. If `evictionHard` is nil, kubelet uses `DefaultEvictionHard` (1.31:cmd/kubelet/app/server.go:420-422) | n/a | none | A partial `evictionHard` fully replaces the defaults. A rendered key would be dropped by lenient decoding with a log line (1.31:pkg/kubelet/kubeletconfig/util/codec/codec.go:76-100) |
| 1.32 | no | none; no CLI flag | n/a; nil `evictionHard` falls back to defaults (1.32:cmd/kubelet/app/server.go:449-451) | n/a | none | same as 1.31 |
| 1.33 | yes (new) | `mergeDefaultEvictionSettings`, `*bool` (1.33:staging/src/k8s.io/kubelet/config/v1beta1/types.go:597); internal `bool` (1.33:pkg/kubelet/apis/config/types.go:348); no CLI flag | `false` (1.33:pkg/kubelet/apis/config/v1beta1/defaults.go:239-241) | none (nothing in `pkg/kubelet/apis/config/validation/`) | none | merge code at 1.33:cmd/kubelet/app/server.go:453-461 |
| 1.34 | yes | `*bool` (1.34:staging/src/k8s.io/kubelet/config/v1beta1/types.go:598); internal 1.34:pkg/kubelet/apis/config/types.go:349 | `false` (1.34:pkg/kubelet/apis/config/v1beta1/defaults.go:239-241) | none | none | merge at 1.34:cmd/kubelet/app/server.go:456-464, same as 1.33 |
| 1.35 | yes | `*bool` (1.35:staging/src/k8s.io/kubelet/config/v1beta1/types.go:598); internal 1.35:pkg/kubelet/apis/config/types.go:349 | `false` (1.35:pkg/kubelet/apis/config/v1beta1/defaults.go:239-241) | none | none | merge at 1.35:cmd/kubelet/app/server.go:452-460, same as 1.33 |
| 1.36 | yes | `*bool` (1.36:staging/src/k8s.io/kubelet/config/v1beta1/types.go:622); internal 1.36:pkg/kubelet/apis/config/types.go:360 | `false` (1.36:pkg/kubelet/apis/config/v1beta1/defaults.go:240-242) | none | none | merge at 1.36:cmd/kubelet/app/server.go:472-480, same as 1.33 |
| 1.37 | yes | `*bool` (1.37:staging/src/k8s.io/kubelet/config/v1beta1/types.go:622); internal 1.37:pkg/kubelet/apis/config/types.go:360 | `false` (1.37:pkg/kubelet/apis/config/v1beta1/defaults.go:238-240) | none | none | merge at 1.37:cmd/kubelet/app/server.go:472-480, same as 1.33 |

The defaults that get merged (`eviction.DefaultEvictionHard`, Linux build) are the same five signals in every version:
`memory.available: 100Mi`, `nodefs.available: 10%`, `nodefs.inodesFree: 5%`, `imagefs.available: 15%`, `imagefs.inodesFree: 5%`
(1.31-1.35:pkg/kubelet/eviction/defaults_linux.go:23-29, 1.36-1.37:pkg/kubelet/eviction/defaults_linux.go:22-28).
There is no `pid.available` default, so merging never adds a PID eviction threshold.
The `evictionHard` doc comment lists only four defaults and leaves out `imagefs.inodesFree` (e.g. 1.33:staging/src/k8s.io/kubelet/config/v1beta1/types.go:552-556). The code wins, so the real list is the five signals above.

How the merge works, which is the same in 1.33-1.37 (quoted from 1.33:cmd/kubelet/app/server.go:453-461):

```go
if kc.EvictionHard == nil {
    kc.EvictionHard = eviction.DefaultEvictionHard
} else if kc.MergeDefaultEvictionSettings {
    for k, v := range eviction.DefaultEvictionHard {
        if _, exists := kc.EvictionHard[k]; !exists {
            kc.EvictionHard[k] = v
        }
    }
}
```

- Only `evictionHard` gets defaults merged in.
  The field doc names evictionHard, evictionSoft, evictionSoftGracePeriod and evictionMinimumReclaim, then admits that "currently only evictionHard has default values" (1.33:staging/src/k8s.io/kubelet/config/v1beta1/types.go:588-596).
  The other three have no defaults anywhere, so merging adds nothing to them.
- Merging works per key and the user's value wins, including `"0%"`/`"100%"`. `parseThresholdStatement` later drops those values, which disables that signal (1.35:pkg/kubelet/eviction/helpers.go:388-390).
  So "merge, but turn off one default" works only with `"0%"`. A bare `"0"` fails with "must be positive" (1.35:pkg/kubelet/eviction/helpers.go:414-416).
- The merge runs inside `loadConfigFile`, which handles only the `--config` file, before `--config-dir` drop-ins are merged (1.33:cmd/kubelet/app/server.go:216-227).
  So `mergeDefaultEvictionSettings` set in a drop-in does nothing to the main file's map.
  A drop-in `evictionHard` is JSON-merge-patched onto a map that has already been defaulted or merged (1.33:cmd/kubelet/app/server.go:325-385), so drop-ins always add keys rather than replace the map (inferred from `jsonpatch.MergePatch` semantics).
  Bottlerocket renders the field in the main file (`--config /etc/kubernetes/kubelet/config`, kits/bottlerocket-core-kit/packages/kubernetes-1.35/kubelet-exec-start-conf:17), so this is only a note for users who write their own drop-ins.
- The merged map feeds two things:
  - the eviction manager (`ParseThresholdConfig`, 1.33:pkg/kubelet/kubelet.go:525);
  - the Node Allocatable reservation (1.33:cmd/kubelet/app/server.go:819). That reservation subtracts only `memory.available` and `nodefs.available` (1.31:pkg/kubelet/cm/helpers.go:32-53, 1.37:pkg/kubelet/cm/helpers.go:45-66).
  So merging changes `status.allocatable.ephemeral-storage` by 10% of nodefs capacity, which makes a cheap observable (see verification).

### What changes between versions

- 1.31 -> 1.32: none. Neither has the field. A non-nil `evictionHard` is used exactly as written (1.31:cmd/kubelet/app/server.go:420-422, 1.32:cmd/kubelet/app/server.go:449-451).
- 1.32 -> 1.33: field added (`*bool`, default false), with the merge branch in `loadConfigFile` (1.33:staging/src/k8s.io/kubelet/config/v1beta1/types.go:597, 1.33:pkg/kubelet/apis/config/v1beta1/defaults.go:239-241, 1.33:cmd/kubelet/app/server.go:455-461). No feature gate guards it.
- 1.33 -> 1.37: none. Type, default, merge code and `DefaultEvictionHard` values are identical; only line numbers move (rows above). `k8s-field-report.py field mergeDefaultEvictionSettings` agrees: "kubernetes-1.33: added", nothing after.

### Bottlerocket implementation

- Model: `merge_default_eviction_settings: bool` (bottlerocket-settings-sdk/bottlerocket-settings-models/settings-extensions/kubernetes/src/lib.rs:51).
  `#[model]` wraps it in `Option` and adds `deny_unknown_fields` (bottlerocket-settings-sdk/bottlerocket-settings-models/model-derive/src/lib.rs:36,112-116).
  Only JSON booleans are accepted; `"true"`, `1`, `[]` and `{}` are rejected (lib.rs:295-307).
  Upstream has no validation for this field, so neither side accepts anything the other rejects.
  The model is shared by every k8s version: the single `aws-k8s` settings plugin uses `KubernetesSettingsV1` (bottlerocket/sources/settings-plugins/aws-k8s/src/lib.rs:8). As a result, 1.31 and 1.32 variants accept the setting too.
- Templates:
  - 1.33-1.37: `kits/bottlerocket-core-kit/packages/kubernetes-1.3{3..7}/kubelet-config:42-44` render it with `{{#if_not_null settings.kubernetes.merge-default-eviction-settings}}mergeDefaultEvictionSettings: {{...}}{{/if_not_null}}`.
    - unset: nothing is rendered, so kubelet defaults to false;
    - `false`: renders `mergeDefaultEvictionSettings: false`, which is the same as the default;
    - `true`: renders `mergeDefaultEvictionSettings: true`.
    It renders as an unquoted YAML bool. `if_not_null` skips only null (kits/bottlerocket-core-kit/sources/api/schnauzer/src/helpers/stdlib/mod.rs:671-706). No featureGates are involved.
  - 1.31-1.32: not rendered (kubernetes-1.31/kubelet-config:42 and kubernetes-1.32/kubelet-config:42 start directly at the `eviction-hard` block). This is correct, because the field does not exist upstream.
    The core-kit test `older_versions_do_not_render_merge_defaults` pins this behavior (kits/bottlerocket-core-kit/sources/api/schnauzer/tests/kubelet_eviction_settings.rs:55-62).
  - Related block: `evictionHard` renders only when the map is non-empty (`{{#if}}` on an object is false when empty; kubelet-config:45-50 on 1.33+, :42-47 on 1.31/1.32). Values are quoted strings. An empty map leaves `evictionHard` nil, so all five defaults apply no matter what the merge setting says.
  - Supported upstream but not rendered: none. Rendered where unsupported: none.
- What a 1.31/1.32 user gets with `merge-default-eviction-settings = true`:
  - `apiclient set` and user-data accept it.
  - It is stored, and the `kubernetes` service restart runs (`systemctl try-restart kubelet.service`, bottlerocket/sources/shared-defaults/kubernetes-services.toml:15-17).
  - The rendered kubelet config is byte-for-byte the same as without the setting.
  - Effective behavior is identical to `false`: with `eviction-hard = {"memory.available" = "600Mi"}`, kubelet has only the memory threshold, and the nodefs/imagefs hard thresholds are gone.
  - The docs say so ("This setting has an effect only on Kubernetes 1.33+ variants", bottlerocket-project-website/data/settings/1.69.x/kubernetes.toml:12).
- Migration: present. `bottlerocket/sources/settings-migrations/v1.69.0/kubernetes-merge-default-eviction-settings/src/main.rs` is an `AddSettingsMigration`, which removes the key on downgrade. It is listed in bottlerocket/Release.toml:491-495 (`(1.68.1, 1.69.0)`) and as a workspace member in bottlerocket/sources/Cargo.toml:81.
  The release is coherent: bottlerocket 1.69.0 pins core-kit 18.0.0 (bottlerocket/Twoliter.lock:19-22), which contains core-kit #1089 and #1120. Both repos pin settings-models v0.33.0 (bottlerocket/sources/Cargo.toml:152; `git show v18.0.0:sources/Cargo.toml` in core-kit, line 237). The field first appears in v0.32.0 (settings-sdk CHANGELOG.md:24-28).
- Docs: present at bottlerocket-project-website/data/settings/1.69.x/kubernetes.toml:1-28. The description, the 1.33+ note and the example are accurate. The docs do not say that only `eviction-hard` is affected, or that `"0%"` (not `"0"`) is how to turn off a single default while merging.

### How to verify it works on a node

Run on one node per variant (1.31 ... 1.37). Use kubectl from a workstation, and `apiclient` / `sheltie` from the admin container.

1. Baseline with no eviction settings (all versions):
   ```
   NODE=<node-name>
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig | {mergeDefaultEvictionSettings, evictionHard}'
   kubectl get node $NODE -o json | jq '.status | {cap: .capacity["ephemeral-storage"], alloc: .allocatable["ephemeral-storage"], mcap: .capacity.memory, malloc: .allocatable.memory}'
   ```
   Expected: `evictionHard` holds all five defaults (`memory.available` 100Mi).
   `mergeDefaultEvictionSettings` is `false` on 1.33+ (the defaulted pointer is serialized) and absent on 1.31/1.32.
2. Set only `memory.available`, merge off:
   ```
   apiclient set --json '{"settings":{"kubernetes":{"eviction-hard":{"memory.available":"600Mi"}}}}'
   # in sheltie:
   grep -n -A6 -E '^(mergeDefaultEvictionSettings|evictionHard):' /etc/kubernetes/kubelet/config
   ```
   Expected on all versions: configz `evictionHard == {"memory.available":"600Mi"}`.
   Ephemeral-storage allocatable then equals capacity minus `kube-reserved.ephemeral-storage` (1Gi by default) and nothing else.
3. Turn the merge on:
   ```
   apiclient set settings.kubernetes.merge-default-eviction-settings=true
   ```
   Expected on 1.33-1.37:
   - the rendered file has `mergeDefaultEvictionSettings: true`;
   - configz shows `mergeDefaultEvictionSettings: true` and five `evictionHard` keys: memory.available 600Mi, nodefs.available 10%, nodefs.inodesFree 5%, imagefs.available 15%, imagefs.inodesFree 5%;
   - ephemeral-storage allocatable drops by 10% of capacity compared with step 2. This is the cheap merge proof, because `hardEvictionReservation` subtracts `nodefs.available`.
   Expected on 1.31/1.32: no line in the file, configz is unchanged from step 2, and allocatable is unchanged.
4. `kubectl describe node $NODE` shows Capacity/Allocatable, consistent with step 3. MemoryPressure/DiskPressure/PIDPressure stay False.
   Thresholds themselves are not in node status or default-verbosity kubelet logs, so configz is the authoritative view.
   An optional end-to-end disk-pressure test (fill nodefs past 90% and watch DiskPressure/evictions) is slow and destructive; the allocatable diff is enough.
5. Clean up: the API has no reliable "unset" (model fields are `Option`, and a `None`/null in a PATCH is skipped, so it inferred-acts as "no change"). Toggle back with `merge-default-eviction-settings=false`, or use a fresh node for each A/B leg.

Time cost: each step is about 30 s, mostly the kubelet restart, so a full A/B is about 3 min per node. Launching seven variant nodes in parallel takes about 10-15 min.
Upstream e2e_node coverage: none for `mergeDefaultEvictionSettings` in any version. It is covered only by unit tests: pkg/kubelet/apis/config/v1beta1/defaults_test.go and pkg/kubelet/apis/config/helpers_test.go, e.g. 1.35:pkg/kubelet/apis/config/helpers_test.go:262.
The eviction e2e tests (e.g. 1.35:test/e2e_node/eviction_test.go:88,293) depend on the non-merge behavior, because they set a single-signal `evictionHard`.

### Findings

- [risk] Silent no-op on 1.31/1.32.
  Input: aws-k8s-1.32 with `merge-default-eviction-settings = true` and `eviction-hard."memory.available" = "600Mi"`.
  Effect: the API accepts it, the template does not render it (kubernetes-1.32/kubelet-config:42), and the kubelet field does not exist anyway.
  kubelet ends up with only the memory threshold, and nodefs/imagefs hard eviction is disabled, which is the opposite of what the user asked for.
  The docs note covers it.
  Possible fix if 1.31/1.32 stay supported for long: emulate the merge in those two templates. For each of the five constant defaults, render `{{#unless (lookup settings.kubernetes.eviction-hard "<signal>")}}` when the setting is true. The values are identical in every version (defaults_linux.go above).
  Otherwise, accept the docs note.
- [risk] Turning off one default while merging needs `"0%"`; Bottlerocket accepts `"0"` (and negative quantities), which kubelet rejects at startup.
  Input: any version, `eviction-hard = {"nodefs.available" = "0"}`; the value passes `KubernetesThresholdValue` via `KUBERNETES_QUANTITY` (bottlerocket-settings-sdk/bottlerocket-settings-models/modeled-types/src/kubernetes.rs:552-561,566-592).
  Effect: kubelet logs `eviction threshold nodefs.available must be positive: 0` (1.35:pkg/kubelet/eviction/helpers.go:414-416), and `run()` returns the error (1.35:cmd/kubelet/app/server.go:812-815).
  kubelet.service is `Restart=always` (kits/bottlerocket-core-kit/packages/kubernetes-1.35/kubelet.service:17), so it loops and the node never joins. `"-100Mi"` hits the same check.
  This belongs to the eviction-hard value type rather than to the merge field, but merging is exactly when users want to turn one signal off.
  Fix: reject zero and negative non-percent values in `KubernetesThresholdValue`, and document "use `0%` to disable a signal".
- [nit] Docs (website 1.69.x/kubernetes.toml:1-16) should say the merge applies only to `eviction-hard` (not `eviction-soft`), list the five defaults, and show `"0%"` as the way to drop one default.

## settings.kubernetes.kube-reserved.pid / settings.kubernetes.system-reserved.pid

### Upstream per version

In every version `pid` is a key of a `map[string]string`, not a struct field. Keys and values are validated only at runtime by `parseResourceList` in `cmd/kubelet/app/server.go`, not by `ValidateKubeletConfiguration`.

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `systemReserved["pid"]`, `kubeReserved["pid"]`, `map[string]string` (1.31:staging/src/k8s.io/kubelet/config/v1beta1/types.go:638,646); flags `--system-reserved`/`--kube-reserved` with `pid=1000` in help (1.31:cmd/kubelet/app/options/options.go:499-500) | nil (no reservation) | key must be cpu, memory, ephemeral-storage or pid, else "cannot reserve %q resource"; value `resource.ParseQuantity`; negative rejected (1.31:cmd/kubelet/app/server.go:1350-1360). Error aborts kubelet (1.31:cmd/kubelet/app/server.go:774-781) | none (`SupportNodePidsLimit` not defined) | runc v1.2.8 (1.31:go.mod:49), `PidsLimit int64`; 0 means "do not touch" |
| 1.32 | yes | same (1.32:staging/src/k8s.io/kubelet/config/v1beta1/types.go:644,652; options.go:499-500) | nil | same (1.32:cmd/kubelet/app/server.go:1363-1373, call 797-804) | none | runc v1.2.8 (1.32:go.mod:53). Compressible enforcement keys added (not used by Bottlerocket) |
| 1.33 | yes | same (1.33:staging/src/k8s.io/kubelet/config/v1beta1/types.go:693,701) | nil | same (1.33:cmd/kubelet/app/server.go:1365-1375, call 807-814) | none | opencontainers/cgroups v0.0.3 (1.33:go.mod:49), `int64`, 0 = untouched |
| 1.34 | yes | same (1.34:staging/src/k8s.io/kubelet/config/v1beta1/types.go:694,702) | nil | same (1.34:cmd/kubelet/app/server.go:1339-1349, call 806-813) | none | cgroups v0.0.1 (1.34:go.mod:49), `int64` |
| 1.35 | yes | same (1.35:staging/src/k8s.io/kubelet/config/v1beta1/types.go:694,702) | nil | same (1.35:cmd/kubelet/app/server.go:1334-1344, call 800-807) | none | cgroups v0.0.3 (1.35:go.mod:47), `int64` |
| 1.36 | yes | same (1.36:staging/src/k8s.io/kubelet/config/v1beta1/types.go:718,726) | nil | same (1.36:cmd/kubelet/app/server.go:1364-1374, call 833-840) | none | cgroups v0.0.6 (1.36:go.mod:45): `PidsLimit *int64`, 0 now means a limit of 1 |
| 1.37 | yes | same (1.37:staging/src/k8s.io/kubelet/config/v1beta1/types.go:718,726) | nil | same plus CPU rounded to millicores (1.37:cmd/kubelet/app/server.go:1415-1428; pid unaffected) | none | cgroups v0.0.7 (1.37:go.mod:45), same as 1.36 |

What the reservation does (same in every version unless noted):

- PIDs are "internal capacity", not a node resource.
  `internalCapacity["pid"] = min(/proc/sys/kernel/pid_max, /proc/sys/kernel/threads-max)` (1.37:pkg/kubelet/cm/container_manager_linux.go:248-253, 1.37:pkg/kubelet/stats/pidlimit/pidlimit_linux.go:37-51; 1.31: container_manager_linux.go:239-244, pidlimit_linux.go:38-52).
  `node.status.capacity/allocatable` never contain `pid`. The upstream test says so: "Process IDs are not a node allocatable, so we have to do this ad hoc" (1.35:test/e2e_node/node_container_manager_test.go:169).
- Enforcement: with `cgroupsPerQOS` true and `"pods"` in `enforceNodeAllocatable`, both being the defaults that Bottlerocket keeps (1.37:pkg/kubelet/apis/config/v1beta1/defaults.go:52,165,271-272), kubelet sets the pids limit of the pods root cgroup (`kubepods.slice` with the systemd driver).
  The limit is `internalCapacity.pid - systemReserved.pid - kubeReserved.pid`, clamped at 0 (1.37:pkg/kubelet/cm/node_container_manager_linux.go:69-79,265-284,220-250; 1.31:pkg/kubelet/cm/node_container_manager_linux.go:69-80,165-188,197-213).
  It is reapplied on every kubelet start (`enforceNodeAllocatableCgroups`).
- `kubeReservedCgroup` / `systemReservedCgroup` get a pids cap only when `kube-reserved` / `system-reserved` is in `enforceNodeAllocatable` (1.37:pkg/kubelet/cm/node_container_manager_linux.go:122-139). The `*-compressible` variants (1.32+) never apply pids (getCgroupConfigInternal, 1.37:node_container_manager_linux.go:220-250).
- Hard-eviction thresholds never reduce the pids limit. `hardEvictionReservation` handles only memory and nodefs (1.37:pkg/kubelet/cm/helpers.go:45-66), and the kubepods limit uses `getNodeAllocatableInternalAbsolute`, which leaves eviction out.
- No sanity check: `validateNodeAllocatable` iterates `cm.capacity`, which has no `pid` (1.37:pkg/kubelet/cm/node_container_manager_linux.go:317-335; 1.31:247-264). A pid reservation larger than capacity is therefore accepted and clamped to 0 (1.37:node_container_manager_linux.go:276-278).
  What a 0 limit does depends on the cgroup library:
  - 1.31-1.35: `resources.PidsLimit = *ptr`, an `int64` whose doc says "set <= 0 to disable limit". The systemd driver only sets TasksMax when it is > 0 or -1, and fs2 skips 0. So the kubepods limit is left as it was (runc v1.2.8 `libcontainer/cgroups/systemd/v2.go:260`, `fs2/pids.go:16-18`; cgroups v0.0.3 `systemd/v2.go:259`; read with `gh api`).
  - 1.36-1.37: `resources.PidsLimit = ptr` (1.36:pkg/kubelet/cm/cgroup_manager_linux.go:308-309). With cgroups v0.0.6/v0.0.7 a 0 limit becomes `TasksMax=1` / `pids.max=1` (`systemd/v2.go:262-272`, `fs2/pids.go` setPids).
  The module source is not unpacked in the cache, so the upstream tag content is assumed to equal what EKS-D builds (inferred).

### What changes between versions

- Key support, value parsing and the non-negative check: none from 1.31 to 1.37 (parseResourceList rows above). No feature gate in any version (`k8s-field-report.py gate SupportNodePidsLimit`: not defined in all seven).
- Enforcement keys: 1.32 adds `kube-reserved-compressible` / `system-reserved-compressible` (absent in 1.31:pkg/kubelet/cm/node_container_manager_linux.go, present from 1.32). They never apply pids, and Bottlerocket does not render `enforceNodeAllocatable`, so pid behavior does not change.
- 1.35 -> 1.36: the cgroup library's PID-limit type changes from `int64` to `*int64` (1.35:pkg/kubelet/cm/cgroup_manager_linux.go:306-307 vs 1.36:pkg/kubelet/cm/cgroup_manager_linux.go:308-309). For valid reservations the result is the same. For an over-reservation (sum >= internal pid capacity), kubepods goes from "limit unchanged" (1.31-1.35) to "limit 1" (1.36-1.37).
- 1.36 -> 1.37: parseResourceList starts rounding CPU to millicores (1.37:cmd/kubelet/app/server.go:1423-1425). This does not affect pid.
- The upstream doc comments are stale in every version: "Currently only cpu and memory are supported" for systemReserved, and "cpu, memory and local storage" for kubeReserved (e.g. 1.37:staging/src/k8s.io/kubelet/config/v1beta1/types.go:712-726). The flag help and the code do support pid.

### Bottlerocket implementation

- Model:
  - Fields: `kube_reserved` / `system_reserved: HashMap<KubernetesReservedResourceKey, KubernetesQuantityValue>` (bottlerocket-settings-sdk/bottlerocket-settings-models/settings-extensions/kubernetes/src/lib.rs:55-56).
  - Keys: an enum of `cpu`, `memory`, `ephemeral-storage`, `pid` (bottlerocket-settings-sdk/bottlerocket-settings-models/modeled-types/src/kubernetes.rs:638-662). This matches kubelet's allowed set exactly in every version.
  - Values: the `KUBERNETES_QUANTITY` regex (kubernetes.rs:552-561, applied at :698-716). Upstream uses `resource.ParseQuantity`, whose grammar is in 1.35:staging/src/k8s.io/apimachinery/pkg/api/resource/quantity.go:40-58, plus a negative check.
  - Accepted by Bottlerocket but rejected by kubelet (kubelet exits, `Restart=always` loop, node never joins). Checked with a copy of the regex in `python3 -I` and against `parseQuantityString` / suffix lookup in apimachinery `quantity.go:161-273` and `suffix.go:88-106,180-198`:
    - `"-1"`: negative (1.35:cmd/kubelet/app/server.go:1340);
    - `"1K"`, `"100K"`: the regex's own comment says "e.g. 100K", but `K` is not a Kubernetes suffix (`ErrSuffix`, quantity.go:157);
    - `"1.2.3"`: `ErrFormatWrong`;
    - `"1e"`: `ErrSuffix`.
  - Accepted by kubelet but rejected by Bottlerocket: `"1E3"`, `"1e-3"`, `"1e+3"` (the exponent forms in `<decimalExponent>`, quantity.go:58).
  - Accepted by both but meaningless for pid: fractional values (`"100m"`, `"0.5"`). `Quantity.Value()` rounds up (quantity.go:813-814), so `capacity - 0.1` becomes `capacity` and nothing is reserved.
- Templates (all seven versions are identical in the relevant blocks):
  - `kubeReserved` is always rendered (1.31/1.32 `kubelet-config:84-96`, 1.33-1.37 `kubelet-config:87-99`). `pid: "{{settings.kubernetes.kube-reserved.pid}}"` sits inside `{{#if settings.kubernetes.kube-reserved.pid}}`.
    Unset gives no `pid` line. Values are non-empty strings, so they are always truthy, and `"0"` renders `pid: "0"` (a zero reservation, harmless). The value is a quoted YAML string, matching `map[string]string`.
    The block lists its keys explicitly (cpu via `kube_reserve_cpu`, memory via the value or `kube_reserve_memory`, `ephemeral-storage` defaulting to `1Gi`, pid), so a new reserved key needs a per-version template change. That is why core-kit #646 touched only kubeReserved.
  - `systemReserved` renders only when the map is non-empty (1.31/1.32 `kubelet-config:100-108`, 1.33-1.37 `kubelet-config:103-111`), using `{{#each}}` with `{{@key}}: "{{this}}"`. So `pid` passes through like any other model-accepted key, and has done so since before the pid work (see `git show v10.6.0:packages/kubernetes-1.33/kubelet-config` in core-kit).
  - `kubeReservedCgroup: "/runtime"` and `systemReservedCgroup: "/system"` are rendered unless `reserved-cpus` is set. `enforceNodeAllocatable` and `cgroupsPerQOS` are never rendered (grep over all kubelet-config templates), so kubelet uses `["pods"]` and `true`.
    The pid reservation therefore only lowers `kubepods.slice` pids.max. It never caps `runtime.slice` or `system.slice`.
  - No featureGates are involved. Every supported version renders it, and no unsupported version does. `template-drift.py kubernetes --matrix` shows `kube-reserved.pid` and `system-reserved` as x in 1.31-1.37.
- Migration: present. `bottlerocket/sources/settings-migrations/v1.50.0/kubernetes-reserved-pid-settings/src/main.rs` is an `AddSettingsMigration` for `settings.kubernetes.kube-reserved.pid` and `settings.kubernetes.system-reserved.pid`. It is listed in Release.toml:446-448 (`(1.49.0, 1.50.0)`) and in sources/Cargo.toml:64.
- Docs: present in bottlerocket-project-website/data/settings/1.50.x/kubernetes.toml:7 (system-reserved) and :26 (kube-reserved), one line each.
  They do not say that the reservation only lowers the pods' pids limit, that it is not shown in node allocatable, that it should be an integer, or that the total must stay well below `min(pid_max, threads-max)`. No pid example is given.

#### Release history: why bottlerocket #4650 was reverted, and the lesson

Timeline, from `gh pr view` and core-kit tags:
- settings-sdk #98 (merged 2025-09-23) added `Pid` to `ReservedResources` and shipped as settings-models v0.16.0. v0.15.0 has only cpu/memory/ephemeral-storage (`git show bottlerocket-settings-models-v0.15.0:.../modeled-types/src/kubernetes.rs:626-631`).
- core-kit #646 (merged 2025-09-30) added `pid` to the kubeReserved block of the 1.28-1.34 templates and bumped core-kit's own settings-models to v0.16.0. The first tag containing it is v10.7.0 (`git show v10.7.0:sources/Cargo.toml:213`).
- bottlerocket #4650 (merged 2025-10-03) bumped bottlerocket's settings-models to v0.16.0, set the release to 1.49.0 and added `v1.49.0/kubernetes-reserved-pid-settings`. The core-kit 10.7.0 bump arrived separately (#4656, per the CHANGELOG lines that #4660 removed).
- core-kit v10.7.0 had an unrelated regression on NVIDIA variants: NCCL/EFA tests failed, fixed via libnvidia-container (bottlerocket-core-kit issue #685, linked from #4660).
- bottlerocket #4660 (merged 2025-10-04, "Prep 1.49.0 with core-kit 10.6.0") rolled Twoliter back to core-kit 10.6.0. It also reverted the settings-models bump and the pid migration, and dropped the pid release highlight.
- bottlerocket #4661 (merged 2025-10-09) re-landed the models bump and migration for 1.50.0, moving it to `v1.50.0/...` with the Release.toml entry under `(1.49.0, 1.50.0)`, and bumped core-kit to 10.7.1.

Why the model bump and migration had to go out with the kit rollback (shipping v0.16.0 models with core-kit 10.6.0):
1. Template gap: core-kit 10.6.0's kubeReserved block has no `pid` line, so `kube-reserved.pid` would be accepted and silently dropped.
   `system-reserved.pid` would still render through `{{#each}}`, leaving the feature half working.
2. Model skew inside core-kit binaries (inferred from code, not reproduced). On aws-k8s, pluto runs `apiclient get settings.kubernetes` and deserializes the result into core-kit's pinned `KubernetesSettingsV1` (kits/bottlerocket-core-kit/sources/api/pluto/src/api.rs:118-121,164-174). Models use `deny_unknown_fields` and enum keys.
   With v0.15.0 compiled into core-kit 10.6.0 (`git show v10.6.0:sources/Cargo.toml:214`), user data containing `kube-reserved.pid` would make pluto fail to deserialize and exit 1.
   `pluto.service` is `RequiredBy=settings-applier.service` (kits/bottlerocket-core-kit/packages/os/pluto.service:30), so settings-applier would not run, and the node would not get its config or join.
3. Migration naming: the migration directory, the workspace member and the Release.toml pair are all keyed to the release that introduces the setting. When the setting slipped from 1.49.0 to 1.50.0, all three had to move.

Lesson for the skill:
- Treat it as an invariant that bottlerocket's settings-models tag equals the tag compiled into the core-kit pinned in `Twoliter.lock` (not core-kit develop), and that the pinned kit contains every template line for the new key.
  The API model must never be ahead of core-kit, because core-kit binaries (pluto) deserialize the whole Kubernetes settings struct strictly.
- Ship the bottlerocket models bump, the migration and the kit bump as one unit. If the kit is rolled back for any reason, roll back that unit too, and when it re-lands, rename the migration for the new release.
- Kits bundle unrelated changes, so a setting is only "released" once a kit containing it has passed all variant families (NVIDIA included).
- Current state is coherent for both settings in this group (bottlerocket 1.69.0 / core-kit 18.0.0 / settings-models v0.33.0 on both sides).

### How to verify it works on a node

Run per variant. `$CAP = min(pid_max, threads-max)`. Bottlerocket ships systemd's `50-pid-max.conf` (kits/bottlerocket-core-kit/packages/systemd-257/systemd-257.spec:565), so pid_max is normally 4194304 (inferred from the systemd default), and threads-max, which scales with RAM, is usually the smaller value.

1. Baseline:
   ```
   # sheltie
   cat /proc/sys/kernel/pid_max /proc/sys/kernel/threads-max
   cat /sys/fs/cgroup/kubepods.slice/pids.max          # cgroup v2; v1: /sys/fs/cgroup/pids/kubepods.slice/pids.max
   systemctl show kubepods.slice -p TasksMax
   cat /sys/fs/cgroup/runtime.slice/pids.max /sys/fs/cgroup/system.slice/pids.max
   ```
   Expected (all versions): kubepods pids.max == `$CAP`.
2. Set the reservations:
   ```
   apiclient set --json '{"settings":{"kubernetes":{"kube-reserved":{"pid":"1000"},"system-reserved":{"pid":"500"}}}}'
   grep -n -A6 -E '^(kubeReserved|systemReserved):' /etc/kubernetes/kubelet/config
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig | {kubeReserved, systemReserved, enforceNodeAllocatable, cgroupsPerQOS, kubeReservedCgroup, systemReservedCgroup}'
   ```
   Expected (all versions):
   - the file has `pid: "1000"` under kubeReserved and `pid: "500"` under systemReserved;
   - configz shows the same, plus `enforceNodeAllocatable: ["pods"]`;
   - kubepods pids.max == `$CAP - 1500` (and TasksMax the same);
   - runtime.slice and system.slice pids.max are unchanged from step 1 (not enforced);
   - kubelet event `Updated Node Allocatable limit across pods` (`kubectl get events --field-selector involvedObject.name=$NODE`).
3. Negative check that would mislead: `kubectl get node $NODE -o jsonpath='{.status.allocatable}'` and `kubectl describe node` show no `pid` on any version. Do not use them as proof.
4. Reproductions for the bugs (disposable node, about 2 min each):
   - `apiclient set --json '{"settings":{"kubernetes":{"kube-reserved":{"pid":"1K"}}}}'` is accepted. Then `journalctl -u kubelet -b | grep 'kube-reserved value failed to parse'` shows `failed to parse quantity "1K" for "pid" resource: unable to parse quantity's suffix`, and `systemctl status kubelet` shows restarts.
     Repeat with `"-1"`, which gives `resource quantity for "pid" cannot be negative`. Restore with `"1000"`.
   - Over-reservation: set `kube-reserved.pid` to the threads-max value and restart.
     On 1.36/1.37 expect kubepods pids.max `1`, and `kubectl run pidtest --image=public.ecr.aws/docker/library/busybox --restart=Never -- true` fails to start its container.
     On 1.31-1.35 expect pids.max unchanged from the previous kubelet run (inferred).
5. Time cost: about 1 min per step on an existing node, plus about 2 min per negative test (kubelet restart loop, then restore).

Upstream e2e_node: `test/e2e_node/node_container_manager_test.go` ("Node Container Manager", Serial, `feature.NodeAllocatable`).
It sets `systemReserved.pid=1000` and `kubeReserved.pid=738`, then checks the node-allocatable cgroup's `pids.max == MaxPID - 1738` (1.35:test/e2e_node/node_container_manager_test.go:49-58,154-176,327-349). It also enforces the kube/system reserved cgroups (lines 393-425), which Bottlerocket does not do.
The PID eviction ordering test (1.35:test/e2e_node/eviction_test.go:653-720) covers `pid.available`, not reservation.

### Findings

- [bug] Bottlerocket accepts reserved-resource quantities that make kubelet exit, so the node never joins.
  - Versions: all of 1.31-1.37, for both `kube-reserved` and `system-reserved` and every key, `pid` included.
  - Inputs: `"-1"`, `"1K"`/`"100K"`, `"1.2.3"`, `"1e"`. All pass `KubernetesQuantityValue` (modeled-types/src/kubernetes.rs:552-561,698-716).
  - Effect: kubelet fails in `parseResourceList` with "cannot be negative" or a ParseQuantity error (1.35:cmd/kubelet/app/server.go:1334-1344), and `run()` returns `--kube-reserved value failed to parse` (1.35:cmd/kubelet/app/server.go:800-807). kubelet.service `Restart=always` loops.
  - The same regex also backs other quantity settings, so the blast radius is larger than this group.
  - Fix: replace `KUBERNETES_QUANTITY` with the apimachinery grammar, e.g. `^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)(Ki|Mi|Gi|Ti|Pi|Ei|[numkMGTPE]|[eE][+-]?[0-9]+)?$`, and add a non-negative check for reserved values.
    Consider a dedicated non-negative integer type for `pid` (see the next nit). Add the four inputs above to the `bad_kubernetes_quantity_value` tests (kubernetes.rs:734-748).
- [risk] PID over-reservation is unvalidated by both Bottlerocket and kubelet, and its effect changed in 1.36.
  - Input: `kube-reserved.pid + system-reserved.pid >= min(pid_max, threads-max)`. For example, a value copied from a large node onto a small one: about 30k threads-max on a 4 GiB node (inferred from the kernel `threads-max` formula).
  - Effect on 1.36/1.37: kubepods limit 1, so the node is Ready but no pod can start.
  - Effect on 1.31-1.35: the kubepods limit is left at its previous value, or unlimited on first boot (inferred).
  - Evidence: `validateNodeAllocatable` ignores pid (1.37:pkg/kubelet/cm/node_container_manager_linux.go:317-335); the clamp to 0 is at :276-278; the cgroup library change is at 1.36:pkg/kubelet/cm/cgroup_manager_linux.go:308-309 with cgroups v0.0.6 `systemd/v2.go:262-272`.
  - Fix: Bottlerocket cannot check this at API time. Document it: "keep the sum well below `min(/proc/sys/kernel/pid_max, /proc/sys/kernel/threads-max)`; check with `cat`". Consider an upstream issue asking kubelet to validate pid reservations against internal capacity.
- [nit] Fractional pid values (`"100m"`, `"0.5"`) are accepted by both sides and reserve nothing (`Quantity.Value()` rounds up, quantity.go:813). Fix: use an integer-only value type for the `pid` key.
- [nit] Docs (website 1.50.x/kubernetes.toml:7,26) should explain that pid only lowers `kubepods` pids.max (no cap on runtime/system slices, nothing shown in node allocatable), that it must be an integer below `min(pid_max, threads-max)`, and give an example. The linked KubeletConfiguration reference has the stale "cpu and memory only" text.
- [risk] Release process (from #4650 -> #4660 -> #4661): no automated check ties bottlerocket's settings-models tag to the models tag compiled into the pinned core-kit. A skew where the API is ahead of the kit can break aws-k8s boot through pluto for users who set the new key (inferred, see release history).
  Fix: a pre-release check that compares `bottlerocket/sources/Cargo.toml` `bottlerocket-settings-models-v*` with `sources/Cargo.toml` at the core-kit tag named in `Twoliter.lock`, and that renders every new key with the pinned kit's templates.

## Script feedback

- `python3 -I $T/k8s-field-report.py field kubeReserved.pid` prints "ABSENT: no 'kubeReserved.pid' in KubeletConfiguration v1beta1" for all seven versions. That is misleading: `kubeReserved` is `map[string]string`, and `pid` is a valid key in every version.
  A skill that trusts ABSENT would decide pid is unsupported.
  Suggest detecting a map-typed parent and printing "map key; keys/values validated at runtime by cmd/kubelet/app/server.go parseResourceList", with the allowed-key switch (e.g. 1.37:cmd/kubelet/app/server.go:1415).
- `python3 -I $T/k8s-field-report.py field kubeReserved 1.31 1.37` says "consumers: 14" / "16" but prints fewer lines.
  It leaves out the `parseResourceList(s.KubeReserved)` call (1.31:server.go:774, 1.37:server.go:883), which is the only validation, and it does not follow into that function or into `getCgroupConfig` (pid enforcement).
  As a result its "Changes between consecutive versions" misses the two real behavior changes for this setting: the 1.36 `PidsLimit` pointer change (1.36:pkg/kubelet/cm/cgroup_manager_linux.go:308-309) and the 1.37 CPU rounding in parseResourceList.
  Suggest printing every consumer, and diffing the bodies of functions that take the field as an argument.
- `python3 -I $T/k8s-field-report.py field mergeDefaultEvictionSettings` is accurate (absent in 1.31/1.32, `*bool` default false, one consumer line).
  It shows only the `else if` line, though, not the block or the values it merges. Suggest printing the whole if/else and resolving package-level variables it references (`eviction.DefaultEvictionHard` in pkg/kubelet/eviction/defaults_linux.go), because those values are what users experience.
- `python3 -I $T/k8s-field-report.py field evictionHard 1.33` shows no "default @" line. Defaulting lives in `cmd/kubelet/app/server.go` loadConfigFile, not in `SetDefaults_KubeletConfiguration`.
  The only default shown is the doc comment, which lists four signals and misses `imagefs.inodesFree: 5%` (code: 1.33:pkg/kubelet/eviction/defaults_linux.go:28).
  Suggest flagging "no SetDefaults entry" and searching server.go for `kc.<Field> == nil`.
- `python3 -I $T/kubelet-config-lint.py` reports "every rendered path exists upstream" for all versions, but it never checks map keys or values: `kubeReserved.pid`, `evictionHard.<signal>`, `systemReserved` via `{{#each}}`.
  A template rendering `hugepages-2Mi` under kubeReserved, or a bad signal name, would pass even though kubelet exits.
  Suggest an allowed-keys table for map fields, taken from parseResourceList's switch and from `signalToResource` (1.35:pkg/kubelet/eviction/helpers.go:98-107).
  Positive: `kubelet-config-lint.py 1.31 1.32 --template kits/bottlerocket-core-kit/packages/kubernetes-1.33/kubelet-config` correctly flags `mergeDefaultEvictionSettings` as UNKNOWN on 1.31/1.32.
- `python3 -I $T/template-drift.py kubernetes --matrix` is correct for this group (merge "." on 1.31/1.32, x on 1.33+; pid x everywhere).
  It shows `system-reserved` as a single row because it is `{{#each}}`-rendered, which hides that kube-reserved uses an explicit per-key allowlist and system-reserved passes any key through. Minor.
- Missing tool: nothing checks the settings-models tag in bottlerocket against the models tag inside the core-kit pinned by `Twoliter.lock`. That is the failure class behind #4650/#4660.
