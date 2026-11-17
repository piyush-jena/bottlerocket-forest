# Reading Kubernetes and containerd source per version

**Keywords:** kubelet source, KubeletConfiguration, feature gates, validation, defaults, eks-d, per-version, containerd cri config

Always read the source core-kit actually builds: the EKS-D tarball pinned (with sha512) in `packages/kubernetes-1.X/Cargo.toml`, version in `%global gover` of the spec.
`scripts/fetch-package-source.sh` unpacks it; `scripts/k8s-field-report.py` prints the first-pass facts with `path:line` for every packaged version.
Docs are a cross-check: the kubelet config reference (kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/) and the KEP.
When docs and source disagree, source wins (for example the upstream comment for `mergeDefaultEvictionSettings` lists four default signals; the code merges five).

## Where each question is answered (kubelet)

| Question | File (relative to the version's `src/`) | Notes |
|---|---|---|
| Does the field exist, what is its JSON path and Go type? | `staging/src/k8s.io/kubelet/config/v1beta1/types.go` | Pointer types (`*bool`, `*int32`) mean "unset" is distinct from zero. Map types mean the next path element is a key, parsed elsewhere. |
| Which gate does it need? | `+featureGate=` markers on the field, then `pkg/features/kube_features.go` (1.33+), `versioned_kube_features.go` (1.32), unversioned map entries (1.31) | A gate's state in version X is the last spec entry with Version <= X. Markers can be misspelled (`UserNamespaceSupport`) or dropped at GA. |
| What is the default? | `pkg/kubelet/apis/config/v1beta1/defaults.go` | Defaults may depend on a gate (`crashLoopBackOff` is only defaulted when its gate is on) or on the host (`singleProcessOOMKill` depends on cgroup version, in `pkg/kubelet/kubelet.go`). |
| What does validation reject? | `pkg/kubelet/apis/config/validation/validation.go`, `validation_linux.go`, `validation_reserved_memory.go` | Validation failures stop kubelet. Validation often goes through local aliases (`userNs := kc.UserNamespaces`). |
| What else is parsed at startup and can still stop kubelet? | `cmd/kubelet/app/server.go` (`loadConfigFile`, `run`: `parseResourceList`, `eviction.ParseThresholdConfig`, `cm.ParseQOSReserved`), `pkg/kubelet/kubelet.go` (`NewMainKubelet`) | `kubeReserved`/`systemReserved` values and eviction thresholds are only parsed here, not in validation. |
| Are option names valid in this version? | `pkg/kubelet/cm/cpumanager/policy_options.go`, `pkg/kubelet/cm/topologymanager/policy_options.go` | `alphaOptions` / `betaOptions` / `stableOptions` sets; Alpha options need `CPUManagerPolicyAlphaOptions` / `TopologyManagerPolicyAlphaOptions`. |
| What does the field actually do? | grep the Go field name in `pkg/kubelet` and `cmd/kubelet`, then follow the plumbing into `pkg/kubelet/cm`, `kuberuntime`, `eviction`, `images`, ... | The report lists direct references only. Compare the consuming code across versions: behavior can change while the field does not (`memoryThrottlingFactor` in 1.37). |
| How does upstream test it? | `test/e2e_node/*` | Read the assertions: a file mentioning a field is not proof of coverage (the swap e2e test never applies its pod resources). |
| Is a flag deprecated, and which field does it set? | `cmd/kubelet/app/options/options.go` (`AddKubeletConfigFlags` deprecates every flag bound to a config field), `globalflags_linux.go` | Prefer rendering the config field. |
| How is the config file merged with flags and drop-ins? | `cmd/kubelet/app/server.go` (`mergeKubeletConfigurations`, `kubeletConfigFlagPrecedence`) | Drop-ins (`--config-dir`) do not get eviction default merging. |

## How to read across versions

1. Run `k8s-field-report.py field <path>` for all versions and read the "Changes between consecutive versions" section first: it shows where the field appears, where gates flip, and where validation or defaults change.
2. For each version where something changes, open both versions' files at the cited lines.
3. Check the gate in every version the template would render: `k8s-field-report.py gate <Gate>`.
   Beta and on: renders as is.
   Alpha and off: the field is either rejected (validation checks the gate) or ignored (the consumer checks the gate); find which.
   GA and locked: setting the gate to its locked value is allowed with a warning, any other value stops kubelet.
4. Look for semantic changes in the consumer, not just the field: grep the field in both versions and diff the functions.
5. Confirm with `kubelet-validate.sh`: render the setting for every version, and for each version you decided not to render, append the field to its rendered file and validate (the counterfactual).

## Signals that a version should not render a setting

- The field is absent in `types.go`.
- Its gate is Alpha (off by default) and Bottlerocket does not enable it.
- Validation rejects any non-default value while the gate is off (`crashLoopBackOff` before 1.35, `memoryReservationPolicy: TieredReservation` before 1.37).
- The field is accepted but ignored (no consumer runs), so the setting would mislead (`memoryThrottlingFactor` before 1.37).
- An upstream bug makes the field ineffective (`userNamespaces.idsPerPod` on 1.33/1.34, kubernetes#133144): document it, and decide with the user whether to render.

## containerd CRI options

| Question | Where |
|---|---|
| Struct and TOML key | `k8s-field-report.py containerd <toml_key>`, then the struct in `pkg/cri/config/config.go` (1.7) or `internal/cri/config/config.go` (2.x) |
| TOML table the key lives in | the plugin registration: 1.7 `pkg/cri/cri.go` (`io.containerd.grpc.v1.cri`); 2.x `plugins/cri/runtime/plugin.go` (`io.containerd.cri.v1.runtime`) and siblings |
| Default | the `DefaultConfig` functions in the config package; otherwise the Go zero value |
| Config `version` the release accepts | `version = 2` for 1.7; 2.x accepts 2 and 3 and migrates them, 2.3 also 4 |
| What it does | grep the Go field in `internal/cri/server` / `pkg/cri/server` and `internal/cri/opts` |
| Which variants use which containerd | `bottlerocket/variants/*/Cargo.toml` and core-kit package dependencies; NVIDIA variants render `*_nvidia_*` templates |
| What restarts when it changes | core-kit `packages/containerd-*/` `affected-services` metadata and the variant's defaults |

containerd settings cannot be checked by `kubelet-validate.sh`; verify the rendered TOML with `verify-node.sh --file /etc/containerd/config.toml --file-path '<table>.<key>'` and the behavior on a node.
