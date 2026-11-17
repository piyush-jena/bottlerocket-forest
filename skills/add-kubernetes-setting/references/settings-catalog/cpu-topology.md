<!-- Audit of shipped settings, 2026-11-17, against core-kit a4f438b1f, settings-sdk 06d9d1a, bottlerocket b7c6c274,
     and the EKS-D sources packaged in core-kit for Kubernetes 1.31-1.37 (containerd 1.7/2.2/2.3).
     Line numbers drift; re-run scripts/k8s-field-report.py before relying on a citation.
     Status of the findings as of this date: see ../../SKILL.md "Known open findings". -->

# cpu-topology

Scope: `settings.kubernetes.cpu-manager-policy-options`, `settings.kubernetes.topology-manager-policy-options.prefer-closest-numa-nodes`, `settings.kubernetes.topology-manager-policy-options.max-allowable-numa-nodes`.

Conventions: upstream paths are relative to `~/.cache/br-package-src/kubernetes-1.3X-*/src`, prefixed with the version.
Bottlerocket paths are relative to the grove root `/home/fedora/Repositories/bottlerocket-forest/groves/k8s-settings`.
"core-kit" = `kits/bottlerocket-core-kit`, "model" = `bottlerocket-settings-sdk/bottlerocket-settings-models`.

Template renders below were produced with a scratch harness (`a scratch handlebars harness (scripts/render-template.sh now does this with schnauzer itself)`): handlebars 4.5.0 (the version pinned in `core-kit/sources/Cargo.lock:3034-3035`) with `set_strict_mode(true)` exactly as schnauzer does (`core-kit/sources/api/schnauzer/src/v2/registry.rs:15-19`), rendering the real template line ranges.
The relevant blocks only use built-in helpers (`if`, `else`, `each`, `eq`, `or`); schnauzer does not override `or`/`eq` (only `any_enabled`, `if_not_null`, `default` and kube_* helpers are requested in the frontmatter, `core-kit/packages/kubernetes-1.33/kubelet-config:1-3`).

---

## settings.kubernetes.cpu-manager-policy-options

### Upstream per version

Field: `cpuManagerPolicyOptions`, Go type `map[string]string`, flag `--cpu-manager-policy-options`.
Values are parsed with `strconv.ParseBool` for every option, so `"true"` is the only meaningful rendered value.

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes, `1.31:staging/src/k8s.io/kubelet/config/v1beta1/types.go:362` | `cpuManagerPolicyOptions`, `map[string]string` | nil | none in `validation.go`; runtime only, see below | `CPUManagerPolicyOptions` Beta/true (`1.31:pkg/features/kube_features.go:1048`), checked at `1.31:cmd/kubelet/app/server.go:795-801`; `CPUManagerPolicyAlphaOptions` Alpha/false (`:1044`); `CPUManagerPolicyBetaOptions` Beta/true (`:1046`) | known options: Beta `full-pcpus-only`; Alpha `distribute-cpus-across-numa`, `align-by-socket`, `distribute-cpus-across-cores` (`1.31:pkg/kubelet/cm/cpumanager/policy_options.go:39-47`) |
| 1.32 | yes, `1.32:.../types.go:371` | same | nil | runtime | `CPUManagerPolicyOptions` Beta/true (`1.32:pkg/features/versioned_kube_features.go:111-114`), checked `1.32:cmd/kubelet/app/server.go:819-825`; Alpha gate `:103-105` false; Beta gate `:107-109` true | Beta `full-pcpus-only`; Alpha `distribute-cpus-across-numa`, `align-by-socket`, `distribute-cpus-across-cores`, **`strict-cpu-reservation`**, `prefer-align-cpus-by-uncorecache` (`1.32:.../cpumanager/policy_options.go:41-51`) |
| 1.33 | yes, `1.33:.../types.go:410` | same | nil | runtime | `CPUManagerPolicyOptions` GA locked (`1.33:pkg/features/kube_features.go:1073-1077`), struct-level check removed (`1.33:cmd/kubelet/app/server.go:872` passes the map straight through); Alpha gate false `:1065-1067`; Beta gate true `:1069-1071` | Stable `full-pcpus-only`; Beta `strict-cpu-reservation`, `distribute-cpus-across-numa`; Alpha `align-by-socket`, `distribute-cpus-across-cores`, `prefer-align-cpus-by-uncorecache` (`1.33:.../policy_options.go:41-52`) |
| 1.34 | yes, `1.34:.../types.go:411` | same | nil | runtime | GA locked (`1.34:pkg/features/kube_features.go:1149-1153`); Alpha false `:1141`; Beta true `:1145` | Stable `full-pcpus-only`; Beta `strict-cpu-reservation`, `distribute-cpus-across-numa`, `prefer-align-cpus-by-uncorecache`; Alpha `align-by-socket`, `distribute-cpus-across-cores` (`1.34:.../policy_options.go:41-52`) |
| 1.35 | yes, `1.35:.../types.go:411` | same | nil | runtime | GA locked (`1.35:pkg/features/kube_features.go:1168-1172`); Alpha false `:1160`; Beta true `:1164` | Stable `full-pcpus-only`, `strict-cpu-reservation`; Beta `distribute-cpus-across-numa`, `prefer-align-cpus-by-uncorecache`; Alpha `align-by-socket`, `distribute-cpus-across-cores` (`1.35:.../policy_options.go:41-52`) |
| 1.36 | yes, `1.36:.../types.go:435` | same | nil | runtime | GA locked (`1.36:pkg/features/kube_features.go:1291-1295`); Alpha false `:1283`; Beta true `:1287` | Stable `full-pcpus-only`, `strict-cpu-reservation`, `prefer-align-cpus-by-uncorecache`; Beta `distribute-cpus-across-numa`; Alpha `align-by-socket`, `distribute-cpus-across-cores` (`1.36:.../policy_options.go:41-52`) |
| 1.37 | yes, `1.37:.../types.go:435` | same | nil | runtime | GA locked (`1.37:pkg/features/kube_features.go:1388-1392`); Alpha false `:1380`; Beta true `:1384` | same sets as 1.36 (`1.37:.../policy_options.go:41-52`) |

Per-option maturity matrix (A = Alpha, needs `CPUManagerPolicyAlphaOptions` which is off by default in every version; B = Beta, needs `CPUManagerPolicyBetaOptions` which is on by default in every version; GA = no gate check; `-` = unknown option, kubelet errors `unknown CPU Manager Policy option`):

| option | 1.31 | 1.32 | 1.33 | 1.34 | 1.35 | 1.36 | 1.37 | modeled by Bottlerocket |
|---|---|---|---|---|---|---|---|---|
| full-pcpus-only | B | B | GA | GA | GA | GA | GA | yes |
| distribute-cpus-across-numa | A | A | B | B | B | B | B | yes |
| strict-cpu-reservation | - | A | B | B | GA | GA | GA | yes |
| prefer-align-cpus-by-uncorecache | - | A | A | B | B | GA | GA | yes |
| align-by-socket | A | A | A | A | A | A | A | no |
| distribute-cpus-across-cores | A | A | A | A | A | A | A | no |

Runtime validation path (all fatal, the node never becomes Ready):
- Gate/unknown check: `CheckPolicyOptionAvailable` at `1.31:.../cpumanager/policy_options.go:52-66`, `1.32:...:56-70`, `1.33-1.37:...:57-72`.
  Error text for an Alpha option: `CPU Manager Policy Alpha-level Options not enabled, but option "<name>" provided`.
- Pairwise conflicts in `NewStaticPolicyOptions`:
  - `full-pcpus-only` + `distribute-cpus-across-cores`, `distribute-cpus-across-numa` + `distribute-cpus-across-cores`: all versions (`1.31:...:132-139`).
  - `prefer-align-cpus-by-uncorecache` + `distribute-cpus-across-cores`, `prefer-align-cpus-by-uncorecache` + `distribute-cpus-across-numa`: 1.32+ (`1.32:...:161-167`, `1.33-1.37:...:163-169`).
- Hardware checks: `align-by-socket` only (`1.37:...:175-187`).
- Policy must be `static`. `NewNonePolicy` rejects any non-empty map: `None policy: received unsupported options=...` (`1.31-1.34:pkg/kubelet/cm/cpumanager/policy_none.go:37-40`, `1.35-1.36:...:38-41`, `1.37:...:39-42`).
  It is reached from `cpu_manager.go` `case PolicyNone` (`1.31:161`, `1.32-1.34:171`, `1.35:174`, `1.36:184`, `1.37:188`).
- Error propagation: `cpumanager.NewManager` failure returns from `NewContainerManager` (`1.31:pkg/kubelet/cm/container_manager_linux.go:317-330`, `1.32:322-335`, `1.37:329-343`), which `cmd/kubelet/app/server.go` returns as a run error.
- `strict-cpu-reservation` also changes state validation at Start.
  With the option on, an existing `cpu_manager_state` whose `defaultCpuSet` contains reserved CPUs is rejected (`1.37:pkg/kubelet/cm/cpumanager/policy_static.go:228-238`; line 232 in 1.37, 226 in 1.32, 227 in 1.33, 228 in 1.34, 230 in 1.35, 233 in 1.36).
  With the option off, a state file that lacks the reserved CPUs is rejected.
  Start failure is fatal: `1.37:pkg/kubelet/cm/container_manager_linux.go:654-657` leads to `1.37:pkg/kubelet/kubelet.go:1850-1851` (`os.Exit(1)`).
- Static policy also requires kube+system reserved CPU > 0 (`1.37:pkg/kubelet/cm/cpumanager/cpu_manager.go:208`).
  Bottlerocket always renders a non-zero `kubeReserved.cpu` via `kube_reserve_cpu` (`core-kit/packages/kubernetes-1.37/kubelet-config:87-88`), so this is satisfied.

### What changes between versions
- 1.31 to 1.32: `strict-cpu-reservation` and `prefer-align-cpus-by-uncorecache` become known, both Alpha (`1.32:.../cpumanager/policy_options.go:36-37,45-46`). The prefer-align conflicts are added (`1.32:...:161-167`).
- 1.32 to 1.33: `full-pcpus-only` goes Stable; `strict-cpu-reservation` and `distribute-cpus-across-numa` go Beta (`1.33:...:46-52`). The `CPUManagerPolicyOptions` gate goes GA locked and its check in server.go is removed (`1.33:pkg/features/kube_features.go:1073-1077`, `1.33:cmd/kubelet/app/server.go:872`).
- 1.33 to 1.34: `prefer-align-cpus-by-uncorecache` goes Beta (`1.34:...:45-49`).
- 1.34 to 1.35: `strict-cpu-reservation` goes Stable (`1.35:...:49-52`).
- 1.35 to 1.36: `prefer-align-cpus-by-uncorecache` goes Stable (`1.36:...:48-52`).
- 1.36 to 1.37: none.
- `CPUManagerPolicyAlphaOptions` (Alpha/false) and `CPUManagerPolicyBetaOptions` (Beta/true) do not change in 1.31-1.37.

### Bottlerocket implementation
- **Model**: `cpu_manager_policy_options: Vec<KubernetesCPUManagerPolicyOption>` (`model/settings-extensions/kubernetes/src/lib.rs:73`).
  The enum allows exactly `full-pcpus-only`, `distribute-cpus-across-numa`, `prefer-align-cpus-by-uncorecache`, `strict-cpu-reservation` (`model/modeled-types/src/kubernetes.rs:1356-1367`).
  There is no dedupe and no cross-field check against `cpu-manager-policy`.
  - **Accepted by Bottlerocket, rejected by kubelet (node fails to start)**:
    - **1.32**: `strict-cpu-reservation`. It is Alpha in 1.32, the template renders it, and the alpha gate cannot be enabled through settings. See Findings.
    - **All versions**: any rendered option while `cpu-manager-policy` is unset or `none`, giving `None policy: received unsupported options`. A list whose values are all filtered out by the version's template renders an empty map and does not fail.
    - **1.34-1.37**: `["distribute-cpus-across-numa", "prefer-align-cpus-by-uncorecache"]` together (`1.34:...:167-169`). In 1.32/1.33 the combination is filtered out before kubelet sees it.
    - **1.33-1.37**: toggling `strict-cpu-reservation` at runtime on a node already running the static policy. See Findings.
  - **Accepted by kubelet, rejected by Bottlerocket**: `align-by-socket` and `distribute-cpus-across-cores` (Alpha in every version, so not usable anyway); explicit `"false"` values (equivalent to absent).
- **Templates** (`core-kit/packages/kubernetes-1.3X/kubelet-config`). All versions use `{{#if settings.kubernetes.cpu-manager-policy-options}}` and render `cpuManagerPolicyOptions:` then `{{#each}}` with `    {{this}}: "true"` (quoted string, which matches `map[string]string`). Unset or `[]` renders nothing (verified).

  | version | lines | per-value filter | values that actually render (verified by strict render of the real lines with all 4 values) |
  |---|---|---|---|
  | 1.31 | 114-121 | `(eq this "full-pcpus-only")` line 117 | full-pcpus-only |
  | 1.32 | 114-121 | `(or (eq .. "full-pcpus-only") (eq .. "strict-cpu-reservation"))` line 117 | full-pcpus-only, **strict-cpu-reservation (Alpha in 1.32)** |
  | 1.33 | 117-124 | `(or (eq .. "full-pcpus-only") (eq .. "strict-cpu-reservation") (eq .. "distribute-cpus-across-numa"))` line 120 | full-pcpus-only, strict-cpu-reservation. **`distribute-cpus-across-numa` is never rendered**: handlebars `or` is binary (`handlebars-4.5.0/src/helpers/helper_extras.rs:13`), the macro reads only params 0 and 1 and silently ignores the third (`handlebars-4.5.0/src/macros.rs:59-83`) |
  | 1.34 | 117-122 | none | all four |
  | 1.35 | 117-122 | none | all four |
  | 1.36 | 117-122 | none | all four |
  | 1.37 | 117-122 | none | all four |

  - When every listed value is filtered (for example 1.31 with `["strict-cpu-reservation"]`), the output is a bare `cpuManagerPolicyOptions:` key, which is YAML null, a nil map, so kubelet starts with no options.
  - Duplicate list entries produce duplicate YAML keys. That trips the strict YAML check (`1.37:staging/src/k8s.io/apimachinery/pkg/runtime/serializer/json/json.go:277-285`), and kubelet falls back to lenient decoding with a warning (`1.37:pkg/kubelet/kubeletconfig/util/codec/codec.go:76-103`). Inferred, not run.
  - Upstream supports it but it is not rendered:
    - `distribute-cpus-across-numa` on 1.33 (Beta, default-on). This is unintended.
    - `strict-cpu-reservation`, `prefer-align-cpus-by-uncorecache` and `distribute-cpus-across-numa` are correctly not rendered where they are Alpha or unknown.
  - Rendered where it is gated off: `strict-cpu-reservation` on 1.32.
  - No `featureGates` are rendered for this in any version. 1.31/1.32 have no `featureGates` block at all. 1.33+ only set `DynamicResourceAllocation` and `MutableCSINodeAllocatableCount` (`core-kit/packages/kubernetes-1.37/kubelet-config:236-238`). There is no feature-gate setting in the model.
- **Migration**: `bottlerocket/sources/settings-migrations/v1.51.0/kubernetes-beta-cpu-manager-policy-options/src/main.rs:12-16` is a `RestrictListsMigration` that keeps only `full-pcpus-only` on downgrade. It is registered at `bottlerocket/Release.toml:452`.
  The logic is correct: pre-1.51 models only know `full-pcpus-only`.
  The comment at lines 5-8 ("strict-cpu-reservation: 1.32 or higher") is wrong per source: it is Alpha in 1.32.
  The original 2023 setting predates this, and the `archived/v1.14.0/kubelet-config-settings` migration covers the key.
- **Docs**:
  - `website/repo/data/settings/1.51.x/kubernetes.toml:28-51` lists all four values with no per-Kubernetes-version availability, and gives the example `["full-pcpus-only", "distribute-cpus-across-numa"]`. On 1.31-1.33 the second value is silently dropped.
  - `1.14.x/kubernetes.toml:212-228` is the original single-value entry.
  - The docs say "when `cpu-manager-policy` is set to `static`" but not that kubelet fails otherwise.

### How to verify it works on a node
Set options through user-data at launch, not with `apiclient set` on a running static-policy node.
`/var/lib/kubelet/cpu_manager_state` is only removed at boot (`core-kit/packages/kubernetes-1.37/kubernetes-tmpfiles.conf:4`, `r!`), and `apiclient set` only does `systemctl try-restart kubelet.service` (`bottlerocket/sources/shared-defaults/kubernetes-services.toml:15-16`).
So toggling `strict-cpu-reservation` live fails kubelet Start until a reboot (Findings).

Test user-data (TOML):
```toml
[settings.kubernetes]
cpu-manager-policy = "static"
cpu-manager-policy-options = ["full-pcpus-only", "strict-cpu-reservation", "distribute-cpus-across-numa"]
```
Checks:
```sh
# admin container
apiclient get settings.kubernetes.cpu-manager-policy settings.kubernetes.cpu-manager-policy-options
sudo sheltie
grep -A5 '^cpuManagerPolicyOptions' /etc/kubernetes/kubelet/config
journalctl -u kubelet --no-pager | grep -E 'created with configuration|Failed to initialize cpu manager|Alpha-level Options|unsupported options|can not be used at the same time|invalid state'
cat /var/lib/kubelet/cpu_manager_state
# workstation
kubectl get --raw /api/v1/nodes/$NODE/proxy/configz | jq '.kubeletconfig | {cpuManagerPolicy, cpuManagerPolicyOptions, reservedSystemCPUs}'
```
- Proof of acceptance (cheap, any instance type):
  - Invalid or gated options are fatal at container-manager init. So a Ready node whose `configz` shows the option, plus the static-policy log line, proves kubelet accepted and applied it.
  - Log line: `Static policy created with configuration options=...` (`1.31:pkg/kubelet/cm/cpumanager/policy_static.go:139`, `1.32:143`, `1.33:144`, `1.34:145`). In 1.35+ the message is `created with configuration` (`1.35:147`, `1.36:150`, `1.37:149`).
  - The options struct prints booleans `FullPhysicalCPUsOnly`, `DistributeCPUsAcrossNUMA`, `StrictCPUReservation`, `PreferAlignByUncoreCacheOption`. The exact text format depends on klog output, inferred.
- Expected result per version for the user-data above:
  - 1.31: config/configz only `full-pcpus-only: "true"`; Ready.
  - 1.32: config has `full-pcpus-only` and `strict-cpu-reservation`. kubelet exits with `CPU Manager Policy Alpha-level Options not enabled, but option "strict-cpu-reservation" provided` and the node never joins. Inferred from source; render verified.
  - 1.33: only `full-pcpus-only` and `strict-cpu-reservation` (distribute dropped, the bug); log shows `DistributeCPUsAcrossNUMA:false`; Ready.
  - 1.34-1.37: all three; Ready.
- Behavioral checks:
  - `strict-cpu-reservation` (cheap, any instance, about 10 min): `cat /var/lib/kubelet/cpu_manager_state`.
    - On a 4-vCPU node the default kube-reserved rounds up to 1 reserved CPU (`1.37:.../cpu_manager.go:214`), normally CPU 0.
    - Expect `"defaultCpuSet":"1-3"` with the option and `"0-3"` without it (A/B).
    - A BestEffort pod's `cat /sys/fs/cgroup/cpuset.cpus.effective` should exclude the reserved CPU. Expected result inferred, not run.
  - `full-pcpus-only` (cheap, any x86 instance with SMT, for example m5.xlarge; Graviton has no SMT, so the check passes trivially):
    - A Guaranteed pod with `cpu: "1"` (requests = limits, memory too) fails with status reason `SMTAlignmentError` (`1.37:pkg/kubelet/cm/cpumanager/policy_static.go:48-49`).
    - With `cpu: "2"` it runs on a sibling pair (`/sys/devices/system/cpu/cpuN/topology/thread_siblings_list`).
    - A/B: without the option the `cpu: "1"` pod runs.
  - `distribute-cpus-across-numa` (expensive): needs at least 2 NUMA nodes (for example m5.24xlarge, c5.24xlarge, m6i.32xlarge; inferred from 2-socket EC2 sizes, check `ls -d /sys/devices/system/node/node*`).
    - Use a Guaranteed pod whose CPU request exceeds the free CPUs of one NUMA node, for example 50 on a 96-vCPU host.
    - Expect an even split across nodes with the option, packed without it. Compare `Cpus_allowed_list` from `/proc/1/status` inside the container with `/sys/devices/system/node/node*/cpulist`.
    - About 30 min plus large-instance cost.
  - `prefer-align-cpus-by-uncorecache` (moderate): needs more than one L3 domain (`cat /sys/devices/system/cpu/cpu*/cache/index3/shared_cpu_list | sort -u | wc -l` > 1). That is typical of AMD EPYC families such as m6a/c6a/m7a/c7a (inferred).
    - A Guaranteed pod requesting at most one L3 domain's CPUs should land within a single `shared_cpu_list`.
- Rough time: about 10-15 min per version for the cheap checks (launch, join, read configz/log/state).
- Upstream e2e coverage:
  - `1.37:test/e2e_node/cpu_manager_test.go:817` (strict CPU reservation), `:927-982` (SMT alignment / full-pcpus-only), `:1071`, `:1147` (uncore cache), `:1204`, `:1426` (combinations), `:1515-1557` (distribute-cpus-across-numa).
  - 1.31 e2e only covers `FullPCPUsOnlyOption`.

### Findings
- **[bug] 1.32 renders `strict-cpu-reservation`, which is Alpha in 1.32, so kubelet fails to start.**
  - Input: aws-k8s-1.32 variant, `cpu-manager-policy = "static"`, `cpu-manager-policy-options = ["strict-cpu-reservation"]`.
  - The template filter `core-kit/packages/kubernetes-1.32/kubelet-config:117` renders `strict-cpu-reservation: "true"` (verified by render).
  - Upstream: Alpha in `1.32:pkg/kubelet/cm/cpumanager/policy_options.go:45`. `CPUManagerPolicyAlphaOptions` is false (`1.32:pkg/features/versioned_kube_features.go:103-105`). The check is at `1.32:...:61-63`, it is fatal via `1.32:pkg/kubelet/cm/container_manager_linux.go:332-334`, and Bottlerocket has no way to enable the alpha gate.
  - Origin: core-kit 6ad630461 and PR #689 claim "strict-cpu-reservation - 1.32 or higher". settings-sdk #104 testing covered only 1.29 and 1.34.
  - Fix: in 1.32 render only `full-pcpus-only` (same filter as 1.31), correct the v1.51.0 migration comment, and add per-version availability to the docs.
- **[bug] 1.33 silently drops `distribute-cpus-across-numa` (three-argument `or`).**
  - Input: aws-k8s-1.33, static policy, `["distribute-cpus-across-numa"]`. The rendered output is `cpuManagerPolicyOptions:` (null), verified with strict handlebars 4.5.0 render of `core-kit/packages/kubernetes-1.33/kubelet-config:117-124`.
  - Effect: the option is Beta and default-on upstream (`1.33:.../policy_options.go:48`), but kubelet runs without it and there is no error.
  - Fix: `{{#if (or (eq this "full-pcpus-only") (or (eq this "strict-cpu-reservation") (eq this "distribute-cpus-across-numa")))}}`, or more simply `{{#unless (eq this "prefer-align-cpus-by-uncorecache")}}`.
- **[risk] Model accepts combinations kubelet rejects.**
  - Any options with `cpu-manager-policy` unset or `none` (all versions, fatal `None policy: received unsupported options`).
  - `distribute-cpus-across-numa` + `prefer-align-cpus-by-uncorecache` on 1.34-1.37 (fatal, `1.34:.../policy_options.go:167-169`). settings-sdk #104 noted this conflict but did not encode it.
  - Fix: a cross-field check in the kubernetes settings extension, or at minimum a docs note.
- **[risk] Toggling `strict-cpu-reservation` at runtime breaks kubelet until reboot (1.33-1.37).**
  - `apiclient set` re-renders and does `systemctl try-restart kubelet.service` (`bottlerocket/sources/shared-defaults/kubernetes-services.toml:15-16`).
  - The stale `cpu_manager_state` then fails `validateState` (`1.37:pkg/kubelet/cm/cpumanager/policy_static.go:228-238`), which is fatal at Start (`1.37:pkg/kubelet/kubelet.go:1850-1851`). The state file is only removed at boot (`kubernetes-tmpfiles.conf:4`).
  - Inferred end to end. Fix: document "reboot after changing", or remove the state file on CPU-manager setting changes.
- **[risk] Silent drops on 1.31-1.33 with no docs.**
  - Options valid in the model are silently filtered per version (1.31: only `full-pcpus-only`; 1.32/1.33: see table).
  - That is safe, but the docs (`1.51.x/kubernetes.toml:42-51`) present all four as accepted everywhere, with an example that is a no-op on 1.31-1.33.
- **[nit] Duplicate list entries produce duplicate YAML keys and a lenient-decode warning (inferred).** Fix: dedupe in the model, or tolerate it.
- **[nit, adjacent, owner of `cpu-manager-policy`] `cpu-manager-policy = "Static"` or `"None"` passes the model but kubelet rejects it.**
  - The model accepts the aliases (`model/modeled-types/src/kubernetes.rs:813-818`) and stores the input verbatim (`:827-829`). The template renders `cpuManagerPolicy: Static`.
  - kubelet then fails with `unknown policy: "Static"` (`1.37:pkg/kubelet/cm/cpumanager/cpu_manager.go:221`; constant `"static"` at `1.37:.../policy_static.go:47`).
  - Fix: normalize to lowercase in `TryFrom`.

---

## settings.kubernetes.topology-manager-policy-options.prefer-closest-numa-nodes

### Upstream per version
Field: `topologyManagerPolicyOptions` (`map[string]string`, flag `--topology-manager-policy-options`), key `prefer-closest-numa-nodes`, value parsed with `strconv.ParseBool`.
- Field definition: `1.31:staging/src/k8s.io/kubelet/config/v1beta1/types.go:401`, `1.32:410`, `1.33:448`, `1.34:449`, `1.35:449`, `1.36:473`, `1.37:473`.
- Struct gate `TopologyManagerPolicyOptions` is checked in server.go: `1.31:cmd/kubelet/app/server.go:803-809`, `1.32:827-833`, `1.33:829-835`, `1.34:828-834`, `1.35:822-828`, `1.36:855-861`, `1.37:905-911`.
- Per-key Beta check uses `TopologyManagerPolicyBetaOptions`: `1.31:pkg/kubelet/cm/topologymanager/policy_options.go:52`, `1.32-1.34:53`, `1.35-1.37:52`.

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes, Beta (`1.31:.../topologymanager/policy_options.go:36-39`) | `topologyManagerPolicyOptions["prefer-closest-numa-nodes"]`, string bool | false | ParseBool (`1.31:...:77-82`) | struct gate Beta/true (`1.31:pkg/features/kube_features.go:1218`); `TopologyManagerPolicyBetaOptions` Beta/true (`:1216`) | usable with default gates |
| 1.32 | yes, Stable (`1.32:...:39-41`) | same | false | ParseBool | struct gate GA/true, not locked (`1.32:pkg/features/versioned_kube_features.go:782-786`); BetaOptions Beta/true (`:777-780`) | |
| 1.33 | yes, Stable (`1.33:...:39-41`) | same | false | ParseBool | struct gate GA, not locked (`1.33:pkg/features/kube_features.go:1819-1823`) | |
| 1.34 | yes, Stable (`1.34:...:39-41`) | same | false | ParseBool | GA, not locked (`1.34:...kube_features.go:1822-1826`) | |
| 1.35 | yes, Stable (`1.35:...:37-40`) | same | false | ParseBool | GA, not locked (`1.35:...kube_features.go:1879-1883`) | |
| 1.36 | yes, Stable (`1.36:...:37-40`) | same | false | ParseBool | GA locked (`1.36:...kube_features.go:2078-2082`) | |
| 1.37 | yes, Stable (`1.37:...:37-40`) | same | false | ParseBool | GA locked (`1.37:...kube_features.go:2244-2248`) | |

The options are only parsed when `topologyManagerPolicy` is not `none`.
`NewManager` returns early for `none` without calling `NewPolicyOptions` (`1.31-1.34:pkg/kubelet/cm/topologymanager/topology_manager.go:137-140`, `1.35:142-145`, `1.36:171-174`, `1.37:182-185`).
So with the default policy, any options are ignored silently, including invalid ones.
With a non-none policy, a parse or gate error is fatal (`1.31:pkg/kubelet/cm/container_manager_linux.go:289-298`; `1.37:298-307`).

### What changes between versions
- 1.31 to 1.32: `prefer-closest-numa-nodes` goes Beta to Stable (`1.32:.../topologymanager/policy_options.go:39-41`). The struct gate goes Beta to GA (`1.32:pkg/features/versioned_kube_features.go:785`).
- 1.35 to 1.36: the struct gate becomes `LockToDefault` (`1.36:pkg/features/kube_features.go:2081`). No behavioral change, since Bottlerocket never sets it.
- Otherwise none. `TopologyManagerPolicyBetaOptions` is Beta/true and `TopologyManagerPolicyAlphaOptions` is Alpha/false throughout 1.31-1.37.

### Bottlerocket implementation
- **Model**: `topology_manager_policy_options: KubernetesTopologyManagerPolicyOptions` (`model/settings-extensions/kubernetes/src/lib.rs:76`) with field `prefer_closest_numa_nodes: bool` (`model/modeled-types/src/kubernetes.rs:1696-1701`, `#[model(impl_default = true)]`, so `Option<bool>`).
  Equivalent to upstream ParseBool for the values Bottlerocket can produce.
  Nothing is accepted by Bottlerocket and rejected by kubelet.
  No cross-check that `topology-manager-policy` is not `none`.
- **Templates**:
  - 1.31: not rendered. Topology section `core-kit/packages/kubernetes-1.31/kubelet-config:122-127` has scope and policy only.
  - 1.32: `:128-131`; 1.33: `:131-134`; 1.34: `:129-132`. Pattern: `{{#if ...prefer-closest-numa-nodes}}topologyManagerPolicyOptions:\n  prefer-closest-numa-nodes: "{{...}}"{{/if}}`.
  - 1.35: `:129-140`, nested with max-allowable (see next section).
  - 1.36 and 1.37: **not rendered**. The topology section ends at `topologyManagerPolicy` (`:126-128`) and goes straight to `podPidsLimit` (`:129`).
  - Unset or false renders nothing. True renders `"true"` (quoted string, correct for `map[string]string`).
  - Upstream supports it but it is not rendered: 1.31 (Beta, default-on), 1.36, 1.37 (Stable).
  - Rendered where unsupported: none.
- **Root cause for 1.36/1.37** (verified with git, read-only):
  - core-kit PR #901 (commit 628d29bfb) touched only 1.32-1.35 and merged 2026-04-16 (`gh pr view 901`).
  - The next day `kubernetes-1.36` was added in e641ab8ed. Its `kubelet-config` is byte-identical to `628d29bfb^:packages/kubernetes-1.35/kubelet-config`, the pre-#901 1.35 template.
  - `kubernetes-1.37` (01487c213) was copied from 1.36 and inherited the gap.
- **Migration**: `bottlerocket/sources/settings-migrations/v1.60.0/kubernetes-topology-manager-policy-options/src/main.rs:7-11` (`AddSettingsMigration` for the parent and both keys), `bottlerocket/Release.toml:468`. Correct.
- **Docs**: `website/repo/data/settings/1.60.x/kubernetes.toml:1-16` says "available Kubernetes 1.32 onwards". That is false for 1.36/1.37 today.
  The docs do not say that `topology-manager-policy` must be non-`none` for the option to do anything.

### How to verify it works on a node
Combined test for both topology keys (cheap, any instance type, even single-NUMA):
```toml
[settings.kubernetes]
topology-manager-policy = "best-effort"     # required, options are ignored under "none"
[settings.kubernetes.topology-manager-policy-options]
prefer-closest-numa-nodes = true
max-allowable-numa-nodes = 16
```
```sh
sudo sheltie
grep -A3 '^topologyManagerPolicyOptions' /etc/kubernetes/kubelet/config
journalctl -u kubelet --no-pager | grep -E 'Creating topology manager|max-allowable-numa-nodes|NUMA Nodes'
kubectl get --raw /api/v1/nodes/$NODE/proxy/configz | jq '.kubeletconfig | {topologyManagerPolicy, topologyManagerScope, topologyManagerPolicyOptions}'
```
- **Proof of acceptance**: the log line `Creating topology manager with policy per scope ... topologyPolicyOptions=<PreferClosestNUMA:.. MaxAllowableNUMANodes:..>` (`1.31-1.34:pkg/kubelet/cm/topologymanager/topology_manager.go:147`, `1.35:152`, `1.36:181`, `1.37:192`).
  It is logged only after the options parsed successfully, and only for non-none policies.
  For `max-allowable-numa-nodes` > 8 there is also `WARNING: the value of max-allowable-numa-nodes is more than the default recommended value` (`policy_options.go:94` in 1.31/1.35-1.37, `:95` in 1.32-1.34).
- **Expected per version today** for the user-data above:
  - 1.31: configz has no `topologyManagerPolicyOptions`; log `PreferClosestNUMA:false MaxAllowableNUMANodes:8`.
  - 1.32-1.34: configz `{"prefer-closest-numa-nodes":"true"}`; log `PreferClosestNUMA:true MaxAllowableNUMANodes:8`; no warning.
  - 1.35: configz has both keys; log `PreferClosestNUMA:true MaxAllowableNUMANodes:16` plus the warning.
  - 1.36, 1.37: same as 1.31 (nothing rendered).
  - A/B: the same node with `topology-manager-policy` unset logs only `Creating topology manager with none policy`, even though configz still shows the options.
- **Behavioral check** (expensive):
  - `prefer-closest-numa-nodes` only matters when an allocation must span NUMA nodes on a host with at least 3-4 NUMA nodes and non-uniform distances (`cat /sys/devices/system/node/node*/distance`).
  - Upstream e2e skips below 4 NUMA nodes (`1.37:test/e2e_node/topology_manager_test.go:59`, `:1377-1395`).
  - On such a host (for example 4-socket x1.32xlarge or x1e.32xlarge or u-* high-memory, inferred; check `node*` count), run a Guaranteed pod sized to need 2 NUMA nodes. Expect the chosen pair to be the minimum-distance pair.
  - The core-kit #901 test (a 4-CPU pod on a 2-NUMA host landing on node0) does not exercise this option: best-effort picks a single-node fit regardless.
- Rough time: about 10 min per version for the cheap check.
- Upstream e2e: `1.37:test/e2e_node/topology_manager_test.go:1377-1395` and `:1440-1441`; also present in 1.32+ (`1.32:...:1150`).

### Findings
- **[bug] 1.36 and 1.37 never render `topologyManagerPolicyOptions`.**
  - Input: aws-k8s-1.36 or aws-k8s-1.37, `topology-manager-policy = "best-effort"`, `topology-manager-policy-options.prefer-closest-numa-nodes = true`.
  - What users see: the API accepts the setting and `apiclient get` returns it. `/etc/kubernetes/kubelet/config` has no `topologyManagerPolicyOptions`, kubelet runs with `PreferClosestNUMA:false`, and nothing is logged or rejected. Users moving from a 1.35 AMI silently lose the setting.
  - Fix: insert the 1.35 block (`core-kit/packages/kubernetes-1.35/kubelet-config:129-140`) verbatim after line 128 in both `kubernetes-1.36/kubelet-config` and `kubernetes-1.37/kubelet-config`. Both keys are Stable there (`1.36:pkg/kubelet/cm/topologymanager/policy_options.go:37-40`, same in 1.37).
  - Do not "simplify" it to `{{#if (or a b)}}`: `or` with a missing setting is a render error in strict mode (verified: "`or` helper: Couldn't read parameter y"). The nested if/else is the right shape.
- **[risk] Topology options are no-ops under the default `topology-manager-policy` (`none`).** This is upstream behavior (`topology_manager.go:137-140` etc.), but neither the model nor the docs tell users. Fix: a docs note, or warn or validate in the settings extension.
- **[nit] 1.31 does not render it although it is Beta with a default-on gate** (`1.31:.../policy_options.go:36-39`, `1.31:pkg/features/kube_features.go:1216`). That is consistent with the stated "GA only" choice (commit 628d29bfb message) and the docs, so the effect is a silent no-op on 1.31.
  It is inconsistent with cpu-manager-policy-options, where Beta options are rendered. Optional fix: render it in 1.31.

---

## settings.kubernetes.topology-manager-policy-options.max-allowable-numa-nodes

### Upstream per version
Key `max-allowable-numa-nodes` in `topologyManagerPolicyOptions`, parsed with `strconv.Atoi`.
Values below 8 are rejected (`the minimum value of "max-allowable-numa-nodes" should not be less than 8`) and values above 8 log a warning.
- Atoi/min/warn lines: 1.31 and 1.35-1.37 `policy_options.go:84/89/94`; 1.32-1.34 `:85/90/95`.
- Default constant `defaultMaxAllowableNUMANodes = 8`: `1.31-1.34:pkg/kubelet/cm/topologymanager/topology_manager.go:40`, `1.35-1.37:41`.
- Enforcement, only for non-none policies: `unsupported on machines with more than %v NUMA Nodes` at `1.31-1.34:topology_manager.go:154-155`, `1.35:159-160`, `1.36:188-189`, `1.37:199-200`.

| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes, Beta (`1.31:.../topologymanager/policy_options.go:36-39`) | `topologyManagerPolicyOptions["max-allowable-numa-nodes"]`, string int | 8 | Atoi, >= 8 (`:83-96`) | `TopologyManagerPolicyBetaOptions` Beta/true (`1.31:pkg/features/kube_features.go:1216`); struct gate Beta/true (`:1218`) | usable with default gates |
| 1.32 | yes, Beta (`1.32:...:36-38`) | same | 8 | Atoi, >= 8 (`:84-97`) | BetaOptions Beta/true (`1.32:pkg/features/versioned_kube_features.go:777-780`); struct GA | usable with default gates |
| 1.33 | yes, Beta (`1.33:...:36-38`) | same | 8 | same | BetaOptions Beta/true (`1.33:pkg/features/kube_features.go:1814-1817`) | usable |
| 1.34 | yes, Beta (`1.34:...:36-38`) | same | 8 | same | BetaOptions Beta/true (`1.34:...kube_features.go:1817-1820`) | usable |
| 1.35 | yes, Stable (`1.35:...:37-40`) | same | 8 | Atoi, >= 8 (`:83-96`) | no per-key gate; struct GA | |
| 1.36 | yes, Stable (`1.36:...:37-40`) | same | 8 | same | struct GA locked | |
| 1.37 | yes, Stable (`1.37:...:37-40`) | same | 8 | same | struct GA locked | |

### What changes between versions
- 1.34 to 1.35: Beta to Stable (`1.35:.../topologymanager/policy_options.go:37-40`). No change in accepted values or default.
- 1.35 to 1.36: the struct gate gets locked (no effect).
- Otherwise none.

### Bottlerocket implementation
- **Model**: `max_allowable_numa_nodes: MaxAllowableNumaNodesValue` (`model/modeled-types/src/kubernetes.rs:1700`). It is a u32 with `#[serde(try_from = "u32", into = "u32")]` and `ensure!(input >= 8)` (`:1650-1665`; error `model/modeled-types/src/lib.rs:198`).
  Equivalent to upstream: lower bound 8 matches, and every u32 fits Go `int` on 64-bit.
  Nothing is accepted by Bottlerocket and rejected by kubelet.
  The only kubelet values Bottlerocket rejects are numeric strings, which is fine.
- **Templates**:
  - Rendered only in 1.35: `core-kit/packages/kubernetes-1.35/kubelet-config:132-134` (inside the prefer-closest branch) and `:135-139` (the `{{else}}` branch, which opens its own `topologyManagerPolicyOptions:`).
  - Quoted output `"16"` (string, correct for `map[string]string`; an unquoted int would fail decoding into `map[string]string`).
  - Every combination of the nested `#if`/`else` in 1.35, rendered with the real lines 129-140 in strict mode:

    | prefer-closest | max-allowable | output |
    |---|---|---|
    | unset (or parent object absent) | unset | nothing |
    | true | unset | `topologyManagerPolicyOptions:` / `prefer-closest-numa-nodes: "true"` |
    | false | unset | nothing (the else branch has no max; equivalent to kubelet default false) |
    | unset | 16 | `topologyManagerPolicyOptions:` / `max-allowable-numa-nodes: "16"` |
    | true | 16 | both keys under one `topologyManagerPolicyOptions:` |
    | false | 8 | `max-allowable-numa-nodes: "8"` only |

    No duplicate `topologyManagerPolicyOptions:` key is possible and no strict-mode error occurs. 0-7 cannot reach the template (the model rejects them), and every valid value is truthy. The logic is correct.
  - Not rendered in 1.31-1.34 or 1.36-1.37.
- **Is the 1.35-only rendering correct for 1.32-1.34?**
  - It is safe (it never breaks a node) but more conservative than necessary.
  - The key is Beta in 1.31-1.34, and its gate `TopologyManagerPolicyBetaOptions` is Beta/default-on there (table above).
  - Bottlerocket renders no `featureGates` that could turn it off (1.31/1.32 have no featureGates block; 1.33/1.34 only DRA/MutableCSINodeAllocatableCount, `core-kit/packages/kubernetes-1.34/kubelet-config:233-235`) and offers no feature-gate setting.
  - So rendering it in 1.31-1.34 would be accepted by kubelet. Omitting it makes the setting a silent no-op there.
  - Choosing "GA only" matches the commit 628d29bfb message and docs. It is not a correctness bug, but it is the only escape hatch for hosts with more than 8 NUMA nodes running a non-none topology policy.
- **What 1.36/1.37 should contain**: exactly 1.35 lines 129-140 after `{{/if}}` of `topologyManagerPolicy` (line 128), i.e.
  ```
  {{#if settings.kubernetes.topology-manager-policy-options.prefer-closest-numa-nodes}}
  topologyManagerPolicyOptions:
    prefer-closest-numa-nodes: "{{settings.kubernetes.topology-manager-policy-options.prefer-closest-numa-nodes}}"
  {{#if settings.kubernetes.topology-manager-policy-options.max-allowable-numa-nodes}}
    max-allowable-numa-nodes: "{{settings.kubernetes.topology-manager-policy-options.max-allowable-numa-nodes}}"
  {{/if}}
  {{else}}
  {{#if settings.kubernetes.topology-manager-policy-options.max-allowable-numa-nodes}}
  topologyManagerPolicyOptions:
    max-allowable-numa-nodes: "{{settings.kubernetes.topology-manager-policy-options.max-allowable-numa-nodes}}"
  {{/if}}
  {{/if}}
  ```
  If 1.31-1.34 should also get it, use the same block there in place of the prefer-only block. For 1.31 also add prefer-closest, which is Beta and default-on there.
- **Migration**: same v1.60.0 `AddSettingsMigration` (`bottlerocket/sources/settings-migrations/v1.60.0/kubernetes-topology-manager-policy-options/src/main.rs:10`). Correct.
- **Docs**: `website/repo/data/settings/1.60.x/kubernetes.toml:5` says "`uint` >= 8 (available Kubernetes 1.35 onwards)", which is false for 1.36/1.37 today.
  The example at `:12-16` has `max-allowable-numa-nodes = "\"8\""`. The website partial prints values verbatim (`website/repo/layouts/partials/settings-example-tab-pane.html:22-28`), so the TOML tab shows `max-allowable-numa-nodes = "8"`, a TOML string.
  A mirror of the model's serde attributes rejects that string with `invalid type: string "8", expected u32` (verified in `/tmp/k8s-settings-research/scratch/serdecheck`).
  The apiserver deserializes PATCH bodies into the typed model (`core-kit/sources/api/apiserver/src/server/mod.rs:317-318`), so copy-pasted user-data would be rejected. End-to-end inferred.
  The apiclient tab (`...="8"` in shell) works, because the shell strips the quotes.

### How to verify it works on a node
- Cheap (any instance, about 10 min/version): use the combined user-data in the previous section.
  - On 1.35, expect configz `"max-allowable-numa-nodes":"16"`, the log `MaxAllowableNUMANodes:16`, and the `WARNING: the value of max-allowable-numa-nodes is more than the default recommended value` line.
  - On every other version today, expect `MaxAllowableNUMANodes:8` and no warning.
  - The warning plus the `Creating topology manager with policy per scope` line together prove kubelet parsed and accepted the value. A non-none `topology-manager-policy` is required.
- Behavioral: only observable on a host with more than 8 NUMA nodes and a non-none topology policy.
  - Without the option, kubelet fails `unsupported on machines with more than 8 NUMA Nodes`. With `max-allowable-numa-nodes >= node count` it starts.
  - Typical EC2 instances do not have more than 8 NUMA nodes (inferred), so in practice only the cheap check is feasible.
- Upstream e2e: `1.37:test/e2e_node/topology_manager_test.go:1433-1439` (runs the suite with the value 16; present since `1.31:test/e2e_node/topology_manager_test.go:969-974`). It only checks that nothing breaks.

### Findings
- **[bug] 1.36 and 1.37 do not render `max-allowable-numa-nodes`** (same root cause as above).
  - Input: aws-k8s-1.36, a host with more than 8 NUMA nodes, `topology-manager-policy = "restricted"`, `max-allowable-numa-nodes = 16`.
  - Effect: kubelet still fails with `unsupported on machines with more than 8 NUMA Nodes` (`1.36:pkg/kubelet/cm/topologymanager/topology_manager.go:188-189`). On normal hosts it is a silent no-op.
  - Fix: copy the 1.35 block (above).
- **[risk] Not rendered on 1.31-1.34 although kubelet accepts it there with default gates.** Silent no-op, documented as "1.35 onwards". Suggest rendering it in 1.31-1.34 too: Beta, gate on by default and not changeable by users.
- **[nit] Docs TOML example quotes the number.** `max-allowable-numa-nodes = "8"` would be rejected by the u32 model type (verified with a mirror serde type; end-to-end inferred). Fix: change `"\"8\""` to `"8"` in `website/repo/data/settings/1.60.x/kubernetes.toml:16`, and fix the "1.32/1.35 onwards" text once 1.36/1.37 render the keys (or say "1.32-1.35" until then).

---

## Script feedback

- `python3 -I $T/k8s-field-report.py field cpuManagerPolicyOptions` and `... field topologyManagerPolicyOptions`:
  - For map-of-options fields it reports only the struct-level gate taken from the doc comment (`CPUManagerPolicyOptions`, `TopologyManagerPolicyOptions`). It never shows the per-key registry (`alphaOptions` / `betaOptions` / `stableOptions` in `pkg/kubelet/cm/{cpumanager,topologymanager}/policy_options.go`), nor the `*PolicyAlphaOptions` / `*PolicyBetaOptions` gates that actually decide whether kubelet starts. Those are exactly what changes between versions here.
  - It also omits the runtime validators (`NewStaticPolicyOptions`, `NewPolicyOptions`, `NewNonePolicy`), because validation is not in `validation.go`.
  - Suggest: when a field is a `map[string]string` consumed by a `CheckPolicyOptionAvailable`-style function, print per-key maturity per version with path:line, and a diff of the sets.
- `python3 -I $T/k8s-field-report.py gate <Gate>`: prints maturity history but no `path:line`, so every citation had to be grepped manually. Adding the definition and spec line numbers would make it directly citable.
- `python3 -I $T/kubelet-config-lint.py`:
  - Reported "no issues" for all versions, yet 1.32 renders the Alpha-gated key `strict-cpu-reservation` (node fails to start). The lint only checks top-level paths, not keys inside option maps or the values enumerated in `{{#if (eq this "...")}}` filters.
  - It also cannot catch the 1.33 bug: `(or a b c)` silently ignores `c` in handlebars 4.5.0 (`helper_extras.rs:12-13`). An arity check for `or`/`and`/`eq` (exactly 2 params) would catch it.
  - Suggest: cross-check enumerated map keys against the per-version option registries, and flag n-ary `or`/`and`.
- `python3 -I $T/template-drift.py kubernetes --matrix`:
  - Correctly flagged the 1.35 to 1.36 drop of both topology keys.
  - It shows `cpu-manager-policy-options` as `x` in every version although the set of values that render differs per version (1.31: 1, 1.32: 2, 1.33: 2 effective, 1.34+: 4). Value-level drift inside `{{#each}}` filters is invisible.
  - It only flags "rendered in N, missing in N+1". It does not flag keys missing in older versions that upstream supports (1.31 prefer-closest, 1.31-1.34 max-allowable). Combining it with the field report ("supported upstream but not rendered") would surface these.
- Missing tool: none of the scripts render templates.
  - A strict-mode handlebars 4.5.0 render of the real template lines found the 1.33 bug in seconds and proved the 1.35 nested if/else for all combinations.
  - My scratch harness is `a scratch handlebars harness (scripts/render-template.sh now does this with schnauzer itself)` (built-in helpers only; usage `hbrender <template> <start> <end> '<settings-json>'`).
  - Adding a render step (ideally via schnauzer's own registry so custom helpers work) with a per-version settings fixture would catch both classes of bug.
