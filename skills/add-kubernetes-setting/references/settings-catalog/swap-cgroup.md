<!-- Audit of shipped settings, 2026-11-17, against core-kit a4f438b1f, settings-sdk 06d9d1a, bottlerocket b7c6c274,
     and the EKS-D sources packaged in core-kit for Kubernetes 1.31-1.37 (containerd 1.7/2.2/2.3).
     Line numbers drift; re-run scripts/k8s-field-report.py before relying on a citation.
     Status of the findings as of this date: see ../../SKILL.md "Known open findings". -->

# swap-cgroup

Scope: `settings.kubernetes.memory-swap-behavior` (kubelet `memorySwap.swapBehavior`) and kubelet `failCgroupV1` (setting added in settings-sdk #108, reverted in #111, hardcoded by core-kit #792), plus the hardcoded `failSwapOn: false`, the 1.35+ zram swap device (`release-swap`, `settings.kernel.zram.size`) and the cgroup v1 opt-in, because they decide whether either kubelet field matters.

Upstream paths are relative to each version's `src/` in `~/.cache/br-package-src/kubernetes-1.3X-*/src`.
Bottlerocket paths are relative to the grove root unless noted.
Nothing here was run on a node (no AWS). Claims are from source unless marked "inferred".

Summary:
- `swapBehavior` accepts exactly `""`, `NoSwap`, `LimitedSwap` in every packaged version (1.31-1.37). No value was added or removed (`UnlimitedSwap` is gone in all of them). Only the NodeSwap gate changes: Beta/on in 1.31-1.33, GA and locked on in 1.34-1.37. Bottlerocket never sets that gate.
- The Bottlerocket enum accepts nothing that kubelet rejects by value. One combination does stop kubelet: `LimitedSwap` on a cgroup v1 host (opt-in through boot parameters) makes kubelet exit at startup in every version.
- `failCgroupV1` exists in 1.31-1.37. Its default is `false` in 1.31-1.34 and `true` in 1.35-1.37. Hardcoding `false` only in 1.35+ is correct, and it changes nothing for cgroup v2 hosts.

## settings.kubernetes.memory-swap-behavior

### Upstream per version

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `memorySwap.swapBehavior`, `string` (1.31:staging/src/k8s.io/kubelet/config/v1beta1/types.go:971, parent field :593). No flag. | `""`, no defaulting in defaults.go. `""` behaves as NoSwap. | NodeSwap on: `""`/`NoSwap`/`LimitedSwap`, anything else is an error (1.31:pkg/kubelet/apis/config/validation/validation.go:193-200). NodeSwap off: any non-empty `memorySwap` is an error (:202-203). Runtime check: `LimitedSwap` on cgroup v1 makes kubelet exit (1.31:cmd/kubelet/app/server.go:810-813). | Beta, default true, unversioned spec (1.31:pkg/features/kube_features.go:1144) | Logic in `configureContainerSwapResources` (1.31:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:165-198). |
| 1.32 | yes | same, types.go:982 (parent :599) | `""` | validation.go:202-209, :211-212. Runtime check at server.go:834-837. | Beta/true. Versioned: 1.22 Alpha/false, 1.28 Beta/false, 1.30 Beta/true (1.32:pkg/features/versioned_kube_features.go:553-557) | Same logic (kuberuntime_container_linux.go:198-231). |
| 1.33 | yes | same, types.go:1036 (parent :648) | `""` | validation.go:203-210, :212-213. Runtime check at server.go:836-839. | Beta/true (1.33:pkg/features/kube_features.go:1548) | Refactored into `GetContainerSwapBehavior` (kuberuntime_container_linux.go:223-246) with the same semantics. Node now reports `.status.nodeInfo.swap.capacity` (1.33:pkg/kubelet/nodestatus/setters.go:359-363). |
| 1.34 | yes | same, types.go:1036 (parent :649) | `""` | validation.go:203-213. Runtime check at server.go:835-838. | GA, locked true (1.34:pkg/features/kube_features.go:1517-1522) | kuberuntime_container_linux.go:225 |
| 1.35 | yes | same, types.go:1036 (parent :649) | `""` | validation.go:206-216. Runtime check at server.go:829-832. | GA, locked (1.35:pkg/features/kube_features.go:1576-1581) | kuberuntime_container_linux.go:225 |
| 1.36 | yes | same, types.go:1069 (parent :673) | `""` | validation.go:209-219. Runtime check at server.go:862-865. | GA, locked (1.36:pkg/features/kube_features.go:1732-1737) | kuberuntime_container_linux.go:234 |
| 1.37 | yes | same, types.go:1075 (parent :673) | `""` | validation.go:237-247. Runtime check at server.go:912-915. | GA, locked (1.37:pkg/features/kube_features.go:1914-1919). Still defined despite the `// remove in 1.37` comment (:1918). | kuberuntime_container_linux.go:305. Startup log `Effective KubeletConfiguration` (1.37:cmd/kubelet/app/server.go:252-257). |

Related field `failSwapOn` (`*bool`, default true in every version: 1.31:pkg/kubelet/apis/config/v1beta1/defaults.go:233-234 ... 1.37:253-254). If a swap device is active and `failSwapOn` is true, kubelet exits with "running with swap on is not supported" (1.31:pkg/kubelet/cm/container_manager_linux.go:213-216 ... 1.37:222-224). This check does not depend on the NodeSwap gate.

### What changes between versions

- Accepted values: none. Every version accepts the same three values (see the table). The constants are only `LimitedSwap` and `NoSwap` (1.31:pkg/kubelet/types/constants.go:34-35; 1.33-1.37:38-39, typed `SwapBehavior` from 1.33, no user-visible change). `UnlimitedSwap` appears nowhere in `pkg/`, `cmd/` or `staging/src/k8s.io/kubelet` of any packaged version.
- NodeSwap gate: Beta/on in 1.31-1.33, GA/locked-on in 1.34-1.37 (citations above).
  - With the gate off, which is only possible in 1.31-1.33 via `featureGates.NodeSwap: false`, any non-empty `memorySwap` fails validation: "memorySwap.swapBehavior cannot be set when NodeSwap feature flag is disabled" (1.31:validation.go:202-203). Kubelet exits (1.31:cmd/kubelet/app/server.go:251-252). All containers are forced to NoSwap (1.31:kuberuntime_container_linux.go:178-181; 1.33:226-228).
  - In 1.34+, trying to set `NodeSwap=false` fails on its own: "cannot set feature gate NodeSwap to false, feature is locked to true" (1.34:staging/src/k8s.io/component-base/featuregate/feature_gate.go:334).
  - None of this can happen on Bottlerocket. No template renders `featureGates.NodeSwap` (the only gates rendered are DRA ones, kubernetes-1.33+/kubelet-config `featureGates:`), and there is no feature-gate setting.
- Effective behavior is the same in every version.
  - **cgroup v2:** `LimitedSwap` gives swap only to containers that meet all of these: not critical, Burstable QoS, requesting memory, and request != limit (1.31:kuberuntime_container_linux.go:183-186 and 381-401; 1.37:305-327). The limit is `floor(request / MemoryCapacity * SwapCapacity)` (1.31:432-444; 1.37:639-651). Every other container, and every container under `NoSwap`/`""`, gets `memory.swap.max=0` (1.31:403-415; 1.37:609-621).
  - **No swap controller:** if `memory.swap.max` is missing in kubelet's own cgroup (v2) or `memory.memsw.limit_in_bytes` is missing (v1), kubelet sets no swap limits at all (1.31:166-168 and 348-371; 1.37:286-288 and 548-574).
  - **cgroup v1:** `LimitedSwap` makes kubelet exit at startup: "swap feature is enabled and LimitedSwap but it is only supported with cgroupv2" (server.go lines in the table). `NoSwap` only sets `MemorySwapLimitInBytes = MemoryLimitInBytes` ("if memory limit is 0, memory swap limit is ignored", 1.31:404-411; 1.37:610-617).
- Visibility changes (not behavior):
  - 1.33+ reports the node's swap capacity in `.status.nodeInfo.swap.capacity`.
  - 1.33+ e2e checks the summary API swap stats (1.33:test/e2e_node/swap_test.go:292).
  - 1.37 logs the full effective config at startup.
  - All versions log "NoSwap is set due to memorySwapBehavior not specified" when `failSwapOn` is false and the behavior is unset (1.31:server.go:815-817; 1.37:917-919). All versions log "Swap is on" with the contents of `/proc/swaps` (1.31:pkg/kubelet/util/swap/swap_util.go:113; 1.37:119).
- tmpfs `noswap` for memory-backed volumes needs kernel 6.4+ (1.31:pkg/util/kernel/constants.go:47). Without it, kubelet emits the Warning event `PossibleMemoryBackedVolumesOnDisk` when swap is on (1.31:pkg/kubelet/cm/container_manager_linux.go:218-224; 1.37:227-233). The emptyDir code applies `noswap` whenever it is supported (1.31:pkg/volume/emptydir/empty_dir.go:339; 1.37:356). This matters only for 1.31/1.32, which use kernel-6.1 (bottlerocket/variants/aws-k8s-1.31/Cargo.toml:23).

### Bottlerocket implementation

- **Model**
  - Field `memory_swap_behavior: KubernetesMemorySwapBehavior` in `KubernetesSettingsV1` (bottlerocket-settings-sdk/bottlerocket-settings-models/settings-extensions/kubernetes/src/lib.rs:94, kebab-case through `#[model]`).
  - The type is an enum with variants `NoSwap` (alias `no-swap`) and `LimitedSwap` (alias `limited-swap`) (bottlerocket-settings-sdk/bottlerocket-settings-models/modeled-types/src/kubernetes.rs:1567-1574). Tests are at :1576-1594 and reject `""`.
  - Aliases are normalized before rendering: the apiserver re-serializes the typed `Settings` before writing the datastore (kits/bottlerocket-core-kit/sources/api/apiserver/src/server/controller.rs:412-422). A real node confirmed that `no-swap` reads back as `"NoSwap"` (bottlerocket PR #4566, testing comment 2992253903). Kubelet therefore only ever sees `NoSwap` or `LimitedSwap`.
  - Accepted by Bottlerocket but rejected by kubelet: no values. Conditionally rejected: `LimitedSwap` on a cgroup v1 host, all versions (finding 1). Gate-off rejection cannot happen on Bottlerocket.
  - Accepted by kubelet but rejected by Bottlerocket: only `""`, which is the same as leaving the setting unset. Nothing is lost.
  - Dead code: the error variant `InvalidMemorySwapBehavior` (modeled-types/src/lib.rs:188-189) is never constructed, because validation goes through serde_plain via `Scalar`.
- **Templates**
  - Rendered in all seven versions with the same block: kubernetes-1.31/kubelet-config:208-211, 1.32:212-215, 1.33:215-218, 1.34:213-216, 1.35:222-225, 1.36:210-213, 1.37:216-219.

    ```
    {{#if settings.kubernetes.memory-swap-behavior}}
    memorySwap:
      swapBehavior: {{settings.kubernetes.memory-swap-behavior}}
    {{/if}}
    ```
  - Unset: the block is skipped, kubelet gets `""` (NoSwap), and configz shows `"memorySwap":{}`.
  - `""`, false and 0 cannot be stored (enum). The value is a plain unquoted YAML string; both variants are safe plain scalars.
  - No `featureGates.NodeSwap` is rendered, which is correct: the gate is on by default everywhere and locked in 1.34+.
  - Every version that supports the field renders it, and no version renders it where it is unsupported.
  - Changing the setting re-renders `kubelet-config` and runs `systemctl try-restart kubelet.service` (bottlerocket/sources/shared-defaults/kubernetes-services.toml:1-17). Existing containers keep the swap limit they were created with; new containers get the new behavior (inferred: limits are computed in `generateLinuxContainerResources`, 1.37:kuberuntime_container_linux.go:167-200).
- **Hardcoded `failSwapOn: false`**
  - Present in every version: kubernetes-1.31/kubelet-config:207, 1.32:211, 1.33:214, 1.34:212, 1.35:220, 1.36:208, 1.37:214. Added by core-kit PR #473.
  - It is what allows kubelet to start at all on 1.35+, where swap is on by default (next bullet). Without it, every 1.35+ node would fail at container_manager_linux.go:222-224.
- **zram interaction (`release-swap`, `settings.kernel.zram.size`, bottlerocket PR #4991)**
  - `release-swap` is included only in the aws/vmware k8s-1.35, 1.36 and 1.37 variants, for example bottlerocket/variants/aws-k8s-1.35/Cargo.toml:23. It is in none of the 1.31-1.34 variants.
  - It installs `prepare-swap.service` (`Before=containerd.service kubelet.service`; kits/bottlerocket-core-kit/packages/release/prepare-swap.service:5-8) and the sysctls `vm.swappiness=200` and `vm.page-cluster=0` (packages/release/release-swap-sysctl.conf; release.spec:259-265, 607-609). On 1.37 the swappiness default is overridden to 150 (bottlerocket/sources/shared-defaults/kubernetes-swappiness.toml:1-3, linked from sources/settings-defaults/aws-k8s-1.37/defaults.d/61-kubernetes-swappiness.toml).
  - corndog creates `/dev/zram0`, 1 GiB by default, clamped to MemTotal, with swap priority 1024 (kits/bottlerocket-core-kit/sources/api/corndog/src/swap.rs:13, 86-95, 113-135). It does this once per boot and never resizes an initialized device. Setting the size to `"0"` creates no device. The `corndog-toml` template is `{{#if settings.kernel.zram.size}}` (packages/os/corndog-toml:36-39); `"0"` is a non-empty string and is rendered, as covered by sources/api/schnauzer/tests/zram_settings.rs:12.
  - Result on 1.35+ with the setting unset: swap is on, kubelet starts because of `failSwapOn: false`, and every container gets `memory.swap.max=0` on cgroup v2. Only host and system processes use zram.
  - With `LimitedSwap`, a qualifying container gets `request / MemoryCapacity * 1Gi` by default. For example, about 140 MiB for a 1Gi request on an 8 GiB node, because the zram device is small. Raise `settings.kernel.zram.size` and reboot to give pods more.
  - SwapCapacity comes from cAdvisor machine info, computed once when kubelet starts (1.31:pkg/kubelet/cm/container_manager_linux.go:227-229 comment). prepare-swap runs first, so this is fine on 1.35+. On 1.31-1.34 a user must bring their own swap before kubelet starts, or restart kubelet after `swapon` (inferred). Otherwise `LimitedSwap` silently yields `memory.swap.max=0`.
  - Bottlerocket units put kubelet in `runtime.slice` with `MemoryAccounting=true` (kits/bottlerocket-core-kit/packages/kubernetes-1.3X/kubelet.service:9, :23). kubelet's swap-controller probe of `/sys/fs/cgroup/<self>/memory.swap.max` should therefore succeed. Core-kit PR #473 observed `memory.swap.max=0` on containers with 1.25-1.32 cgroup v2 nodes. Not yet observed on 1.35+ (6.12/6.18 kernels); see the verification steps.
- **cgroup v1 interaction**
  - A user can opt into cgroup v1 (see the failCgroupV1 section). On such a node `LimitedSwap` stops kubelet (finding 1).
  - With zram on by default on 1.35+, `NoSwap` does not stop limit-less containers from swapping (finding 2).
- **Migration:** bottlerocket/sources/settings-migrations/v1.42.0/kubernetes-memory-swap-behavior-setting/src/main.rs:6-10 (`AddSettingsMigration`), registered in bottlerocket/Release.toml:428-430 for (1.41.0, 1.42.0). A tested rollback removed the key (PR #4566 testing comment).
- **Docs:** missing. No `memory-swap-behavior` entry exists in any `bottlerocket-project-website/data/settings/*/kubernetes.toml` or under `content/`. The only swap docs are for zram (`data/settings/1.69.x/kernel.toml`, which says it takes effect only on 1.35+ variants).

### How to verify it works on a node

Variables: `NODE=<node name>`. Host commands run in the admin container after `sudo sheltie`. Expected results are the same for 1.31-1.37 except where noted.

1. Host facts, about 1 min:

   ```
   uname -r                                    # 1.31/1.32: 6.1, 1.33-1.35: 6.12, 1.36/1.37: 6.18
   stat -fc %T /sys/fs/cgroup                  # cgroup2fs = v2 (default), tmpfs = v1
   cat /proc/swaps                             # 1.35+: /dev/zram0 ~1G by default; 1.31-1.34: header only
   systemctl status prepare-swap.service       # 1.35+ only
   CG=$(systemctl show -p ControlGroup --value kubelet); cat /sys/fs/cgroup${CG}/memory.swap.max
   # must exist (kubelet's swap-controller probe); if missing, kubelet sets no swap limits at all
   ```
2. Provide swap where it is missing (1.31-1.34), about 2 min. Run these on the host, then restart kubelet so cAdvisor reads SwapTotal again:

   ```
   modprobe zram && echo 4G > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon /dev/zram0
   systemctl restart kubelet
   ```

   It is inferred that the zram module and swap tools exist on these kernels (CHANGELOG "Include swap utilities (#3829)"). A swapfile on `/local` is the fallback.

   On 1.35+, to make pod swap large enough to observe:

   ```
   apiclient set settings.kernel.zram.size="100%"
   apiclient reboot
   ```

   About 3-5 min; the size is applied once per boot.
3. API, rendered file and kubelet view, about 1 min:

   ```
   apiclient set settings.kubernetes.memory-swap-behavior=LimitedSwap
   apiclient get settings.kubernetes.memory-swap-behavior          # "LimitedSwap" (aliases come back normalized)
   grep -A1 '^memorySwap:' /etc/kubernetes/kubelet/config           # swapBehavior: LimitedSwap
   grep -E '^fail(SwapOn|CgroupV1):' /etc/kubernetes/kubelet/config  # failSwapOn: false everywhere; failCgroupV1: false only 1.35+
   journalctl -u kubelet -b --no-pager | grep -E 'Swap is on|NoSwap is set due|only supported with cgroupv2|running with swap on'
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig | {memorySwap, failSwapOn, failCgroupV1}'
   # expected: {"memorySwap":{"swapBehavior":"LimitedSwap"},"failSwapOn":false,"failCgroupV1":false}
   # unset A/B: {"memorySwap":{}, ...} plus the log line "NoSwap is set due to memorySwapBehavior not specified"
   kubectl get node $NODE -o jsonpath='{.status.nodeInfo.swap.capacity}'   # 1.33+: SwapTotal in bytes; empty on 1.31/1.32 or with no swap
   ```

   On 1.37 only: `journalctl -u kubelet -b | grep 'Effective KubeletConfiguration'` shows the same fields.
4. One pod for each swap branch, about 3 min. Use agnhost (`registry.k8s.io/e2e-test-images/agnhost:2.52`, args `["pause"]`, it has `sh`/`cat`) with `nodeName: $NODE` and these resources:
   - `swap-be`: none (BestEffort)
   - `swap-bu`: requests.memory 512Mi (Burstable)
   - `swap-bueq`: requests = limits memory 512Mi, no cpu (Burstable with request == limit)
   - `swap-gu`: cpu 100m and memory 512Mi, requests = limits (Guaranteed)
   - `swap-crit`: same as `swap-bu` plus `priorityClassName: system-node-critical`

   ```
   for p in be bu bueq gu crit; do echo "$p $(kubectl exec swap-$p -- cat /sys/fs/cgroup/memory.swap.max)"; done
   # host view of the same file:
   U=$(kubectl get pod swap-bu -o jsonpath='{.metadata.uid}' | tr - _)
   C=$(kubectl get pod swap-bu -o jsonpath='{.status.containerStatuses[0].containerID}'); C=${C#containerd://}
   cat /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod${U}.slice/cri-containerd-${C}.scope/memory.swap.max
   ```

   Expected with LimitedSwap and swap present: `swap-bu` = floor(536870912 / capacity.memory_bytes * SwapTotal), within one 4Ki page. Get `capacity.memory` from `kubectl get node $NODE -o jsonpath='{.status.capacity.memory}'`. All others are `0`.

   Expected with NoSwap or unset (A/B on the same node after `apiclient set settings.kubernetes.memory-swap-behavior=NoSwap`, or on a node without the setting): all `0`.

   With LimitedSwap but no swap device: all `0`. If any file reads `max`, kubelet's swap-controller probe failed and pods can swap without limit. Treat that as a bug.
5. Memory-hungry A/B, about 5 min. Use a pod with requests.memory 1Gi and limits.memory 1536Mi, image agnhost:2.52, args `["stress","--mem-total","2Gi","--mem-alloc-size","32Mi","--mem-alloc-sleep","100ms"]`, `restartPolicy: Never`. This is the same tool upstream uses (1.37:test/e2e_node/swap_test.go:411-428).
   - LimitedSwap with zram at 100% of memory (swap limit about 1Gi): the pod stays Running, `kubectl exec ... cat /sys/fs/cgroup/memory.swap.current` is above 0, and `memory.current` stays at or below 1536Mi.

     `kubectl get --raw /api/v1/nodes/$NODE/proxy/stats/summary | jq '.pods[]|select(.podRef.name=="swap-stress").containers[].swap'` shows `swapUsageBytes` above 0 (1.37:pkg/kubelet/stats/helper.go:307-325).
   - NoSwap or unset: the same pod ends `OOMKilled` (exit 137) and `memory.swap.current` stays 0.
   - With the default 1Gi zram on a larger node the swap limit is small, so size `--mem-total` to `limit + swap_limit/2`.
6. Negative path (only on a cgroup v1 node, see failCgroupV1): with `LimitedSwap`, `systemctl is-active kubelet` reports failed or activating and `journalctl -u kubelet` contains "swap feature is enabled and LimitedSwap but it is only supported with cgroupv2". The node never becomes Ready.

Upstream e2e coverage: `test/e2e_node/swap_test.go`.
- NodeConformance NoSwap table and the critical-pod case: 1.37:71-100.
- LimitedSwap "Basic functionality": 1.37:116-142.
- Stress tests that use more than node memory and more than the memory limit, plus the summary API test (1.33+): 1.37:206, :242, :292.
- Caveats, from source:
  - `getSwapTestPod` builds `resources` but never assigns them to the pod (1.31:296-326; 1.37:360-390), so every QoS row in both tables actually runs a BestEffort pod and only proves `0`.
  - `expectLimitedSwap` uses `Or(>= lower, <= upper)`, which is always true (1.37:486-492).
  - Only the stress contexts really exercise LimitedSwap. Do not count the table tests as evidence for step 4.

### Findings

- **[risk] `LimitedSwap` on a cgroup v1 node stops kubelet in every version (1.31-1.37).**
  - Input: `settings.boot.kernel-parameters."systemd.unified_cgroup_hierarchy"=["0"]` (plus reboot) together with `settings.kubernetes.memory-swap-behavior=LimitedSwap`.
  - Effect: kubelet returns "swap feature is enabled and LimitedSwap but it is only supported with cgroupv2" (1.31:cmd/kubelet/app/server.go:810-813 ... 1.37:912-915), with or without a swap device. The node never joins.
  - Setting it at runtime on a Ready cgroup v1 node takes that node NotReady at the next try-restart.
  - The Bottlerocket model has no cross-setting check, and 1.35+ now officially keeps cgroup v1 working (`failCgroupV1: false`), so this path is reachable.
  - Source-verified; not reproduced on a node.
  - Fix: document "LimitedSwap requires cgroup v2" on the setting. A validation that reads boot settings would be the strict option, but documentation is proportionate for a deprecated opt-in.
- **[risk] On cgroup v1 nodes with swap (default zram on 1.35+), `NoSwap` and unset do not stop swapping for containers without a memory limit.**
  - On v1, `ConfigureNoSwap` only sets `MemorySwapLimitInBytes = MemoryLimitInBytes` (1.35:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:483-490, "if memory limit is 0, memory swap limit is ignored"). containerd sets `Memory.Swap` only when a limit is non-zero (containerd-2.3.7 internal/cri/opts/spec_linux_opts.go:401-410).
  - So BestEffort and limit-less Burstable containers on a 1.35+ cgroup v1 node can use the 1 GiB zram device (corndog swap.rs:13). Containers with limits can still have part of their usage swapped ("Some swapping is still possible", same lines).
  - Inferred from source; not run.
  - Fix: document that cgroup v1 users who need no pod swap should set `settings.kernel.zram.size="0"`. Verify on a node by reading `memory.memsw.limit_in_bytes` for a BestEffort container, expected to be unlimited.
- **[nit] No user documentation for `memory-swap-behavior` (shipped in v1.42.0).**
  - Evidence: no entry in any website `data/settings/*/kubernetes.toml`.
  - The doc should say:
    - Values are `NoSwap`/`LimitedSwap`; the kebab aliases are accepted and normalized.
    - Only non-critical Burstable containers with memory request != limit get swap, sized `request / node memory * swap size`.
    - A swap device is required: 1.35+ has 1 GiB zram by default (`settings.kernel.zram.size`); 1.31-1.34 have none, so `LimitedSwap` there is a silent no-op unless the user provisions swap before kubelet starts.
    - cgroup v2 is required.
    - Changes apply to new containers after the kubelet restart.
    - On 1.31/1.32 (kernel 6.1), memory-backed volumes may be swapped (`PossibleMemoryBackedVolumesOnDisk`).
- **[nit] Dead error variant `InvalidMemorySwapBehavior`** (bottlerocket-settings-sdk/bottlerocket-settings-models/modeled-types/src/lib.rs:188-189). It is never constructed. Remove it in a later model release.

## kubelet failCgroupV1 (`settings.kubernetes.fail-cgroup-v1`: added in settings-sdk #108, reverted in #111; hardcoded by core-kit #792)

### Upstream per version

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `failCgroupV1` `*bool` (1.31:staging/src/k8s.io/kubelet/config/v1beta1/types.go:863); flag `--fail-cgroupv1` (1.31:cmd/kubelet/app/options/options.go:373) | `false` (1.31:pkg/kubelet/apis/config/v1beta1/defaults.go:271-272) | If true on a cgroup v1 host: error "...cgroup v1 support is in maintenance mode" (1.31:pkg/kubelet/apis/config/validation/validation_linux.go:31-32, called from validation.go:260). Kubelet exits (1.31:cmd/kubelet/app/server.go:251-252). Never checked on cgroup v2. | none | A cgroup v1 node gets Warning event `CgroupV1` and metric `kubelet_cgroup_version` (1.31:pkg/kubelet/kubelet.go:3072-3078, called at :1649). |
| 1.32 | yes | types.go:874; options.go:373 | `false` (defaults.go:289-290) | validation_linux.go:33 (called validation.go:301). Also new: `singleProcessOOMKill: false` is rejected on v1 (:38). | none | Event and metric moved to `cgroupVersionCheck` (1.32:pkg/kubelet/kubelet_linux.go:34-40, called at kubelet.go:1725). Logged at V(2) only. |
| 1.33 | yes | types.go:923; options.go:373 | `false` (defaults.go:292-293) | validation_linux.go:36 (called validation.go:328) | none | |
| 1.34 | yes | types.go:923; options.go:364 | `false` (defaults.go:292-293) | validation_linux.go:36 (called validation.go:328) | none | |
| 1.35 | yes | types.go:923; options.go:374 | **`true`** (defaults.go:292-293) | Same check; message is now "...cgroup v1 support is unsupported and will be removed in a future release" (validation_linux.go:36-37, called validation.go:331) | none | Event text `CgroupV1DeprecatedWarning` (1.35:pkg/kubelet/cm/container_manager.go:52) |
| 1.36 | yes | types.go:957; options.go:376 | `true` (defaults.go:293-294) | validation_linux.go:35 (called validation.go:334) | none | |
| 1.37 | yes | types.go:963; options.go:376 | `true` (defaults.go:291-292) | validation_linux.go:35 (called validation.go:362) | none | Internal type comment still says default false (1.37:pkg/kubelet/apis/config/types.go:555-558). The comment is stale; v1beta1 and defaults.go are authoritative. |

The only non-test consumers in any version are the flag and `validateKubeletOSConfiguration` (`grep -rn FailCgroupV1 pkg cmd`, excluding tests). No 1.35-1.37 kubelet path refuses cgroup v1 other than this field: the remaining v1 checks only log (for example 1.37:cmd/kubelet/app/server.go:679-682 for MemoryQoS). containerd 2.3 still runs on v1 and emits a deprecation warning (containerd-2.3.7 pkg/deprecation/deprecation.go:72).

### What changes between versions

- 1.31-1.34: default `false`. Omitting the field is the same as `false`. Kubelet starts on cgroup v1, emits a `CgroupV1` Warning event and sets `kubelet_cgroup_version=1`.
- 1.35-1.37: default `true` (defaults.go lines in the table). Without an explicit `false`, kubelet exits on cgroup v1 hosts with the validation error above. The error text changed from "maintenance mode" to "unsupported and will be removed".
- On cgroup v2 nothing changes in any version: the value is only read under `isCgroup1` (validation_linux.go lines in the table).
- No e2e_node test exercises this field on cgroup v1. The only mention sets it true on cgroup v2 inside a test that is skipped as "currently broken" (1.37:test/e2e_node/node_container_manager_test.go:89-90, 119). The defaults are covered by unit tests (1.37:pkg/kubelet/apis/config/v1beta1/defaults_test.go:129).

### Bottlerocket implementation

- **Model:** none today.
  - `fail-cgroup-v1` was added in settings-sdk #108 (released in tag `bottlerocket-settings-models-v0.18.0`), fixed in #110 (`v0.19.0`) and removed in #111 (`v0.20.0`; bottlerocket-settings-sdk/bottlerocket-settings-models/CHANGELOG.md:169, 182, 194).
  - No Bottlerocket release shipped 0.18/0.19: `git show v1.53.0:sources/Cargo.toml` pins v0.17.0 and v1.54.0 pins v0.20.0. No core-kit release did either: v12.2.0 pins v0.17.0 and v12.3.0 pins v0.20.0.
  - So no datastore can contain the key, and no migration is needed. None exists, which is correct.
- **Templates:**
  - Literal `failCgroupV1: false` (a YAML bool, no helper, no setting) at kubernetes-1.35/kubelet-config:221, 1.36:209 and 1.37:215. Absent in 1.31-1.34.
  - Added in core-kit commit 9d0232319 (PR #792), released in core-kit v12.2.0. That is the first core-kit that 1.35 variants shipped with (bottlerocket v1.53.0, CHANGELOG "Add new kubernetes 1.35 variants (#4735)"). core-kit v12.1.0 carried the 1.35 beta without the line, but no variant used it.
  - Correctness per version:
    - 1.31-1.34: the default is already `false`. Omitting the line is equivalent, and adding it would be a no-op (the field exists since 1.31). No version is missing a needed line.
    - 1.35-1.37: the line is required for the cgroup v1 opt-in to keep working.
    - For cgroup v2 users it changes no behavior in any version. Only configz differs (`false` instead of the upstream default `true`).
  - Kubelet flags (`kubelet-exec-start-conf`) never pass `--fail-cgroupv1`, so nothing overrides the config file.
- **How users opt into cgroup v1:**
  - Boot settings model `BootSettingsV1`, with `kernel` and `init` maps (aliases `kernel-parameters`, `init-parameters`) and `reboot-to-reconcile` (bottlerocket-settings-sdk/bottlerocket-settings-models/settings-models/src/boot.rs:8-24).
  - prairiedog writes these maps as `init.*` / `kernel.*` bootconfig keys (kits/bottlerocket-core-kit/sources/api/prairiedog/src/bootconfig.rs:62-75).
  - The tested path, from bottlerocket PR #4735 (1.35 node Ready on cgroup v1):

    ```
    [settings.boot]
    reboot-to-reconcile = true
    [settings.boot.kernel-parameters]
    "systemd.unified_cgroup_hierarchy" = ["0"]
    "SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE" = ["1"]
    ```
  - The `settings.boot.init."systemd.unified_cgroup_hierarchy"` form in the settings-sdk #108 description was not tested. Inferred to work only if systemd parses init (post-`--`) arguments from `/proc/cmdline`.
  - systemd-257 (used by the 1.34-1.37 variants, bottlerocket/variants/aws-k8s-1.34/Cargo.toml:26) also needs `SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1`.
    - That parameter ships as bootconfig `21-cgroup-enable-legacy-force.conf` (packages/systemd-257/systemd-cgroup-legacy-force-bootconfig.conf:1).
    - Since core-kit 9e70bbb19 (in v18.0.0) the file is in the `systemd-257-cgroups-v1` subpackage. `systemd-257` requires that subpackage unless the image is UKI (systemd-257.spec:140, 229-237, 1003-1004).
    - No k8s variant enables `uki-image`, so the file is present today.
  - 1.31-1.33 use systemd-252 and need only `systemd.unified_cgroup_hierarchy=0` (inferred from the absence of the systemd-257 package in those variants). All 1.31-1.37 variants default to cgroup v2: no `unified_cgroup_hierarchy` in any `bottlerocket/variants/*k8s-1.3*/Cargo.toml`.
- **Docs:** no website entry (correct, since there is no setting). The cgroup v1 opt-in and Bottlerocket's override of the 1.35 upstream default are not documented anywhere on the site (grep for `cgroup` under `data/settings` and `content/` finds only package lists and old variant definitions).

### How to verify it works on a node

1. Default cgroup v2 node (any version), about 1 min:

   ```
   stat -fc %T /sys/fs/cgroup                                   # cgroup2fs
   grep '^failCgroupV1' /etc/kubernetes/kubelet/config            # present 1.35-1.37 only
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq .kubeletconfig.failCgroupV1    # false on 1.31-1.37
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/metrics" | grep '^kubelet_cgroup_version'      # 2
   kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name=$NODE,reason=CgroupV1   # none
   ```
2. cgroup v1 node: launch with the user data above (`reboot-to-reconcile` reboots once during first boot; about 10 min including join), or `apiclient apply` it on a running node and then `apiclient reboot`.

   ```
   stat -fc %T /sys/fs/cgroup                                   # tmpfs
   tr ' ' '\n' < /proc/cmdline | grep -i cgroup                 # unified_cgroup_hierarchy=0, SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1 (1.34+)
   systemctl is-active kubelet; kubectl get node $NODE           # active / Ready on 1.31-1.37
   kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name=$NODE,reason=CgroupV1   # 1 Warning
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/metrics" | grep '^kubelet_cgroup_version'      # 1
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq .kubeletconfig.failCgroupV1    # false
   # 1.35+ with zram: swap leak check for finding 2 (expected unlimited, ~9223372036854771712, for a BestEffort container)
   cat /sys/fs/cgroup/memory/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod*/cri-containerd-*.scope/memory.memsw.limit_in_bytes
   ```
3. A/B for the hardcode (1.35+): this needs a custom core-kit build without `kubernetes-1.35/kubelet-config:221` (about 1 h including build). Expected: `journalctl -u kubelet` contains "failed to validate kubelet configuration, error: kubelet is configured to not run on a host using cgroup v1. cgroup v1 support is unsupported and will be removed in a future release", kubelet restart-loops, and the node never registers. The same build on cgroup v2 joins normally (configz then shows `true`).

Upstream e2e: none exercises this behavior (see "What changes between versions").

### Findings

- **[nit] Hardcoding `failCgroupV1: false` only in 1.35-1.37 is correct.**
  - 1.31-1.34 already default to `false` (defaults.go lines in the table), so no version is missing a needed line.
  - For cgroup v2 hosts the field is never read (validation_linux.go `isCgroup1` guard).
  - Optional clarity: a template comment explaining that 1.35 flipped the default would stop someone from "aligning" templates by deleting it.
  - Users cannot opt into upstream's strict `true`. That is a product choice, not a bug.
- **[nit] cgroup v1 opt-in on 1.34+ depends on the legacy-force bootconfig, which core-kit v18.0.0 now leaves out of UKI images** (packages/systemd-257/systemd-257.spec:140, 229-237).
  - No k8s variant is UKI today, so this is not reachable.
  - If a UKI k8s variant appears, `failCgroupV1: false` alone will not keep cgroup v1 working (inferred systemd 256+ behavior). Users would also have to pass `SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1` themselves, as PR #4735 did.
- **[nit] The cgroup v1 opt-in procedure and its limits are undocumented.**
  - Limits to cover: kubelet warning events, `LimitedSwap` incompatibility (swap finding 1), and zram swap not enforced for limit-less pods (swap finding 2).
  - Add a short "cgroup v1 (deprecated)" note next to the boot settings docs.

## Script feedback

- `python3 -I $T/k8s-field-report.py field memorySwap.swapBehavior`
  - The fatal runtime check ("LimitedSwap ... only supported with cgroupv2", which makes kubelet exit) appears only as a truncated consumer line (`cmd/kubelet/app/server.go:811: if !isCgroup2UnifiedMode() && ...`). The `return fmt.Errorf` on the next lines is not shown, so a reader cannot tell it is a startup failure.
  - Suggest: for each consumer, show 3 lines of context and tag sites that `return` an error inside `Run`/`run` as "STARTUP FAILURE".
  - Consumer lines are also cut at about 150 characters ("FailSwap").
- `python3 -I $T/k8s-field-report.py gate NodeSwap`
  - Prints only the spec. It does not list where the gate is checked (validation.go gate-off error, server.go, kuberuntime `GetContainerSwapBehavior`, nodestatus setters). Those sites are what answers "what happens when the gate is off".
  - It also drops the `// remove in 1.37` comment on the 1.34+ spec. That comment matters, because rendering `featureGates.NodeSwap` would break kubelet once the gate is removed (it is still present in 1.37.1).
  - Suggest: list `Enabled(features.<Gate>)` call sites and surface trailing removal comments.
- `python3 -I $T/k8s-field-report.py field failCgroupV1`
  - Accurate: it correctly flags the 1.34 to 1.35 default flip.
  - "consumers: 1" counts only the flag, while the real behavior is in `validation_linux.go`. That file is shown under "validation", so this is only a labeling nit. It could note "only enforced when !IsCgroup2UnifiedMode()".
- `python3 -I $T/kubelet-config-lint.py`
  - Says "every rendered path exists upstream" and nothing else. The most consequential lines in this group are hardcoded literals that override upstream defaults: `failSwapOn: false` in all versions (default true) and `failCgroupV1: false` in 1.35-1.37 (default true). The lint gives no hint about them.
  - Suggest an informational LITERAL listing for each non-templated key: rendered value, upstream default for that version, and a marker when they differ.
- `python3 -I $T/template-drift.py kubernetes --matrix`
  - Only tracks `settings.*` keys, so the hardcoded `failCgroupV1` that exists only in 1.35-1.37 is invisible. Here the asymmetry is correct, but a deleted or misplaced literal would never be flagged.
  - Suggest a `--literals` mode that diffs non-templated top-level keys across versions, ideally annotated with each version's default from the field report.
- `skills/add-kubernetes-setting/scripts/verify-node.sh` (read, not run: no AWS)
  - `--setting` always prefixes `settings.kubernetes.`, so it cannot read back the settings this group depends on: `settings.kernel.zram.size` and `settings.boot.*`.
  - It has no check for per-pod cgroup files (`memory.swap.max`, `memory.memsw.limit_in_bytes`), `/proc/swaps`, node events or kubelet metrics. Those are the only proof that swap behavior took effect, because configz just echoes the config.
  - Suggest accepting a full settings key, plus `--pod NAME --cgroup-file FILE --expect V` and `--metric NAME`.
- The field report lists `e2e_node tests mentioning it: test/e2e_node/swap_test.go`. That is accurate as "mentions", but the test's QoS tables never apply pod resources (1.37:test/e2e_node/swap_test.go:360-390), and `expectLimitedSwap` is a tautology (:486-492). A skill that treats "mentioned by e2e" as "covered by e2e" would be misled. The skill text should say so, or the tool could print the `It(...)`/`Entry(...)` names so a human can judge.
