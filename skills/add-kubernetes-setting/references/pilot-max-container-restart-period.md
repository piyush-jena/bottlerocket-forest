# Worked run: settings.kubernetes.max-container-restart-period (bottlerocket#4979)

**Keywords:** worked example, pilot, crashLoopBackOff, maxContainerRestartPeriod, KubeletCrashLoopBackOffMax, topology-manager-policy-options, cpu-manager-policy-options

The first full run of this skill, on 2026-11-17, local branches only (nothing pushed).
It also fixed three template bugs that the audit found, to exercise the "fix an existing setting" path.
Full evidence: `planning/k8s-settings-skill/evidence/` in the forest.

## Spec in brief

User request: bottlerocket#4979 asks for the kubelet's `crashLoopBackOff.maxContainerRestartPeriod`, so crash-looping pods retry sooner than every 5 minutes.

| Version | Field | Gate `KubeletCrashLoopBackOffMax` | Default when unset | Decision |
|---|---|---|---|---|
| 1.31 | absent | not defined | n/a | do not render |
| 1.32-1.34 | present | Alpha, off (`pkg/features/kube_features.go`) | none (only defaulted when the gate is on) | do not render: validation rejects the field while the gate is off ("FeatureGate KubeletCrashLoopBackOffMax not enabled, CrashLoopBackOff.MaxContainerRestartPeriod must not be set") |
| 1.35-1.37 | present | Beta, on | 300s (`defaults.go`) | render |

- Validation (all versions with the field): 1s to 300s, as `Duration.Milliseconds()` in [1000, 300000] (`validation.go`).
- Consumer: `newCrashLoopBackOff` in `pkg/kubelet/kubelet.go` uses it as the backoff maximum and lowers the 10s initial backoff when the maximum is smaller.
- Model: new `KubernetesMaxContainerRestartPeriod` (Kubernetes duration syntax, bounded), differential-tested against Go's `time.ParseDuration` and kubelet's range check (28 inputs, no disagreement where Bottlerocket is looser; Bottlerocket is stricter for `1s1m` and `1.s`).
- Render: `{{#if}}` (no meaningful falsy value), a new `crashLoopBackOff:` parent, only in kubernetes-1.35/1.36/1.37.
- Migration: `AddSettingsMigration` in `v1.70.0` (1.69.0 was already tagged, so a version bump).

## Changes

| Repo | Branch | Commits |
|---|---|---|
| settings-sdk (clone at `~/scratch/k8s-settings-pilot/settings-sdk`) | `pilot/max-container-restart-period` | `c81c690` kubernetes: add max-container-restart-period setting; `5428cdc` settings-models: fix clippy findings from newer toolchains |
| core-kit (grove) | `local/k8s-settings-pilot` | `42f8149` 1.36/1.37 render topology-manager-policy-options; `66f20f2` 1.32 do not render Alpha strict-cpu-reservation; `ce0031c` 1.33 render distribute-cpus-across-numa; `976c92e` schnauzer policy-options tests; `85cca2c` DO NOT MERGE local settings-sdk; `5c5077a` 1.35+ crashLoopBackOff + tests |
| bottlerocket (grove) | `local/k8s-settings-pilot` | `76e6d9a` release 1.70.0; `debd888` migration; `6433fad` DO NOT MERGE local settings-sdk; `c471bd8` DO NOT MERGE local core-kit |

## Offline checks

- settings-sdk: 475 tests pass; `cargo clippy --workspace --all-targets -- -D warnings` clean (after fixing 19 pre-existing findings from rustc 1.98).
- core-kit render tests: 34 pass with the changes; without the template changes the 9 crash-loop cases and the 1.32, 1.33, 1.36 and 1.37 policy cases fail.
- `kubelet-validate.sh`, values `1s`, `300s`, `5m`: OK on 1.31-1.37.
  `0.5s`: rejected by the model (render exits 3).
  Counterfactual, field forced into 1.32 and 1.34 renders: FATAL, "FeatureGate KubeletCrashLoopBackOffMax not enabled"; 1.35: OK.
- CPU and topology options on the develop templates: kubelet 1.32 FATAL "CPU Manager Policy Alpha-level Options not enabled, but option strict-cpu-reservation provided"; after the fixes: OK on 1.31-1.37.

## Nodes (EKS, us-west-2, m5.large, tainted)

| Node | Image | Purpose | Result |
|---|---|---|---|
| stock-136 | stock aws-k8s-1.36 v1.69.0 | baseline; reproduce topology bug | `topologyManagerPolicyOptions: null` although the API stores the option |
| pilot-a | 1.70.0 pilot aws-k8s-1.36 | rungs 1-6 | all pass (below) |
| pilot-b | 1.70.0 pilot aws-k8s-1.36, nothing new set | baseline, rung 7 | `/configz` equals stock-136 except user-set keys and providerID |
| pilot-134 | 1.70.0 pilot aws-k8s-1.34 | rung 8 | API stores `60s`, nothing rendered, `crashLoopBackOff: {}`, Ready |
| stock-132 / pilot-132 | v1.69.0 / 1.70.0 aws-k8s-1.32 | strict-cpu-reservation | stock: kubelet exits ("Alpha-level Options not enabled"), never registers; pilot: Ready, option not rendered |
| stock-133 / pilot-133 | v1.69.0 / 1.70.0 aws-k8s-1.33 | distribute-cpus-across-numa | stock: `/configz` has only `full-pcpus-only`; pilot: both options |

pilot-a ladder:

1. Joins with `max-container-restart-period = "5s"`: Ready.
2. `apiclient get`: `"5s"`.
3. `0.5s`, `301s`, `1h`, `60`: rejected with the model's message; value unchanged.
4. Rendered file and `/configz`: `crashLoopBackOff.maxContainerRestartPeriod: "5s"`; topology options `{"prefer-closest-numa-nodes":"true"}`; no kubelet config warnings.
5. Behavior (crash-looping busybox): 20 restarts in 133s with `5s` vs 4 on pilot-b.
6. Live change to `30s`: kubelet restarted, `/configz` `"30s"`; gaps between restarts 10, 28, 34, 31, 44, 41, 44s vs 12, 28, 51, 84s on pilot-b and 15, 28, 44, 91s on stock-136.

Base: the forest's bare repos were behind GitHub on that day (GitHub bottlerocket develop was already on an untagged 1.70.0 with an empty `(1.69.0, 1.70.0)` edge, and core-kit develop on 18.1.0), so before PRs the branches must be rebased onto current develop, `76e6d9a` dropped, and the migration added to the existing edge.

Not done: upgrade/downgrade (needs an HTTPS-served S3 prefix for the test TUF repo; the user decides which bucket), website docs PR.

## What the run changed in the skill

- `verify-node.sh` needed an admin-container preflight and the `settings.` prefix for `apiclient get`.
- `kubelet-validate.sh` gained the startup parsers (`parseResourceList`, eviction thresholds, `qosReserved`) after an audit claim (`kube-reserved` `1K`) passed validation but fails on a real kubelet.
- The local-kit workflow needed the `[<vendor>.<kit>]` override form; brdev and `build-variant-from-local-kits` were fixed.
- Background probes started from a shell that exits are killed: run behavior probes in the foreground.
- An independent run of Phases 0-2 by a fresh agent (imagePullCredentialsVerificationPolicy) led to: gates from enclosing validation blocks, callee digests in the field report, validation-derived GATED in the lint, `counterfactual.py` and `boundary-matrix.py`, read-only sources for `kubelet-validate.sh`, the "before you start" sync step, baseline-first checks, and the cross-field guard and HTML-escaping notes.
