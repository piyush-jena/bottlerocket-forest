<!-- Audit of shipped settings, 2026-11-17, against core-kit a4f438b1f, settings-sdk 06d9d1a, bottlerocket b7c6c274,
     and the EKS-D sources packaged in core-kit for Kubernetes 1.31-1.37 (containerd 1.7/2.2/2.3).
     Line numbers drift; re-run scripts/k8s-field-report.py before relying on a citation.
     Status of the findings as of this date: see ../../SKILL.md "Known open findings". -->

# memory-oom

Scope: `settings.kubernetes.single-process-oom-kill`, `settings.kubernetes.memory-reservation-policy`, `settings.kubernetes.memory-throttling-factor`.
Upstream paths are relative to each version's `src/` under `~/.cache/br-package-src/kubernetes-1.3X-*/src`.
Bottlerocket paths are relative to the grove root `/home/fedora/Repositories/bottlerocket-forest/groves/k8s-settings`.

Facts shared by all three settings:

- Bottlerocket renders the kubelet config to `/etc/kubernetes/kubelet/config` (`kits/bottlerocket-core-kit/packages/kubernetes-1.37/kubelet-exec-start-conf`, `--config`), uses the systemd cgroup driver with `cgroupRoot: "/"` (`kubernetes-1.37/kubelet-config:142-143`) and containerd `SystemdCgroup = true` (`packages/containerd-2.3/containerd-config-toml_k8s_containerd_sock:70`). Container cgroups are therefore `/sys/fs/cgroup/kubepods.slice/[kubepods-<qos>.slice/]kubepods[-<qos>]-pod<UID with _>.slice/cri-containerd-<id>.scope`.
- No Bottlerocket setting can change kubelet feature gates. The only `featureGates` the templates render are `DynamicResourceAllocation` and `MutableCSINodeAllocatableCount` (`kubernetes-1.33/kubelet-config:235`, `1.34:233`, `1.35:242`, `1.36:230`, `1.37:236-238`; none in 1.31/1.32). So MemoryQoS is whatever the upstream default is per version.
- `enforceNodeAllocatable` is not rendered, so the default `["pods"]` applies (`1.37:pkg/kubelet/apis/config/v1beta1/defaults.go:52,272`). kube-reserved/system-reserved cgroups therefore never get MemoryQoS `memory.min` (`1.37:pkg/kubelet/cm/node_container_manager_linux.go:122-131,170-179`).
- The Bottlerocket API stores the serialized model, not the user's raw string (`kits/bottlerocket-core-kit/sources/api/apiserver/src/server/controller.rs:420-421`), so enum aliases are canonicalized before rendering. `apiclient set k=v` converts `0.8` to a JSON number (`apiserver/src/server/mod.rs:330-345`, `massage_set_input`).
- Handlebars `{{#if}}` is the built-in helper of handlebars 4.5.0 (`sources/Cargo.lock:3034-3035`). For numbers it is `f.is_normal()` (`~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/handlebars-4.5.0/src/json/value.rs:151-157`): it drops 0 and every subnormal float, not just 0.

## settings.kubernetes.single-process-oom-kill

### Upstream per version

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | no | - (no flag) | n/a. kubelet always writes `memory.oom.group=1` on every container cgroup on cgroup v2 (`1.31:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:249-257`) | n/a. A rendered key would be ignored by the lenient decoder | none | group kill is unconditional on v2 |
| 1.32 | yes | `singleProcessOOMKill`, `*bool` (`1.32:staging/src/k8s.io/kubelet/config/v1beta1/types.go:365`) | nil, resolved at startup: cgroup v1 forced `true`, cgroup v2 `false` unless set (`1.32:pkg/kubelet/kubelet.go:701-712`). No v1beta1 defaulting | Linux cgroup v1: explicit `false` is an error (`1.32:pkg/kubelet/apis/config/validation/validation_linux.go:37-38`). Non-Linux: any non-nil is an error (`validation_others.go:31`, `validation_windows.go:41`) | none | effect site: `oom.group` only if cgroup v2 and value false (`1.32:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:283-290`) |
| 1.33 | yes | `types.go:405` | `kubelet.go:737-748` | `validation_linux.go:40-41` | none | effect `kuberuntime_container_linux.go:312` |
| 1.34 | yes | `types.go:406` | `kubelet.go:736-747` | `validation_linux.go:40-41` | none | effect `kuberuntime_container_linux.go:314` |
| 1.35 | yes | `types.go:406` | `kubelet.go:740-751` (v2 default false at :746-747; :744 is the v1 forced true) | `validation_linux.go:40-41` | none | effect `kuberuntime_container_linux.go:314` |
| 1.36 | yes | `types.go:430` | `kubelet.go:746-757` | `validation_linux.go:39-40` | none | effect `kuberuntime_container_linux.go:323` |
| 1.37 | yes | `types.go:430` | `kubelet.go:775-786` | `validation_linux.go:39-40` | none | effect `kuberuntime_container_linux.go:394` |

### What changes between versions

- 1.31 -> 1.32: the field is added. Before it, cgroup v2 always gets `memory.oom.group=1` (`1.31:...kuberuntime_container_linux.go:250-256`). From 1.32 that write is conditional on `!ptr.Deref(m.singleProcessOOMKill, true)` (`1.32:...kuberuntime_container_linux.go:283`).
- 1.32 -> 1.37: none. The type comment, startup resolution, validation and effect site are the same code in every version; only line numbers move (table above). No feature gate in any version. `memory.oom.group` is written only on container cgroups, never on the pod cgroup (`1.37: grep "oom.group" pkg cmd` finds only `kuberuntime_container_linux.go:399`).
- Correction to the brief: on 1.35 the cgroup v2 default false is `1.35:pkg/kubelet/kubelet.go:746-747`. Line 744 is the cgroup v1 forced `true`.

### Bottlerocket implementation

- Model: `single_process_oom_kill: bool` (`bottlerocket-settings-sdk/bottlerocket-settings-models/settings-extensions/kubernetes/src/lib.rs:98`), kebab name `single-process-oom-kill`, no extra validation. Accepts `true`/`false` on every variant, including 1.31.
  - Bottlerocket accepts but kubelet rejects: `false` on a cgroup v1 host would fail kubelet validation, but false is never rendered (see templates), so this cannot happen. Nothing else.
  - kubelet accepts but Bottlerocket rejects: nothing (both are booleans; "unset" is the absent key on both sides).
- Templates: `{{#if settings.kubernetes.single-process-oom-kill}}singleProcessOOMKill: {{...}}{{/if}}` at top-level YAML key `singleProcessOOMKill`, rendered as an unquoted YAML boolean `true`:
  `kubernetes-1.32/kubelet-config:216-217`, `1.33:219-220`, `1.34:217-218`, `1.35:226-227`, `1.36:214-215`, `1.37:220-221`. Not in `1.31/kubelet-config`.
  - unset or `false`: no key, kubelet resolves nil.
  - Is dropping `false` harmless? Confirmed on both cgroup versions:
    - cgroup v2: nil resolves to `ptr.To(false)` (`1.37:pkg/kubelet/kubelet.go:781-782`), identical to an explicit false. Both give `memory.oom.group=1`.
    - cgroup v1: nil resolves to `true` (`1.37:kubelet.go:777-779`). An explicit false would be a validation error and kubelet would not start (`1.37:validation_linux.go:39-40`). So dropping false is not just harmless, it protects a cgroup v1 node. (cgroup v1 is not the default on Bottlerocket k8s variants. Switching to it via boot parameters is undocumented for k8s variants and is inferred possible only.)
  - Supported upstream but not rendered: none (1.32-1.37 all render). Rendered where unsupported: none (1.31 not rendered).
- Migration: `bottlerocket/sources/settings-migrations/v1.39.0/kubelet-setting-container-log-single-process-oom-kill/src/main.rs` (AddSettingsMigration for `settings.kubernetes.single-process-oom-kill`), listed in `bottlerocket/Release.toml:418-420` under `(1.38.0, 1.39.0)` and in `bottlerocket/sources/Cargo.toml:55`. Present.
- Docs: `bottlerocket-project-website/data/settings/1.39.x/kubernetes.toml:37-55`. Accurate, and states "only available for Kubernetes 1.32 and later variants". It does not state the default (unset = kubelet default = group kill on cgroup v2).

### How to verify it works on a node

Setup: one node per version under test with the setting `true`, and one control node of the same variant without it (A/B). Apply with `apiclient set settings.kubernetes.single-process-oom-kill=true` (kubelet restarts). Existing containers keep their cgroup files, so create the test pods after the change.

1. Rendered and loaded (about 1 min):
   ```
   apiclient get settings.kubernetes.single-process-oom-kill
   # sheltie:
   grep -n singleProcessOOMKill /etc/kubernetes/kubelet/config
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig.singleProcessOOMKill'
   ```
   Expected: 1.32-1.37 `true` on A, `null` on B (also `null` when set to `false`). 1.31: `null` on both (not rendered).
2. cgroup file (about 2 min). Pod spec, adapted from the upstream multi-process OOM target (`1.37:test/e2e_node/oomkiller_linux_test.go:205-218,275-300`):
   ```yaml
   apiVersion: v1
   kind: Pod
   metadata: {name: oom-multi}
   spec:
     nodeName: NODE
     restartPolicy: Never
     containers:
     - name: c
       image: public.ecr.aws/docker/library/busybox:1.36
       command: ["sh", "-c", "sleep 20 && dd if=/dev/zero of=/dev/null bs=20M & sleep 86400"]
       resources:
         requests: {memory: 15Mi}
         limits: {memory: 15Mi}
   ```
   During the first 20 s: `kubectl exec oom-multi -- cat /sys/fs/cgroup/memory.oom.group` (the container sees its own cgroup through its private cgroup namespace).
   Expected on cgroup v2: B `1` on every version; A `0` on 1.32-1.37, `1` on 1.31.
3. Behavior (about 1 min after step 2):
   - B (and A on 1.31): the whole container is killed. `kubectl get pod oom-multi -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} {.status.containerStatuses[0].state.terminated.exitCode}'` gives `OOMKilled 137`, phase `Failed`.
   - A on 1.32-1.37: only `dd` is killed. Pod stays `Running` and `kubectl exec oom-multi -- grep oom_kill /sys/fs/cgroup/memory.events` shows `oom_kill 1`. `journalctl -k | grep -i "killed process"` on the host shows `dd`.
4. Negative check (optional): kubelet must not log `singleProcessOOMKill must not be explicitly set to false`: `journalctl -u kubelet | grep -i singleProcessOOMKill` is empty.

Cost: about 10 min for A/B per version after nodes exist. Upstream test: `test/e2e_node/oomkiller_linux_test.go` "OOMKiller [LinuxOnly]" cases "multi process container (single process kill enabled/disabled)" (`1.37:test/e2e_node/oomkiller_linux_test.go:88-114`).

### Findings

- [nit] The setting is accepted but has no effect on 1.31 variants: the shared model accepts it (`lib.rs:98`), 1.31 does not render it, and 1.31 kubelet always group-kills. The docs already say 1.32+. No fix needed beyond keeping that note.
- [nit] Docs have no default line. Suggest adding "unset: kubelet default; on cgroup v2 all processes in a container are OOM-killed together (`memory.oom.group=1`); `false` is the same as unset".
- No bugs. `{{#if}}` is the correct helper here (see above), and 1.32-1.37 behave the same.

## settings.kubernetes.memory-reservation-policy

### Upstream per version

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | no | - | - | - | MemoryQoS Alpha/false (`1.31:pkg/features/kube_features.go:1130`) | MemoryQoS-on behavior (if enabled) is memory.min = requests at container, pod and QoS level, no policy |
| 1.32 | no | - | - | - | Alpha/false (`1.32:pkg/features/versioned_kube_features.go:529-531`) | same |
| 1.33 | no | - | - | - | Alpha/false (`1.33:pkg/features/kube_features.go:1517`) | same |
| 1.34 | no | - | - | - | Alpha/false (`1.34:kube_features.go:1484`) | same |
| 1.35 | no | - | - | - | Alpha/false (`1.35:kube_features.go:1526`) | same (`1.35:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:158-160`, `1.35:pkg/kubelet/cm/qos_container_manager_linux.go:290-314`) |
| 1.36 | yes | `memoryReservationPolicy`, `MemoryReservationPolicy` string (`1.36:staging/src/k8s.io/kubelet/config/v1beta1/types.go:911`, values `None` :111, `TieredReservation` :114) | `None` (`1.36:pkg/kubelet/apis/config/v1beta1/defaults.go:45,299-300`) | must be exactly `None` or `TieredReservation` (`1.36:pkg/kubelet/apis/config/validation/validation.go:359-363`); `TieredReservation` with MemoryQoS off is an error (`:354-357`) | Alpha/false (`1.36:kube_features.go:1677`) | gate is off and cannot be enabled on Bottlerocket, so `TieredReservation` would stop kubelet |
| 1.37 | yes | same type (`1.37:types.go:917`) | `None` (`1.37:defaults.go:43,294-295`) | same rules (`1.37:validation.go:383-392`) | Beta/true (`1.37:kube_features.go:1845-1848`) | effective; no gate dependencies (`1.37:kube_features.go:2739`) |

### What changes between versions

- 1.35 -> 1.36: field added. With MemoryQoS on, protection is no longer unconditional: `None` writes `memory.min=0` and `memory.low=0` on containers (`1.36:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:158-169`); `TieredReservation` writes container `memory.min=request` for Guaranteed pods and `memory.low=request` for Burstable pods. The pod cgroup gets the same key with the pod's request (`1.36:pkg/kubelet/cm/helpers_linux.go:211-225`), and the QoS cgroups get sums (`1.36:pkg/kubelet/cm/qos_container_manager_linux.go:292-325`). Before 1.36 (gate on), container and pod `memory.min=request` and QoS `memory.min=sums` (`1.35:...kuberuntime_container_linux.go:158-160`, `1.35:pkg/kubelet/cm/helpers_linux.go:210-220`, `1.35:...qos_container_manager_linux.go:290-314`). On Bottlerocket 1.36 none of this runs because the gate is off.
- 1.36 -> 1.37:
  - The gate becomes Beta/on, so the policy is effective (`1.37:kube_features.go:1845-1848`).
  - The QoS-level update loop runs only for `TieredReservation` (`1.37:...qos_container_manager_linux.go:405-408`). For `None`, stale `memory.low` on the burstable slice and `memory.min/low` on `kubepods.slice` are reset once at startup (`:113-123,150-166`).
  - Kubelet metrics `kubelet_memory_qos_node_memory_min_bytes` / `_low_bytes` are registered when the gate is on (`1.37:pkg/kubelet/metrics/metrics.go:171-172,993-1011,1522-1524`).
  - Validation and enum are unchanged.

### Bottlerocket implementation

- Model: `memory_reservation_policy: KubernetesMemoryReservationPolicy` (`settings-extensions/kubernetes/src/lib.rs:91`). It is an enum with variants `None`, `TieredReservation`, plus serde aliases `none`, `tiered-reservation` (`bottlerocket-settings-models/modeled-types/src/kubernetes.rs:1466-1474`). The stored and rendered value is always the canonical variant name (`controller.rs:420`).
  - Compared with upstream 1.37, the enum matches exactly: upstream is case-sensitive `None` | `TieredReservation` (`1.37:validation.go:388-392`), and Bottlerocket's aliases are canonicalized before rendering. Upstream also accepts `""` (defaults to None); Bottlerocket rejects `""`. Harmless.
  - Bottlerocket accepts but kubelet rejects: on 1.36, `TieredReservation` would be rejected (`1.36:validation.go:354-357`), but 1.36 does not render it. On 1.37, nothing (the gate is always on, because no Bottlerocket setting can disable it).
  - kubelet accepts but Bottlerocket rejects: `""` only.
  - The setting is accepted on all variants 1.31-1.37 and silently ignored on 1.31-1.36.
- Templates: only `kubernetes-1.37/kubelet-config:205-207`, `{{#if settings.kubernetes.memory-reservation-policy}}memoryReservationPolicy: {{...}}{{/if}}`. This is a top-level key with an unquoted YAML string. `None` is a string, not null, in YAML (go-yaml null forms are `~`, `null`, `Null`, `NULL`, empty). Unset gives no key, so kubelet defaults to `None`. No `featureGates` entry is needed in 1.37 (Beta default true).
  - Supported upstream but not rendered: 1.36. This is correct: `None` is a no-op there and `TieredReservation` would keep kubelet from starting (gate Alpha/off).
  - Rendered where unsupported or gated off: none.
  - Is 1.37-only rendering right? Yes.
- Migration: `bottlerocket/sources/settings-migrations/v1.66.0/kubernetes-memory-qos-settings/src/main.rs` (AddSettingsMigration for both MemoryQoS keys), `bottlerocket/Release.toml:483-487` under `(1.65.0, 1.66.0)`, `bottlerocket/sources/Cargo.toml:77`. Present.
- Docs: missing. There is no entry for `memory-reservation-policy` or `memory-throttling-factor` anywhere in the website clone (`bottlerocket-project-website/` at a826822, 2026-11-13). `data/settings/1.66.x/` has only `kernel.toml`, and no open website PR adds them (open PRs checked with `gh pr list`; #618 is the 1.69.0 refresh and does not mention them).

### How to verify it works on a node

Nodes: an aws-k8s-1.37 node A with `apiclient set settings.kubernetes.memory-reservation-policy=TieredReservation`, a control 1.37 node B without it, and optionally a 1.36 node C with the setting (expect no effect). Create pods after the setting change. Check page size with `getconf PAGESIZE` (values below assume 4096).

Shared MemoryQoS pod set (also used for memory-throttling-factor):

```yaml
apiVersion: v1
kind: Pod
metadata: {name: mq-burstable}
spec:
  nodeName: NODE
  containers:
  - {name: c, image: public.ecr.aws/docker/library/busybox:1.36, command: ["sleep","infinity"],
     resources: {requests: {memory: 128Mi, cpu: 50m}, limits: {memory: 256Mi, cpu: 100m}}}
---
apiVersion: v1
kind: Pod
metadata: {name: mq-guaranteed}
spec:
  nodeName: NODE
  containers:
  - {name: c, image: public.ecr.aws/docker/library/busybox:1.36, command: ["sleep","infinity"],
     resources: {requests: {memory: 256Mi, cpu: 100m}, limits: {memory: 256Mi, cpu: 100m}}}
---
apiVersion: v1
kind: Pod
metadata: {name: mq-besteffort}
spec:
  nodeName: NODE
  containers:
  - {name: c, image: public.ecr.aws/docker/library/busybox:1.36, command: ["sleep","infinity"]}
---
apiVersion: v1
kind: Pod
metadata: {name: mq-nolimit}
spec:
  nodeName: NODE
  containers:
  - {name: c, image: public.ecr.aws/docker/library/busybox:1.36, command: ["sleep","infinity"],
     resources: {requests: {memory: 128Mi}}}
```

Read the files:

```
# container level, no host access needed
for p in mq-burstable mq-guaranteed mq-besteffort mq-nolimit; do
  kubectl exec $p -- sh -c 'echo $(cat /sys/fs/cgroup/memory.min) $(cat /sys/fs/cgroup/memory.low) $(cat /sys/fs/cgroup/memory.high) $(cat /sys/fs/cgroup/memory.oom.group)'; done
# pod and QoS level, via sheltie on the node
U=$(kubectl get pod mq-burstable -o jsonpath='{.metadata.uid}' | tr - _)
cat /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod$U.slice/memory.{min,low,high}
U=$(kubectl get pod mq-guaranteed -o jsonpath='{.metadata.uid}' | tr - _)
cat /sys/fs/cgroup/kubepods.slice/kubepods-pod$U.slice/memory.{min,low,high}
cat /sys/fs/cgroup/kubepods.slice/memory.{min,low} /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/memory.low
kubectl get --raw "/api/v1/nodes/$NODE/proxy/metrics" | grep -E 'kubelet_memory_qos_node_memory_(min|low)_bytes|kubernetes_feature_enabled\{name="MemoryQoS"'
kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig | {memoryReservationPolicy, memoryThrottlingFactor}'
```

Expected (container `min low high oom.group`):

| pod | 1.37 B (unset = None) | 1.37 A (TieredReservation) | 1.31-1.36 any setting |
|---|---|---|---|
| mq-burstable | `0 0 max 1` | `0 134217728 max 1` | `0 0 max 1` |
| mq-guaranteed | `0 0 max 1` | `268435456 0 max 1` | `0 0 max 1` |
| mq-besteffort | `0 0 max 1` | `0 0 max 1` | `0 0 max 1` |
| mq-nolimit | `0 0 max 1` | `0 134217728 max 1` | `0 0 max 1` |

- Pod level on A: burstable pod `memory.low=134217728`, `memory.min=0`; guaranteed pod `memory.min=268435456`. On B: pod `memory.min` and `memory.low` are 0.
- QoS level on A: `kubepods.slice/memory.min` = `..._min_bytes + ..._low_bytes`, and `kubepods.slice/memory.low` = `kubepods-burstable.slice/memory.low` = `..._low_bytes` (`1.37:...qos_container_manager_linux.go:356-368`). The values include every DaemonSet pod on the node, so compare deltas before and after creating the pods: +134217728 low (burstable), +268435456 min (guaranteed). Allow up to 1 min for the periodic update (`:46,184`). On B: all 0 and metrics 0.
- configz: 1.37 shows `"TieredReservation"` on A and `"None"` on B. 1.36 shows `"None"` because it is not rendered. 1.31-1.35 show `null`.
- `kubernetes_feature_enabled{name="MemoryQoS",...} 1` on 1.37 and `0` on 1.31-1.36.
- Rollback: `apiclient set settings.kubernetes.memory-reservation-policy=None` resets the QoS cgroups at the next kubelet start. Already-running containers keep their `memory.low`/`memory.min` until they are recreated (upstream calls this a known limitation, `1.37:test/e2e_node/memory_qos_test.go:1271-1307`).

Cost: about 15 min per node after it exists. Upstream tests: `test/e2e_node/memory_qos_test.go` "memory protection [memoryReservationPolicy=TieredReservation]" and "memoryReservationPolicy" (`1.37:test/e2e_node/memory_qos_test.go:240-423,935-1043`). The tests use the same `cgroupsPerQOS: true`, `enforceNodeAllocatable: [pods]` that Bottlerocket gets by default (`:198-213`).

### Findings

- [risk] Docs are missing for both MemoryQoS settings. Evidence: no matches for `memory-reservation-policy` or `memory-throttling-factor` in the website clone, and no `data/settings/1.66.x/kubernetes.toml`. Effect: users of 1.31-1.36 variants can set them through the API, nothing happens, and nothing tells them it only works on 1.37+. Fix: add entries that say "Kubernetes 1.37+ only, ignored on earlier variants", list accepted values `None`/`TieredReservation`, give the default (unset = `None`, no memory.min/low), describe the Guaranteed min / Burstable low tiers, and note that rollback only applies to new containers.
- No bugs. The 1.37-only rendering is correct, the enum matches upstream, and the migration exists.

## settings.kubernetes.memory-throttling-factor

### Upstream per version

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `memoryThrottlingFactor`, `*float64` (`1.31:staging/src/k8s.io/kubelet/config/v1beta1/types.go:816`) | 0.9 (`1.31:pkg/kubelet/apis/config/v1beta1/defaults.go:41,274-276`) | `<= 0` or `> 1.0` is an error (`1.31:pkg/kubelet/apis/config/validation/validation.go:280-282`); nil with the gate on is an error (`:277-279`, unreachable after defaulting) | Alpha/false (`1.31:kube_features.go:1130`) | inert: used only when the gate is on (`1.31:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:113-146`) |
| 1.32 | yes | `types.go:827` | 0.9 (`defaults.go:44,292-294`) | `validation.go:318-323` | Alpha/false | inert |
| 1.33 | yes | `types.go:876` | 0.9 (`defaults.go:44,295-297`) | `validation.go:345-350` | Alpha/false | inert |
| 1.34 | yes | `types.go:877` | 0.9 (`defaults.go:44,295-297`) | `validation.go:341-346` | Alpha/false | inert |
| 1.35 | yes | `types.go:877` | 0.9 (`defaults.go:44,295-297`) | `validation.go:344-349` | Alpha/false | inert |
| 1.36 | yes | `types.go:901` | 0.9 (`1.36:defaults.go:44,296-298`) | `1.36:validation.go:347-352` | Alpha/false (`1.36:kube_features.go:1677`) | inert |
| 1.37 | yes | `types.go:907`, comment "If nil, memory.high is not set. Default: nil" (`1.37:types.go:899-907`) | nil (no defaulting in `1.37:defaults.go`) | `<= 0` or `> 1.0` is an error (`1.37:validation.go:379-381`); with MemoryQoS off any non-nil value other than 0.9 is an error (`:50,375-377`) | Beta/true (`1.37:kube_features.go:1845-1848`) | effective |

### What changes between versions

- 1.31 -> 1.36: the field and its semantics do not change (only the `utilpointer` -> `ptr` refactor in 1.32). With the gate on, the container formula is `memory.high = floor((req + f*(limit-req)) / page) * page`. It applies only when the memory request differs from the limit, so Guaranteed containers and BestEffort containers (0 == 0) get no `memory.high`. If the limit is 0, node allocatable replaces it, and the value is written only if it is above the request (`1.36:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:173-195`, `1.35:...:164-186`, `1.31:...:124-146`). Default 0.9. On Bottlerocket all of this is unreachable because the gate is Alpha/off.
- 1.36 -> 1.37 (the KEP-2570 rework):
  - Default 0.9 is replaced by nil, and nil means no `memory.high` anywhere (`1.37:types.go:902-904`; `kuberuntime_container_linux.go:226` checks `m.memoryThrottlingFactor != nil`).
  - BestEffort containers now get `memory.high = floor(f*allocatable/page)*page`: the condition is `memoryRequest != memoryLimitSpec || memoryRequest == 0` (`1.37:...kuberuntime_container_linux.go:226,247-254`; unit test "BestEffort pod - set memory.high based on node capacity", `1.37:pkg/kubelet/kuberuntime/kuberuntime_container_linux_test.go:740-746`, kubernetes/kubernetes#137685). "allocatable" here is capacity minus kube-reserved minus system-reserved, without the eviction threshold (`1.37:pkg/kubelet/kubelet.go:836`, `pkg/kubelet/cm/node_container_manager_linux.go:259-282`). It equals `kubepods.slice/memory.max` rounded to a page.
  - New pod-level `memory.high` with the same formula when PodLevelResources (Beta/on in 1.37) is used and the pod declares memory limits (`1.37:pkg/kubelet/cm/helpers_linux.go:42-92`, `pod_container_manager_linux.go:102-120`). The container level is then skipped for containers without their own limit (`kuberuntime_container_linux.go:222-225`).
  - DRA memory allocations inflate the limit used in the formula (`:227-238`).
  - With the gate off, kubelet writes `memory.high=max` (`:270-278`). Not reachable on Bottlerocket.
  - Validation changes: "required when gate on" is removed, and "must be nil or 0.9 when gate off" is added (`1.37:validation.go:48-50,375-377`).
  - The gate flips to Beta/on.

### Bottlerocket implementation

- Model: `memory_throttling_factor: KubernetesMemoryThrottlingFactor` (`lib.rs:92`), an `f64` wrapper accepting `is_finite() && > 0.0 && <= 1.0` (`modeled-types/src/kubernetes.rs:1495-1516`). JSON strings are rejected (`lib.rs:345-353`), but `apiclient set ...=0.8` sends a number.
  - Compared with upstream 1.37 (`validation.go:379-381`): the range matches for every JSON-representable value. The only divergence is NaN: upstream lets NaN through because both comparisons are false, while Bottlerocket rejects it. JSON cannot carry NaN, so this does not matter. Infinity is rejected by both.
  - Bottlerocket accepts but kubelet rejects: nothing on 1.37, because the gate-off rule (`:375-377`) cannot trigger without a feature-gate setting. On 1.31-1.36 any accepted value is also valid upstream, but none is rendered.
  - kubelet accepts but Bottlerocket rejects: nothing meaningful.
- Templates: only `kubernetes-1.37/kubelet-config:208-210`, `{{#if settings.kubernetes.memory-throttling-factor}}memoryThrottlingFactor: {{...}}{{/if}}`. Top-level key, unquoted YAML float.
  - Rendering: serde_json/ryu prints the shortest round-trip form: `0.8`, `1.0`, and below 1e-5 scientific form such as `1e-6` (`~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/ryu-1.0.23/src/pretty/mod.rs:74-116`, core-kit `Cargo.lock:5172-5173`). go-yaml v2 resolves `1e-6` as a float (`~/go/pkg/mod/go.yaml.in/yaml/v2@v2.4.4/resolve.go:84,163-166`; same module version as `1.37:go.mod:69`), so every rendered form decodes into `*float64`.
  - `{{#if}}` with a float: truthy iff `f.is_normal()` (handlebars `value.rs:156`). 0 is rejected by the model. Every normal value in (0, 1] renders. Subnormal values (0 < f < 2.2250738585072014e-308) pass the model but are dropped from the YAML. Effect: kubelet sees nil instead of the subnormal. That makes no behavioral difference: with such a factor, `floor((req + f*(lim-req))/page)*page <= req`, so `memory.high` is never written (`1.37:...kuberuntime_container_linux.go:256`). Only configz differs. `{{#if_not_null}}` would be exact.
  - Unset: no key, so 1.37 kubelet has nil and writes no memory.high.
  - Supported upstream but not rendered: 1.31-1.36. This is correct: the field is inert there (gate Alpha/off, and no Bottlerocket path enables gates), so rendering would only change configz.
  - Rendered where gated off: none.
  - Is 1.37-only rendering right? Yes.
- Migration: same v1.66.0 migration as memory-reservation-policy. Present.
- Docs: missing (see memory-reservation-policy).

### How to verify it works on a node

Use the shared pod set above on a 1.37 node A with `apiclient set settings.kubernetes.memory-throttling-factor=0.8`, a control 1.37 node B without it, and optionally a 1.36 node C with it. Read the files with the same commands. Page size 4096. Let A_bytes = node memory capacity minus kube-reserved minus system-reserved (≈ `cat /sys/fs/cgroup/kubepods.slice/memory.max`; allow one page of difference because the kernel rounds memory.max down to a page).

Expected container `memory.high`:

| pod | B (unset) | A f=0.8 | A f=0.5 | A f=1.0 | 1.31-1.36 any value |
|---|---|---|---|---|---|
| mq-burstable (128Mi/256Mi) | max | 241590272 | 201326592 | 268435456 | max |
| mq-guaranteed (256Mi/256Mi) | max | max | max | max | max |
| mq-besteffort | max | floor(0.8*A_bytes/4096)*4096 | floor(0.5*A_bytes/4096)*4096 | floor(A_bytes/4096)*4096 | max |
| mq-nolimit (128Mi/none) | max | floor((134217728+0.8*(A_bytes-134217728))/4096)*4096 | same with 0.5 | floor(A_bytes/4096)*4096 | max |

- Formula as in `1.37:test/e2e_node/memory_qos_test.go:147-152`. For f=0.9 (the old default) mq-burstable would be 255012864.
- With the policy unset, container `memory.min` and `memory.low` are 0 on A and B. Combined with `TieredReservation`, the min/low columns of the previous table apply unchanged (the two settings are independent, `memory_qos_test.go:966-990`).
- Pod-level `memory.high` stays `max` for these pods because they have no pod-level `spec.resources`. Optional: add `spec.resources.limits.memory: 256Mi` plus `requests.memory: 128Mi` at pod level, and the pod cgroup gets `241590272` with f=0.8.
- configz: A `0.8`, B `null` on 1.37. 1.36 and earlier always show `0.9` (upstream default; Bottlerocket does not render it).
- Behavior (optional, about 5 min): `kubectl exec mq-burstable -- sh -c 'dd if=/dev/zero of=/dev/null bs=240M count=5 2>/dev/null; grep -E "^(high|oom_kill) " /sys/fs/cgroup/memory.events'`. The 240M single block is above memory.high (230.4Mi at f=0.8) but below memory.max (256Mi). On A, `high` is greater than 0 and `oom_kill 0`. On B, `high 0`. This is the same method as upstream "should increment memory.events high counter" (`1.37:test/e2e_node/memory_qos_test.go:1048-1110`, which uses `bs=240M` against a 256Mi limit). Do not write to `/dev/shm`: it is a 64Mi tmpfs by default.

Cost: about 15 min per node. Upstream tests: `test/e2e_node/memory_qos_test.go` "memory.high throttling", "memory.high formula verification across request/limit ratios", "should NOT set memory.high when memoryThrottlingFactor is nil (default)" (`1.37:test/e2e_node/memory_qos_test.go:425-600,873-933`). 1.31-1.35 have no MemoryQoS e2e_node test.

### Findings

- [risk] (docs) The 1.37 semantics differ from every earlier kubelet and from older KEP-2570 text. Missing docs should spell this out:
  - Unset means no memory.high at all, not 0.9.
  - Setting any value also throttles every BestEffort container, and every Burstable container without a memory limit, at `req + f*(allocatable - req)`. Example: f=0.5 on a node with 16 GiB allocatable caps every BestEffort container's memory.high near 8 GiB.
  - Citations: `1.37:pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:226,247-257`, `..._test.go:740-746`.
  - A user moving from a 1.36 node, or reading upstream docs for <= 1.36, would not expect BestEffort throttling.
  - Fix: document it with the 1.37+ note.
- [nit] `{{#if}}` drops subnormal factors that the model accepts (`handlebars-4.5.0/src/json/value.rs:156` vs `modeled-types/src/kubernetes.rs:1508`). No behavioral effect (memory.high would never exceed the request). Optional fix: `{{#if_not_null settings.kubernetes.memory-throttling-factor}}` at `kubernetes-1.37/kubelet-config:208`, or tighten the model to a sensible minimum.
- [nit] (docs) The factor is not a floor at the request. If `f*(limit - request)` is below one page, `memory.high` is not set at all (`1.37:...kuberuntime_container_linux.go:256`), so a tiny factor disables throttling instead of throttling at the request.
- No bugs in validation, rendering or version scoping.

## Script feedback

- `python3 -I $T/k8s-field-report.py field singleProcessOOMKill`: the "consumers" list for 1.32-1.37 shows only the `pkg/kubelet/kubelet.go` plumbing. It misses the line that does the work: `pkg/kubelet/kuberuntime/kuberuntime_container_linux.go:283` (1.32) through `:394` (1.37), where `memory.oom.group` is written. For 1.31 it says only `ABSENT`, so the pre-field baseline (unconditional group kill, `1.31:...kuberuntime_container_linux.go:250-256`) is invisible. Suggest following the value one hop into constructor parameters (lowerCamel `singleProcessOOMKill` / `m.<field>`). For absent fields, suggest grepping a distinctive term from the newest doc comment (here `memory.oom.group`). The tool's e2e list also skips 1.31, although `test/e2e_node/oomkiller_linux_test.go` exists there and covers the baseline.
- `python3 -I $T/k8s-field-report.py field memoryThrottlingFactor`:
  - (a) "consumers" for 1.31-1.36 lists only `pkg/kubelet/kubelet.go`. It misses the formula in `pkg/kubelet/kuberuntime/kuberuntime_container_linux.go`. For 1.37 it misses `kuberuntime_container_linux.go:226-257` and `pkg/kubelet/cm/helpers_linux.go:42-92` (pod-level memory.high).
  - (b) In "Changes 1.36 -> 1.37", the context lines `-    	if obj.MemoryReservationPolicy == "" {` / `obj.MemoryReservationPolicy = DefaultMemoryReservationPolicy` are shown as removed, but they still exist in 1.37 (`1.37:pkg/kubelet/apis/config/v1beta1/defaults.go:294-295`). This is a context-window artifact and reads as a real removal.
  - (c) When defaulting disappears, the 1.37 block just omits the "default @" line. An explicit "default: none found in defaults.go" would be clearer.
  - (d) The cited 1.37 validation uses `previousDefaultMemoryThrottlingFactor`, but the report does not resolve it (`1.37:validation.go:50` = 0.9). That constant is the whole meaning of the gate-off rule.
- `python3 -I $T/kubelet-config-lint.py 1.36 --template kits/bottlerocket-core-kit/packages/kubernetes-1.37/kubelet-config`: prints "every rendered path exists upstream" with no warning. Yet that template renders `memoryReservationPolicy` and `memoryThrottlingFactor`, both `+featureGate=MemoryQoS`, and MemoryQoS is Alpha/off in 1.36. `memoryReservationPolicy: TieredReservation` would fail kubelet validation there (`1.36:validation.go:354-357`) and the node would not join. Likewise `memoryThrottlingFactor` on 1.31-1.35 is not flagged even though it is inert. The lint should read the `+featureGate=` marker on every rendered field and print the gate's maturity/default per version (as it already does for `featureGates` entries), flagging fields whose gate is off and not enabled by the template.
- `python3 -I $T/template-drift.py kubernetes --matrix`: correct for its stated scope. The matrix shows `memory-throttling-factor` only in 1.37 but cannot show that the field exists upstream in 1.31-1.36, so an intentional "exists but deliberately unrendered" gap looks the same as an oversight. An optional upstream-presence overlay (for example `-` for absent upstream, `.` for present but unrendered) would make these gaps reviewable.
- `python3 -I $T/k8s-field-report.py gate MemoryQoS`: accurate. It would be more useful with a reverse index of the KubeletConfiguration fields carrying `+featureGate=MemoryQoS` per version (memoryThrottlingFactor in all, memoryReservationPolicy from 1.36).
- Brief/skill text: "`{{#if x}}` skips false, 0 and """ is incomplete for floats. It skips every non-normal number (0 and subnormals), plus null, `[]` and `{}`. `includeZero=true` keeps every non-NaN number (`handlebars-4.5.0/src/json/value.rs:148-164`).
