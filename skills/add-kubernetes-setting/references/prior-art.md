# Prior art: every shipped Kubernetes setting and what it taught

**Keywords:** kubernetes settings history, settings-sdk PRs, core-kit PRs, bottlerocket migrations, lessons learned

Research date: 2026-11-17.
Mapped from merge commits in each repo (`git log -S<setting>`), PR bodies, and `git tag --contains`.

## The PR sets

| SDK PR | Setting(s) | Upstream target | Models release | core-kit PR(s) | bottlerocket PR(s) | Docs PR | Notes |
|---|---|---|---|---|---|---|---|
| [#69](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/69) | `device-ownership-from-security-context` | containerd CRI | v0.7.0 | [#329](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/329), [#343](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/343) | [#4345](https://github.com/bottlerocket-os/bottlerocket/pull/4345) | [#505](https://github.com/bottlerocket-os/bottlerocket-project-website/pull/505) | #343: the NVIDIA containerd templates were missed |
| [#80](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/80) | `container-log-max-workers`, `container-log-monitor-interval` | kubelet config | v0.9.0 | [#487](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/487) | [#4506](https://github.com/bottlerocket-os/bottlerocket/pull/4506) | [#555](https://github.com/bottlerocket-os/bottlerocket-project-website/pull/555) | model accepts values kubelet rejects |
| [#81](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/81) | `single-process-oom-kill` | kubelet config | v0.9.0 | [#489](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/489) | [#4506](https://github.com/bottlerocket-os/bottlerocket/pull/4506) | [#555](https://github.com/bottlerocket-os/bottlerocket-project-website/pull/555) | 1.32+; `#if` dropping `false` is harmless here |
| [#87](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/87) | `image-minimum-gc-age`, `image-maximum-gc-age` | kubelet config | v0.17.0 | [#689](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/689) | [#4690](https://github.com/bottlerocket-os/bottlerocket/pull/4690) | [#560](https://github.com/bottlerocket-os/bottlerocket-project-website/pull/560) | cross-field rule (max > min) not enforced |
| [#88](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/88) | `memory-swap-behavior` | `memorySwap.swapBehavior` | v0.11.0 | [#541](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/541) | [#4566](https://github.com/bottlerocket-os/bottlerocket/pull/4566) | none | nested struct; scoped to versions where NodeSwap is on |
| [#93](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/93) | `static-pods-enabled` | `staticPodPath` | v0.13.0 | [#641](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/641) | [#4628](https://github.com/bottlerocket-os/bottlerocket/pull/4628) | none | tri-state render with nested `if_not_null` / `#if` |
| [#98](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/98) | `kube-reserved.pid`, `system-reserved.pid` | `kubeReserved.pid` | v0.16.0 | [#646](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/646) | [#4650](https://github.com/bottlerocket-os/bottlerocket/pull/4650), reverted [#4660](https://github.com/bottlerocket-os/bottlerocket/pull/4660), re-landed [#4661](https://github.com/bottlerocket-os/bottlerocket/pull/4661) | none | release coordination (below) |
| [#104](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/104) | `ids-per-pod`, `max-parallel-image-pulls`, beta `cpu-manager-policy-options` | kubelet config | v0.17.0 | [#689](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/689), fix [#1060](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/1060), revert [#747](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/747) | [#4690](https://github.com/bottlerocket-os/bottlerocket/pull/4690) | [#560](https://github.com/bottlerocket-os/bottlerocket-project-website/pull/560) | wrong path; harmful default; per-version option maturity |
| [#108](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/108) | `fail-cgroup-v1` | `failCgroupV1` | v0.18.0; fix [#110](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/110); reverted [#111](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/111) in v0.20.0 | [#792](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/792) hardcodes `failCgroupV1: false`; [#803](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/803) | none | none | a knob was not needed: hardcoding kept the old default |
| [#117](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/117) | `topology-manager-policy-options.*` | `topologyManagerPolicyOptions` | v0.22.0 | [#901](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/901) ([#848](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/848) closed) | [#4778](https://github.com/bottlerocket-os/bottlerocket/pull/4778) | [#588](https://github.com/bottlerocket-os/bottlerocket-project-website/pull/588) | lost in kubernetes-1.36/1.37 templates |
| [#141](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/141) | `container-runtime-endpoint` | kubelet flag | v0.25.0 | [#968](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/968), [#978](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/978) | [#4887](https://github.com/bottlerocket-os/bottlerocket/pull/4887), [#4890](https://github.com/bottlerocket-os/bottlerocket/pull/4890) | none | deprecated flag; `Url` too loose |
| [#147](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/147) | `memory-reservation-policy`, `memory-throttling-factor` | MemoryQoS | v0.27.0 | [#1029](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/1029) | [#4922](https://github.com/bottlerocket-os/bottlerocket/pull/4922) | none | 1.37 only: gate on, semantics reworked |
| [#159](https://github.com/bottlerocket-os/bottlerocket-settings-sdk/pull/159) | `merge-default-eviction-settings` | `mergeDefaultEvictionSettings` | v0.32.0 | [#1089](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/1089), [#1120](https://github.com/bottlerocket-os/bottlerocket-core-kit/pull/1120) | [#4991](https://github.com/bottlerocket-os/bottlerocket/pull/4991) | [#616](https://github.com/bottlerocket-os/bottlerocket-project-website/pull/616) | good model: `if_not_null`, render test, `/configz` evidence |

Typical shape of each PR:

- settings-sdk: field and tests in `settings-extensions/kubernetes/src/lib.rs`, a type in `modeled-types/src/kubernetes.rs` when needed, minor bumps of the touched crates and `settings-models`, and workspace pins.
- core-kit: one commit per `kubernetes-1.X` template (or one for all), the settings-models tag bump, sometimes a schnauzer test.
- bottlerocket: settings-models tag bump, `AddSettingsMigration` crate under `sources/settings-migrations/v<next>/`, the `Release.toml` edge, and a version bump when the current version is already released.

## Lessons

1. **A key in the wrong place silently does nothing** (core-kit #1060).
   `idsPerPod` was rendered at the root instead of under `userNamespaces` for about ten months.
   kubelet's lenient decoding only logs a warning.
   Countermeasures: `kubelet-config-lint.py` (would have flagged `UNKNOWN idsPerPod`), render tests that assert the nested path, `/configz` on a node.
2. **A new default can break users** (core-kit #747).
   #689 added `enableDebuggingHandlers: false` "as the default", which broke `kubectl logs`.
   Unset must render nothing.
3. **Templates copied for a new Kubernetes minor lose changes made in parallel** (topology options, lost in 1.36 and 1.37).
   The 1.36 template was copied from a 1.35 that predated core-kit #901 and was added one day after #901 merged.
   Countermeasures: `template-drift.py` in every PR that adds a `kubernetes-1.X` package; render tests that cover every version.
4. **Option maturity differs per version** (cpu-manager-policy-options).
   `strict-cpu-reservation` is Alpha in 1.32, and the 1.32 template rendered it, so kubelet would refuse to start.
   The 1.33 template listed three options in a handlebars `or`, which reads only two, so `distribute-cpus-across-numa` was dropped.
   Countermeasures: `kubelet-validate.sh` (reports the Alpha option as FATAL) and render tests asserting the exact option set per version.
5. **Fields can exist and still be wrong to render** (MemoryQoS, crashLoopBackOff).
   `memoryReservationPolicy` exists in 1.36 but `TieredReservation` with the gate off fails validation; `memoryThrottlingFactor` exists from 1.31 but does nothing until 1.37 and changed meaning in 1.37.
   `crashLoopBackOff.maxContainerRestartPeriod` exists from 1.32 but is rejected until the gate turns on in 1.35.
   Countermeasures: read `+featureGate` markers and gate maturity per version (`k8s-field-report.py`), `kubelet-config-lint.py` GATED, and the Phase 2 counterfactual.
6. **The model is the user's only guard, and it is often looser than kubelet.**
   Accepted values that make kubelet exit: log workers <= 0, monitor interval < 3s, max GC age <= min, negative parallel pulls, negative ids-per-pod, quantities like `1K`, eviction values `0`.
   Countermeasures: differential tests against upstream parsers, and the Phase 2 boundary matrix through `kubelet-validate.sh`.
7. **Release order is a correctness requirement, not a convenience** (bottlerocket #4650, #4660, #4661).
   core-kit 10.7.0 had an unrelated NVIDIA regression, so Bottlerocket 1.49.0 rolled back to core-kit 10.6.0, and the models bump and migration had to roll back with it: pluto in the older core-kit could not parse the new key.
   The migration was renamed when it re-landed for 1.50.0.
8. **Variants have more than one template per package** (core-kit #343).
   The NVIDIA containerd templates were missed for one release, and the setting did nothing on NVIDIA variants.
   Countermeasure: `template-drift.py` MISSING checks across template flavors.
9. **Not every knob should be a setting** (settings-sdk #108, #111).
   Kubernetes 1.35 flipped the `failCgroupV1` default; Bottlerocket kept the old behavior by hardcoding `false` instead of shipping a setting.
   Ask whether a hardcoded value or a default is the better product decision before adding API surface.
10. **Docs are part of the change.**
    Six shipped settings have no website entry, and one entry documents the wrong default.
11. **Merged PRs show the final tag bump, not how they were tested.**
    Pre-release testing used throwaway overrides that never got committed; `use-local-settings-sdk.py` is the recorded, repeatable version.
