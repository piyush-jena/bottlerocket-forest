<!-- Audit of shipped settings, 2026-11-17, against core-kit a4f438b1f, settings-sdk 06d9d1a, bottlerocket b7c6c274,
     and the EKS-D sources packaged in core-kit for Kubernetes 1.31-1.37 (containerd 1.7/2.2/2.3).
     Line numbers drift; re-run scripts/k8s-field-report.py before relying on a citation.
     Status of the findings as of this date: see ../../SKILL.md "Known open findings". -->

# logs-images

Scope: `settings.kubernetes.container-log-max-workers`, `container-log-monitor-interval`, `image-minimum-gc-age`, `image-maximum-gc-age`, `max-parallel-image-pulls`, on Bottlerocket Kubernetes 1.31 through 1.37.

Path legend (upstream, relative to each version's `src/`):

- `types.go` = `staging/src/k8s.io/kubelet/config/v1beta1/types.go`
- `defaults.go` = `pkg/kubelet/apis/config/v1beta1/defaults.go`
- `validation.go` = `pkg/kubelet/apis/config/validation/validation.go`
- `gcm.go` = `pkg/kubelet/images/image_gc_manager.go`
- `clm.go` = `pkg/kubelet/logs/container_log_manager.go`

Bottlerocket paths are relative to the grove root:

- `lib.rs` = `bottlerocket-settings-sdk/bottlerocket-settings-models/settings-extensions/kubernetes/src/lib.rs`
- `mt/kubernetes.rs` = `bottlerocket-settings-sdk/bottlerocket-settings-models/modeled-types/src/kubernetes.rs`
- `kc-1.3X` = `kits/bottlerocket-core-kit/packages/kubernetes-1.3X/kubelet-config`

## Facts shared by every setting in this group

- **Validation failures are fatal.** kubelet validates the merged config and returns an error if it fails (1.31:cmd/kubelet/app/server.go:251-253, 1.37:cmd/kubelet/app/server.go:265-267). `kubelet.service` has `Restart=always`, `RestartSec=5` (`kits/bottlerocket-core-kit/packages/kubernetes-1.37/kubelet.service:17-19`). So kubelet crash-loops and the node never becomes Ready.
- **Runtime changes restart kubelet.** A runtime `apiclient set` re-renders `/etc/kubernetes/kubelet/config` and runs `systemctl try-restart kubelet.service` (`bottlerocket/sources/shared-defaults/kubernetes-services.toml:1-17`). A bad value set at runtime therefore takes a joined node NotReady.
- **No unset.** The API has no settings delete, only overwrite (`kits/bottlerocket-core-kit/sources/api/apiserver/src/server/mod.rs:105`: delete exists only for transactions). The only "reset" is to write a value that the template skips or that kubelet treats as default.
- **Duration parse errors are fatal.** Durations decode through `metav1.Duration.UnmarshalJSON`, which calls `time.ParseDuration` (1.37:staging/src/k8s.io/apimachinery/pkg/apis/meta/v1/duration.go:32-45). A parse error is not a strict-decoding error, so the lenient fallback is not tried and kubelet fails with `failed to decode` (1.37:pkg/kubelet/kubeletconfig/util/codec/codec.go, `DecodeKubeletConfiguration`).
- **Bottlerocket duration type.** `KubernetesDurationValue` (`mt/kubernetes.rs:856-886`) is the regex `^(([0-9]+\.)?[0-9]+h)?(([0-9]+\.)?[0-9]+m)?(([0-9]+\.)?[0-9]+s)?(([0-9]+\.)?[0-9]+ms)?$` plus a non-empty check. It has no sign and no range check.
  - I compiled the same regex with Go RE2 next to `time.ParseDuration` (scratch program a scratch probe (not kept)).
  - **Bottlerocket accepts, Go rejects:** values that overflow int64 nanoseconds. `2562047h` is OK, but `2562048h`, `9999999999h` and `99999999999999999999s` give `time: invalid duration`.
  - **Go accepts, Bottlerocket rejects:** only non-canonical forms. These are bare `0`, out-of-order or repeated units (`30s1m`, `1h1h`), `.5s`, `1.s`, signed values, and the `us`/`µs`/`ns` units.
- **Integers.** `container-log-max-workers` and `max-parallel-image-pulls` are plain `i32` (`lib.rs:68`, `lib.rs:107`), with the same range as kubelet's `*int32`. There is no minimum.
- **No model-level validation.** `KubernetesSettingsV1::set` and `validate` both return `Ok(())` (`lib.rs:121-124`, `lib.rs:136-138`).
- **Helper truthiness** (handlebars 4.5.0, the only version in `kits/bottlerocket-core-kit/sources/Cargo.lock:3034-3035`; schnauzer does not override `if`):
  - Numbers are truthy when `f.is_normal()`. So `0` is false, and negative numbers are true and get rendered.
  - With `includeZero=true` any non-NaN number is truthy.
  - Strings are truthy when non-empty, so `"0s"` is rendered.
  - Source: `~/.cargo/registry/src/*/handlebars-4.5.0/src/json/value.rs:148-164`, `src/helpers/helper_if.rs:26-31`.
- **Rendered YAML types are safe.** Durations are rendered unquoted. The regex guarantees a unit suffix, so YAML always reads them as strings, which `metav1.Duration` requires. Integers are rendered unquoted and read as YAML ints.

---

## settings.kubernetes.container-log-max-workers

### Upstream per version
| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `containerLogMaxWorkers` `*int32` (1.31:types.go:610), no flag | 1 (1.31:defaults.go:242-243) | `< 1` rejected (1.31:validation.go:296-298) | none | consumed 1.31:pkg/kubelet/kubelet.go:644; workers started 1.31:clm.go:189-193 |
| 1.32 | yes | same (1.32:types.go:616) | 1 (1.32:defaults.go:260) | `< 1` rejected (1.32:validation.go:337) | none | 1.32:pkg/kubelet/kubelet.go:682 |
| 1.33 | yes | same (1.33:types.go:665) | 1 (1.33:defaults.go:263) | `< 1` rejected (1.33:validation.go:364) | none | 1.33:pkg/kubelet/kubelet.go:718 |
| 1.34 | yes | same (1.34:types.go:666) | 1 (1.34:defaults.go:263) | `< 1` rejected (1.34:validation.go:360) | none | 1.34:pkg/kubelet/kubelet.go:716; 1.34:clm.go:146-150 |
| 1.35 | yes | same (1.35:types.go:666) | 1 (1.35:defaults.go:263) | `< 1` rejected (1.35:validation.go:363) | none | 1.35:pkg/kubelet/kubelet.go:720 |
| 1.36 | yes | same (1.36:types.go:690) | 1 (1.36:defaults.go:264) | `< 1` rejected (1.36:validation.go:377) | none | 1.36:pkg/kubelet/kubelet.go:726 |
| 1.37 | yes | same (1.37:types.go:690) | 1 (1.37:defaults.go:262) | `< 1` rejected (1.37:validation.go:406-408) | none | 1.37:pkg/kubelet/kubelet.go:755; 1.37:clm.go:146-150 |

No upper bound in any version. kubelet starts exactly N goroutines at startup (`for i := 0; i < c.maxWorkers; i++ { go c.processQueueItems(...) }`, 1.37:clm.go:147-150).

### What changes between versions
None that changes behavior:

- The defaulter changed from `utilpointer.Int32(1)` (1.31:defaults.go:243) to `ptr.To[int32](1)` (1.32:defaults.go:261).
- The startup log moved from `klog.InfoS` (1.31-1.34:clm.go:189/146) to the contextual `logger.Info` (1.35:clm.go:146) with the same message.

### Bottlerocket implementation
- **Model:** `container_log_max_workers: i32` (`lib.rs:68`), no validation.
  - **Bottlerocket accepts, kubelet rejects (all versions 1.31-1.37):** any value `<= 0`.
  - **kubelet accepts, Bottlerocket rejects:** nothing.
- **Templates:** rendered in every version as `{{#if settings.kubernetes.container-log-max-workers includeZero=true}}containerLogMaxWorkers: {{...}}{{/if}}`:

  | version | lines |
  |---|---|
  | 1.31 | kc-1.31:175-177 |
  | 1.32 | kc-1.32:179-181 |
  | 1.33 | kc-1.33:182-184 |
  | 1.34 | kc-1.34:180-182 |
  | 1.35 | kc-1.35:188-190 |
  | 1.36 | kc-1.36:176-178 |
  | 1.37 | kc-1.37:176-178 |

  - Top-level key, unquoted YAML int.
  - Unset means not rendered, and kubelet uses its default of 1.
  - `0` is rendered as `containerLogMaxWorkers: 0` because of `includeZero=true`. Negative values are rendered because they are truthy.
  - `includeZero=true` only changes the outcome for exactly `0`, and `0` is invalid in every version, so the flag can only hurt here.
  - No feature gate is involved.
  - No version supports the field without rendering it, and none renders it where it is unsupported.
- **Migration:** present. `bottlerocket/sources/settings-migrations/v1.39.0/kubelet-setting-container-log-single-process-oom-kill/src/main.rs:9-14` (AddSettingsMigration), listed in `bottlerocket/Release.toml:418-420` and `bottlerocket/sources/Cargo.toml:55` (bottlerocket #4506).
- **Docs:** present at `bottlerocket-project-website/data/settings/1.39.x/kubernetes.toml:1-13`. They do not state the `>= 1` minimum.

### How to verify it works on a node
Setup:

```
NODE=<node-name>
cfgz() { kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig | {containerLogMaxSize,containerLogMaxFiles,containerLogMaxWorkers,containerLogMonitorInterval}'; }
```

Configure node B in a single transaction. Node A gets only the size and file settings, so rotation is visible on both:

```
apiclient set --json '{"kubernetes":{"container-log-max-size":"1Mi","container-log-max-files":10,"container-log-max-workers":4,"container-log-monitor-interval":"30s"}}'   # B
apiclient set --json '{"kubernetes":{"container-log-max-size":"1Mi","container-log-max-files":10}}'                                                                     # A
```

1. **configz.** Run `cfgz`.
   - B: `containerLogMaxWorkers: 4`.
   - A: `1`, which is the kubelet default (defaults.go above).
   - Same in all versions.
2. **Startup log** (V(0) in all versions, 1.31:clm.go:189, 1.37:clm.go:146). In sheltie: `journalctl -u kubelet --no-pager | grep 'Initializing container log rotate workers' | tail -1`.
   - B: `workers=4 monitorPeriod="30s"`.
   - A: `workers=1 monitorPeriod="10s"`.
   - The exact formatting of `monitorPeriod` is inferred: `metav1.Duration` promotes `String()` from the embedded `time.Duration`.
3. **Live worker count.** Bottlerocket does not set `enableDebuggingHandlers`, so the default `true` (1.37:defaults.go:121-122) keeps `/debug/pprof` installed (1.37:pkg/kubelet/server/server.go:364-369). Run:

   ```
   kubectl get --raw "/api/v1/nodes/$NODE/proxy/debug/pprof/goroutine?debug=2" | grep -c 'logs.(\*containerLogManager).processQueueItems('
   ```

   - Expected: B `4`, A `1`.
   - The stack-frame naming is inferred; I could not run a kubelet.
4. **Upstream test.** `test/e2e_node/container_log_rotation_test.go` "ContainerLogRotationWithMultipleWorkers" (1.31-1.36:112, 1.37:113-191) uses workers=2 and interval 3s. It only asserts that file count stays bounded, never the worker count, so check 3 is stronger.
5. **Negative test** (reproduces the finding below):
   - Run `apiclient set --json '{"kubernetes":{"container-log-max-workers":0}}'`.
   - `journalctl -u kubelet -n 50 --no-pager | grep -m1 'failed to validate kubelet configuration'` shows `containerLogMaxWorkers must be greater than or equal to 1`.
   - `systemctl show kubelet -p NRestarts` keeps increasing, and `kubectl get node $NODE` goes NotReady.
   - Recover with `apiclient set --json '{"kubernetes":{"container-log-max-workers":1}}'`.

Time: about 5 minutes per node.

### Findings
- **[bug] `container-log-max-workers` <= 0 is accepted and rendered, and kubelet refuses to start (1.31-1.37).**
  - Input: `settings.kubernetes.container-log-max-workers = 0` (or `-1`).
  - `lib.rs:68` (i32) accepts it.
  - kc-1.37:176-178 renders `containerLogMaxWorkers: 0`. `includeZero=true` forces 0 through; negative values are truthy anyway.
  - 1.37:validation.go:406-408 rejects it, which is fatal at 1.37:cmd/kubelet/app/server.go:265-267. Same for 1.31:validation.go:296.
  - Effect: at boot the node never joins; via a runtime `apiclient set` a working node goes NotReady.
  - Fix:
    - Add a `>= 1` integer modeled type and use it for this field. There is no `PositiveInteger` today; `NonNegativeInteger` is in `bottlerocket-settings-sdk/bottlerocket-settings-models/modeled-types/src/shared.rs:1371`.
    - Alternatively, drop `includeZero=true` so `0` means "kubelet default".
    - Document the minimum.
- **[nit] No upper bound.** kubelet spawns one goroutine per worker at startup (1.37:clm.go:147-150), so an absurd value such as `2147483647` would exhaust memory. Bottlerocket and kubelet both accept it; the outcome is inferred and not tested. An optional cap in the new modeled type would close this.

---

## settings.kubernetes.container-log-monitor-interval

### Upstream per version
| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `containerLogMonitorInterval` `*metav1.Duration` (1.31:types.go:618), no flag | 10s (1.31:defaults.go:245-246) | `.Seconds() < 3` rejected (1.31:validation.go:300-302) | none | consumed 1.31:pkg/kubelet/kubelet.go:645; loop `wait.Forever(..., period)` 1.31:clm.go:195-199 |
| 1.32 | yes | same (1.32:types.go:624) | 10s (1.32:defaults.go:263) | same (1.32:validation.go:341) | none | 1.32:pkg/kubelet/kubelet.go:683 |
| 1.33 | yes | same (1.33:types.go:673) | 10s (1.33:defaults.go:266) | same (1.33:validation.go:368) | none | 1.33:pkg/kubelet/kubelet.go:719 |
| 1.34 | yes | same (1.34:types.go:674) | 10s (1.34:defaults.go:266) | same (1.34:validation.go:364) | none | 1.34:pkg/kubelet/kubelet.go:717 |
| 1.35 | yes | same (1.35:types.go:674) | 10s (1.35:defaults.go:266) | same (1.35:validation.go:367) | none | 1.35:pkg/kubelet/kubelet.go:721 |
| 1.36 | yes | same (1.36:types.go:698) | 10s (1.36:defaults.go:267) | same (1.36:validation.go:381) | none | 1.36:pkg/kubelet/kubelet.go:727 |
| 1.37 | yes | same (1.37:types.go:698) | 10s (1.37:defaults.go:265) | same (1.37:validation.go:410-412) | none | 1.37:pkg/kubelet/kubelet.go:756; loop 1.37:clm.go:152-156 |

A pointer set to `0s` is non-nil, so the default does not apply and validation then rejects it.

### What changes between versions
None.

### Bottlerocket implementation
- **Model:** `container_log_monitor_interval: KubernetesDurationValue` (`lib.rs:69`).
  - **Bottlerocket accepts, kubelet rejects (all versions):**
    - anything under 3s: `0s`, `0ms`, `1s`, `2.9s`, `2999ms` (Go check shows `kubelet REJECTS (<3s)`);
    - overflowing values such as `2562048h`, which fail at decode.
  - **kubelet accepts, Bottlerocket rejects:** only non-canonical forms, such as `3000000000ns` or `1m30s` written as `30s1m`.
- **Templates:** rendered in every version as `{{#if settings.kubernetes.container-log-monitor-interval}}containerLogMonitorInterval: {{...}}{{/if}}`:

  | version | lines |
  |---|---|
  | 1.31 | kc-1.31:178-180 |
  | 1.32 | kc-1.32:182-184 |
  | 1.33 | kc-1.33:185-187 |
  | 1.34 | kc-1.34:183-185 |
  | 1.35 | kc-1.35:191-193 |
  | 1.36 | kc-1.36:179-181 |
  | 1.37 | kc-1.37:179-181 |

  - Top-level key, unquoted YAML string.
  - Unset means not rendered and the 10s default applies.
  - The only falsy string is `""`, which the model already rejects. `"0s"` is truthy and is rendered, so kubelet rejects it.
  - No gate. Rendered in every version that supports it, never where unsupported.
- **Migration:** same v1.39.0 migration as above (`.../v1.39.0/kubelet-setting-container-log-single-process-oom-kill/src/main.rs:11`).
- **Docs:** present at `website/repo/data/settings/1.39.x/kubernetes.toml:15-27`. They do not state the 3s minimum.

### How to verify it works on a node
Use the same A/B nodes as the previous setting (B: `"30s"`, A: default 10s, both with `container-log-max-size: 1Mi`, `container-log-max-files: 10`).

1. **configz.** Run `cfgz`. B shows `containerLogMonitorInterval: "30s"`, A shows `"10s"`.
2. **Startup log.** Same command as the previous section. B shows `monitorPeriod="30s"`.
3. **Rotation timing.** Start a log producer at about 1 MB/s (the rate is inferred: 500 kB of random data, base64-encoded, plus CRI line framing):

   ```
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: Pod
   metadata: {name: logspam}
   spec:
     nodeName: $NODE
     containers:
     - name: spam
       image: public.ecr.aws/docker/library/busybox:1.36
       command: ["sh","-c","while true; do head -c 500000 /dev/urandom | base64; sleep 1; done"]
   EOF
   ```

   After 3-4 minutes, run in sheltie: `ls -l --time-style=+%T /var/log/pods/default_logspam_*/spam/`.
   - Rotated files are named `0.log.YYYYMMDD-HHMMSS` (format at 1.37:clm.go:45, rename at 1.37:clm.go:416-420). All but the newest are `.gz`.
   - Consecutive suffix timestamps should be about 30-31s apart on B and about 10-11s apart on A. The period is sliding: `wait.Forever` restarts after each pass, so add up to about 1s.
   - The newest uncompressed rotated file holds roughly rate x interval: about 30 MB on B, about 10 MB on A. Both are far above the 1Mi cap, which shows the cost of a long interval.
   - Optionally set `settings.kubernetes.log-level=4` (rendered as `-v` at `kits/bottlerocket-core-kit/packages/kubernetes-1.37/kubelet-exec-start-conf`). kubelet then logs `Starting container log rotation sequence` once per interval (1.37:clm.go:197, 1.31:clm.go:238), so `journalctl -u kubelet -o short-precise | grep 'rotation sequence'` gives the exact period.
4. **Negative test.** `apiclient set --json '{"kubernetes":{"container-log-monitor-interval":"2s"}}'`. The journal shows `containerLogMonitorInterval must be a positive time duration greater than or equal to 3s` and kubelet crash-loops. Recover with `"10s"`.

Upstream test: `test/e2e_node/container_log_rotation_test.go` "ContainerLogRotationWithMultipleWorkers" sets 3s (1.37:41, 1.37:121). It does not measure the period.

Time: about 5 minutes.

### Findings
- **[bug] Intervals under 3s are accepted, and kubelet refuses to start (1.31-1.37).**
  - Input: `settings.kubernetes.container-log-monitor-interval = "1s"` (also `"0s"`, `"2500ms"`).
  - kc-1.37:179-181 renders `containerLogMonitorInterval: 1s`.
  - 1.37:validation.go:410-412 rejects it, which is fatal at 1.37:cmd/kubelet/app/server.go:265-267.
  - Fix: add a duration modeled type that parses to nanoseconds and enforces `>= 3s`, or a method on `KubernetesDurationValue` that a per-field wrapper can use. Document the minimum.
- **[risk] Overflowing durations are accepted, and kubelet fails at decode (all versions; also affects every other `KubernetesDurationValue` setting).**
  - Input: `"2562048h"`. Go gives `time: invalid duration`, so `failed to decode` and kubelet exits.
  - Likelihood is low.
  - Fix: in `KubernetesDurationValue::try_from` (`mt/kubernetes.rs:869-886`), sum the components with checked arithmetic and reject anything above `i64::MAX` ns.

---

## settings.kubernetes.image-minimum-gc-age

### Upstream per version
| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `imageMinimumGCAge` `metav1.Duration` (1.31:types.go:298); flag `--minimum-image-ttl-duration` (1.31:cmd/kubelet/app/options/options.go:437) | 2m, applied when the value is 0 (1.31:defaults.go:135-136) | no negative check; max/min relation (1.31:validation.go:92-94) | none | `MinAge` 1.31:pkg/kubelet/kubelet.go:437; used only by space-based GC (1.31:gcm.go:462) |
| 1.32 | yes | same (1.32:types.go:298) | 2m (1.32:defaults.go:153) | relation (1.32:validation.go:98) | none | 1.32:pkg/kubelet/kubelet.go:475 |
| 1.33 | yes | same (1.33:types.go:339) | 2m (1.33:defaults.go:153) | relation (1.33:validation.go:99) | none | 1.33:gcm.go:487 |
| 1.34 | yes | same (1.34:types.go:340) | 2m (1.34:defaults.go:153) | relation (1.34:validation.go:99) | none | 1.34:pkg/kubelet/kubelet.go:504 |
| 1.35 | yes | same (1.35:types.go:340) | 2m (1.35:defaults.go:153) | relation (1.35:validation.go:102) | none | 1.35:gcm.go:500 |
| 1.36 | yes | same (1.36:types.go:364; doc adds "If unset or 0, defaults to 2m", 1.36:types.go:360-361) | 2m (1.36:defaults.go:154) | adds `< 0` rejected (1.36:validation.go:99-101); relation (1.36:validation.go:105) | none | 1.36:pkg/kubelet/kubelet.go:513 |
| 1.37 | yes | same (1.37:types.go:364) | 2m (1.37:defaults.go:152) | `< 0` rejected (1.37:validation.go:127-129); relation (1.37:validation.go:133-135) | none | 1.37:pkg/kubelet/kubelet.go:540; 1.37:gcm.go:500-503 |

`MinAge` only gates space-based GC, through `freeSpace`, which skips images whose `firstDetected` is younger than `MinAge` (1.37:gcm.go:500). Age-based GC (`freeOldImages`, 1.37:gcm.go:426-456) ignores it.

### What changes between versions
- 1.36 adds an explicit negative-value rejection (1.36:validation.go:99-101; 1.37:validation.go:127-129) and documents that 0 maps to 2m (1.36:types.go:360-361). This does not affect Bottlerocket, because the regex has no sign.
- The `kubelet_image_garbage_collected_total{reason}` counter is defined in 1.31 (1.31:pkg/kubelet/metrics/metrics.go:879) but never registered: there is no `MustRegister(ImageGarbageCollectedTotal)` in 1.31. It is registered from 1.32 (1.32:pkg/kubelet/metrics/metrics.go:1026; 1.37:pkg/kubelet/metrics/metrics.go:1458). This only matters for verification on 1.31.

### Bottlerocket implementation
- **Model:** `image_minimum_gc_age: KubernetesDurationValue` (`lib.rs:80`).
  - **Bottlerocket accepts, kubelet rejects:** overflow values (decode error); values `>=` a set `image-maximum-gc-age` (see the next section).
  - **kubelet accepts, Bottlerocket rejects:** only non-canonical forms.
  - **Semantic trap:** `"0s"` is accepted but becomes 2m in kubelet (defaults.go `== zeroDuration`), not "no minimum". To get a near-zero minimum, use `"1s"`.
- **Templates:** rendered in every version as `{{#if settings.kubernetes.image-minimum-gc-age}}imageMinimumGCAge: {{...}}{{/if}}`:

  | version | lines |
  |---|---|
  | 1.31 | kc-1.31:212-214 |
  | 1.32 | kc-1.32:219-221 |
  | 1.33 | kc-1.33:222-224 |
  | 1.34 | kc-1.34:220-222 |
  | 1.35 | kc-1.35:229-231 |
  | 1.36 | kc-1.36:217-219 |
  | 1.37 | kc-1.37:223-225 |

  - Unquoted YAML string.
  - `"0s"` is rendered, which is harmless because kubelet defaults it to 2m.
  - Bottlerocket passes no `--minimum-image-ttl-duration` flag (`kubelet-exec-start-conf`), so the config value is authoritative.
  - No gate. Rendered in every supported version.
- **Migration:** present. `bottlerocket/sources/settings-migrations/v1.51.0/kubernetes-additional-settings/src/main.rs:9-15`, listed in `bottlerocket/Release.toml:449-453` and `bottlerocket/sources/Cargo.toml:66` (bottlerocket #4690).
- **Docs:** present at `website/repo/data/settings/1.51.x/kubernetes.toml:1-5`. They do not mention that 0 means 2m, and do not mention the interaction with `image-maximum-gc-age`.

### How to verify it works on a node
`MinAge` only matters for threshold-driven GC, so force that path on two disposable nodes.

- Settings for both nodes: `image-gc-high-threshold-percent: 1`, `image-gc-low-threshold-percent: 0`.
  - Both are rendered with `includeZero=true` (kc-1.37:130-135).
  - kubelet validation allows `low < high`.
- A: `image-minimum-gc-age: "1m"`. B: `"30m"`.

```
apiclient set --json '{"kubernetes":{"image-gc-high-threshold-percent":1,"image-gc-low-threshold-percent":0,"image-minimum-gc-age":"1m"}}'   # A ("30m" on B)
kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig | {imageMinimumGCAge,imageMaximumGCAge,imageGCHighThresholdPercent,imageGCLowThresholdPercent}'
#   A: "1m0s", B: "30m0s"; unset would show "2m0s"
kubectl run gcprobe --image=public.ecr.aws/docker/library/alpine:3.20 --restart=Never --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" -- true
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/gcprobe --timeout=2m && kubectl delete pod gcprobe
# on the node (sheltie):
while sleep 30; do date +%T; ctr -n k8s.io images ls -q | grep -c alpine; journalctl -u kubelet --since -40s --no-pager | grep -E 'over the high threshold|Removing image to free bytes'; done
# 1.32+ only:
kubectl get --raw /api/v1/nodes/$NODE/proxy/metrics | grep '^kubelet_image_garbage_collected_total'
```

Expected:

- **Cadence.** GC runs every 5 minutes (`ImageGCPeriod`, 1.37:pkg/kubelet/kubelet.go:231) and logs `Disk usage on image filesystem is over the high threshold` on every tick (1.37:gcm.go:395, 1.31:gcm.go:384).
- **Node A** removes alpine on the first tick that is at least 1m after the image was first detected. Expect it within about 10 minutes, with a `Removing image to free bytes` log line (1.37:gcm.go:529) and `reason="space"` incremented (1.32+).
- **Node B** keeps alpine until 30m. With `log-level` 5 it logs `Image ID's age is less than the policy's minAge` (1.37:gcm.go:502, 1.31:gcm.go:463).
- **Pause image.** `localhost/kubernetes/pause:0.1.0` survives on both nodes:
  - it is labeled `io.cri-containerd.pinned=pinned` (`kits/bottlerocket-core-kit/packages/kubernetes-1.37/prestart-load-pause-ctr.conf`);
  - the label key exists in containerd 1.7, 2.2 and 2.3 (`pkg/cri/labels/labels.go:31` and `internal/cri/labels/labels.go:31/47`);
  - kubelet skips pinned images (1.37:gcm.go:569).
- **Expected noise.** Because a 0% low threshold is unreachable, expect `FreeDiskSpaceFailed` warning events (1.37:gcm.go:403-412). This is harmless on a disposable node.

Time: about 10-12 minutes.

Upstream test: `test/e2e_node/image_gc_test.go` only sets `ImageMinimumGCAge=1s` alongside max age (1.37:57-58). There is no dedicated min-age test.

### Findings
- **[nit] `"0s"` silently means 2m.** Input `image-minimum-gc-age = "0s"` is rendered as `imageMinimumGCAge: 0s`, which kubelet defaults to 2m (1.37:defaults.go:152-153). A user who then sets `image-maximum-gc-age = "1m"` gets a fatal validation error (see next section). Fix: document it, and suggest `"1s"` for "effectively none".
- **[nit] Docs** (`1.51.x/kubernetes.toml:1-5`) do not say that min must stay below max when max is set.

---

## settings.kubernetes.image-maximum-gc-age

### Upstream per version
| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `imageMaximumGCAge` `metav1.Duration` (1.31:types.go:304), no flag | `0s` (disabled); no defaulter (types.go doc) | `!=0` without the gate rejected (1.31:validation.go:86-88); `<0` rejected (89-91); `0 < max <= min` rejected (92-94) | ImageMaximumGCAge Beta, default on (1.31:pkg/features/kube_features.go:1088) | gated use 1.31:pkg/kubelet/kubelet.go:442-446; age GC 1.31:gcm.go:400-415 |
| 1.32 | yes | same (1.32:types.go:304) | 0s | same (1.32:validation.go:92-100) | Beta/on (1.32:pkg/features/versioned_kube_features.go:400-403) | 1.32:pkg/kubelet/kubelet.go:480-484 |
| 1.33 | yes | same (1.33:types.go:345) | 0s | same (1.33:validation.go:93-101) | Beta/on (1.33:pkg/features/kube_features.go:1375-1378) | 1.33:pkg/kubelet/kubelet.go:514-518 |
| 1.34 | yes | same (1.34:types.go:346) | 0s | same (1.34:validation.go:93-101) | Beta/on (1.34:pkg/features/kube_features.go:1323-1326) | 1.34:pkg/kubelet/kubelet.go:509-513 |
| 1.35 | yes | same (1.35:types.go:346) | 0s | same (1.35:validation.go:96-104) | GA, locked on, "remove in 1.38" (1.35:pkg/features/kube_features.go:1360-1364) | unconditional `imageGCPolicy.MaxAge =` 1.35:pkg/kubelet/kubelet.go:516; 1.35:gcm.go:426-442 |
| 1.36 | yes | same (1.36:types.go:370) | 0s | same (1.36:validation.go:96-107) | GA/locked (1.36:pkg/features/kube_features.go:1512-1516) | 1.36:pkg/kubelet/kubelet.go:518 |
| 1.37 | yes | same (1.37:types.go:370) | 0s | gate check (1.37:validation.go:102-104); `<0` (130-132); relation (133-135) | GA/locked (1.37:pkg/features/kube_features.go:1676-1680) | 1.37:pkg/kubelet/kubelet.go:545; 1.37:gcm.go:426-456 |

Runtime behavior, the same in every version:

- `freeOldImages` does nothing until kubelet uptime exceeds `MaxAge` (`freeTime.Sub(beganGC) <= MaxAge`, 1.37:gcm.go:431-435; 1.31:gcm.go:407).
- It then deletes unused, unpinned images whose `lastUsed` is older than `MaxAge` (1.37:gcm.go:442; 1.31:gcm.go:415).
- It does not consult `MinAge`.
- It runs on the 5-minute GC loop (1.37:pkg/kubelet/kubelet.go:1746-1766).
- `lastUsed` and `beganGC` live in memory, so every kubelet restart restarts the clock.

### What changes between versions
- **Gate maturity.** Beta and default-on in 1.31-1.34; GA and locked in 1.35-1.37 (citations above), with removal planned for 1.38.
  - 1.31-1.34 read the gate at kubelet startup (1.31:pkg/kubelet/kubelet.go:442-446). 1.35+ use the field unconditionally (1.35:pkg/kubelet/kubelet.go:516).
  - The GC-stub condition also drops the gate term: 1.31:pkg/kubelet/kubelet.go:1463-1464 versus 1.35:pkg/kubelet/kubelet.go:1647.
  - Because Bottlerocket never sets this gate, behavior is identical across versions.
- **Upstream test labels.** The 1.31-1.34 e2e test enables the gate explicitly and is labeled NodeFeature GarbageCollect (1.31:test/e2e_node/image_gc_test.go:44-62). In 1.35+ it is NodeConformance (1.35:test/e2e_node/image_gc_test.go:43).
- **Metric.** `kubelet_image_garbage_collected_total` is not exposed on 1.31 (see the previous section).

### Bottlerocket implementation
- **Model:** `image_maximum_gc_age: KubernetesDurationValue` (`lib.rs:81`).
  - **Bottlerocket accepts, kubelet rejects (all versions):**
    - any `0 < max <= effective min`, where min is the user value or 2m when unset or `0s`;
    - overflow values.
  - **kubelet accepts, Bottlerocket rejects:** the bare `0` that the docs suggest. The regex needs a unit, and a TOML/JSON integer is a type error. `"0s"` works.
- **Templates:** rendered in every version as `{{#if settings.kubernetes.image-maximum-gc-age}}imageMaximumGCAge: {{...}}{{/if}}`:

  | version | lines |
  |---|---|
  | 1.31 | kc-1.31:215-217 |
  | 1.32 | kc-1.32:222-224 |
  | 1.33 | kc-1.33:225-227 |
  | 1.34 | kc-1.34:223-225 |
  | 1.35 | kc-1.35:232-234 |
  | 1.36 | kc-1.36:220-222 |
  | 1.37 | kc-1.37:226-228 |

  - `"0s"` is rendered, kubelet reads it as 0, and age GC is disabled. This is the correct reset path, given there is no unset.
  - **Feature gates.** None of kc-1.31..1.37 render `ImageMaximumGCAge` (`featureGates` holds only `DynamicResourceAllocation` and `MutableCSINodeAllocatableCount` from 1.33/1.34). The Beta default-on gate covers 1.31-1.34, and nothing will break when 1.38 removes the gate.
  - **History.** The core-kit commit that added this template (`1aa8ab300`) also added `featureGates: ImageMaximumGCAge: true` to the 1.29 template. That version is gone.
  - Rendered in every version that supports it, never where gated off.
- **Migration:** present (v1.51.0, `main.rs:12`; `Release.toml:449-453`).
- **Docs:** present at `website/repo/data/settings/1.51.x/kubernetes.toml:7-11`. Problems:
  - "Set to 0 to disable" is wrong for Bottlerocket input; it should say `"0s"`.
  - The max > min rule is missing, as is the fact that min defaults to 2m.

### How to verify it works on a node
Set both values in one transaction. Setting max `1m` alone fails, because min defaults to 2m.

```
apiclient set --json '{"kubernetes":{"image-minimum-gc-age":"10s","image-maximum-gc-age":"1m"}}'    # B; this restarts kubelet (t0)
kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig | {imageMinimumGCAge,imageMaximumGCAge}'
#   B: {"10s","1m0s"}; A (unset): {"2m0s","0s"}
kubectl run gcprobe --image=public.ecr.aws/docker/library/alpine:3.20 --restart=Never --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" -- true
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/gcprobe --timeout=2m && kubectl delete pod gcprobe
# sheltie:
while sleep 30; do date +%T; ctr -n k8s.io images ls -q | grep -c alpine; done
journalctl -u kubelet -f | grep 'Removing image to free bytes'
# 1.32+:
kubectl get --raw /api/v1/nodes/$NODE/proxy/metrics | grep 'kubelet_image_garbage_collected_total{reason="age"}'
```

Expected (all versions):

- **Why the pod must be deleted.** An exited container still counts as using its image, because `GetPods(ctx, true)` includes exited containers (1.37:gcm.go:244-262).
- **Node B** removes alpine on the first 5-minute GC tick where kubelet uptime is over 1m and the image has been unused for over 1m. That is about t0+5m, or t0+10m if the pod spanned a tick.
  - Logs show `Removing image to free bytes`.
  - On 1.32+ `reason="age"` increments. 1.31 does not expose the metric, so rely on `ctr` and the journal there.
- **Node A** keeps alpine while disk usage stays below 85%.
- **Pause image** stays on both nodes (pinned, see previous section).

Negative test:

- On a node with min unset, run `apiclient set --json '{"kubernetes":{"image-maximum-gc-age":"1m"}}'`.
- The journal shows `invalid configuration: imageMaximumGCAge 1m0s must be greater than imageMinimumGCAge 2m0s` and kubelet crash-loops.
- Recover with `"0s"` or `"3m"`.

Upstream test: `test/e2e_node/image_gc_test.go` "when ImageMaximumGCAge is set" uses max 1m / min 1s and polls for up to 6 minutes (1.37:36-41, 55-110).

Time: about 6-11 minutes.

### Findings
- **[bug] `image-maximum-gc-age` at or below the effective minimum is accepted, and kubelet refuses to start (1.31-1.37).**
  - Inputs:
    - `image-maximum-gc-age = "1m"` (or `"2m"`) with min unset or `"0s"`;
    - any max at or below an explicitly set min, such as min `"1h"` with max `"30m"`.
  - kc-1.37:226-228 renders it.
  - The defaulter turns min 0 into 2m (1.37:defaults.go:152-153), then 1.37:validation.go:133-135 rejects with `imageMaximumGCAge 1m0s must be greater than imageMinimumGCAge 2m0s`, which is fatal at 1.37:cmd/kubelet/app/server.go:265-267. Same rule at 1.31:validation.go:92-94.
  - It is also easy to trigger by changing the two keys in separate `apiclient set` calls, because the intermediate state is invalid.
  - Fix:
    - Document the constraint and the 2m default, and tell users to change both keys in one `apiclient set --json`.
    - A per-field type cannot express this rule. The model's `validate` hook is a no-op (`lib.rs:136-138`), and the apiserver deserializes partial input straight into the model (`kits/bottlerocket-core-kit/sources/api/apiserver/src/server/controller.rs:413`). A real check would need merged-settings validation; how to wire that is inferred, not designed here.
- **[nit] Docs say "Set to 0 to disable".** Bottlerocket rejects `0` (`mt/kubernetes.rs` test `bad_names` includes `"100"`); only `"0s"` works. Fix the wording in `1.51.x/kubernetes.toml:8`.
- **[nit] kubelet restarts reset the age clock.** Age GC never fires until kubelet uptime exceeds `MaxAge` (1.37:gcm.go:431-435), and every Bottlerocket settings change that touches kubelet restarts it. With a large value such as `24h` and frequent `apiclient set`, age GC may never run. Worth a sentence in the docs.

---

## settings.kubernetes.max-parallel-image-pulls

### Upstream per version
| version | exists | JSON path / flag, Go type | upstream default | validation | gate: maturity/default | notes |
|---|---|---|---|---|---|---|
| 1.31 | yes | `maxParallelImagePulls` `*int32` (1.31:types.go:501), no flag; related `serializeImagePulls` `*bool` (1.31:types.go:495), flag `--serialize-image-pulls` (1.31:cmd/kubelet/app/options/options.go:485) | nil (no limit). `serializeImagePulls` defaults to true unless max >= 2 (1.31:defaults.go:208-217) | `< 1` rejected (1.31:validation.go:134-136); `serialize && max > 1` rejected (1.31:validation.go:137-139) | none | puller choice 1.31:pkg/kubelet/images/image_manager.go:62-65; tokens 1.31:pkg/kubelet/images/puller.go:47-51 |
| 1.32 | yes | same (1.32:types.go:510; serialize 504) | same (1.32:defaults.go:226) | same (1.32:validation.go:140-145) | none | 1.32:pkg/kubelet/kubelet.go:728-729 |
| 1.33 | yes | same (1.33:types.go:548; serialize 542) | same (1.33:defaults.go:226) | same (1.33:validation.go:141-146) | none | 1.33:pkg/kubelet/images/image_manager.go:89 |
| 1.34 | yes | same (1.34:types.go:549; serialize 543) | same (1.34:defaults.go:226) | same (1.34:validation.go:141-146) | none | 1.34:pkg/kubelet/kubelet.go:778-779 |
| 1.35 | yes | same (1.35:types.go:549; serialize 543) | same (1.35:defaults.go:226) | same (1.35:validation.go:144-149) | none | 1.35:pkg/kubelet/images/image_manager.go:94 |
| 1.36 | yes | same (1.36:types.go:573; serialize 567) | same (1.36:defaults.go:227) | same (1.36:validation.go:147-152) | none | 1.36:pkg/kubelet/kubelet.go:788-789 |
| 1.37 | yes | same (1.37:types.go:573; serialize 567) | same (1.37:defaults.go:225) | same (1.37:validation.go:175-180) | none | 1.37:pkg/kubelet/images/image_manager.go:91-94; 1.37:pkg/kubelet/images/puller.go:48-53 |

Pull timing:

- The `Pulled` event message `Successfully pulled image %q in %v (%v including waiting)` measures the time spent waiting for a token separately from the actual pull (1.31:pkg/kubelet/images/image_manager.go:167; 1.37:pkg/kubelet/images/image_manager.go:381-382).
- Pull events go only to the event recorder, not the kubelet journal, when there is an object ref (1.37:pkg/kubelet/images/image_manager.go:139-143).
- `registryPullQPS` 5 / `registryBurst` 10 still apply (1.37:defaults.go:109-113), and calls over the limit fail with `pull QPS exceeded` (1.37:pkg/kubelet/images/helpers.go:47-52).

### What changes between versions
- No validation or default changes.
- 1.37 moves the goroutine from inside `parallelImagePuller.pullImage` (`go func()`, 1.31-1.36, for example 1.31:pkg/kubelet/images/puller.go:55) to the caller (`go m.puller.pullImage`, 1.37:pkg/kubelet/images/image_manager.go:366). The limit behaves the same.
- The upstream e2e test `test/e2e_node/image_pull_test.go` exists from 1.32 onward (1.32:50-56, 131-136), not in 1.31.

### Bottlerocket implementation
- **Model:** `max_parallel_image_pulls: i32` (`lib.rs:107`), no validation.
  - **Bottlerocket accepts, kubelet rejects:** negative values. They are truthy, so they are rendered and fail `must be a positive number`.
  - **`0` is accepted and skipped by the template.** kubelet then sees nil, and with `serializeImagePulls: false` that means no limit (1.37:pkg/kubelet/images/puller.go:48-50). Upstream would reject an explicit 0, so the model and kubelet disagree on 0, but the result does not break the node.
  - **kubelet accepts, Bottlerocket rejects:** nothing.
- **What Bottlerocket renders for `serializeImagePulls`:** a hard-coded `serializeImagePulls: false` in every template, independent of any setting. It has been there since the original kubelet template (core-kit history `dc8867795`).

  | version | line |
  |---|---|
  | 1.31 | kc-1.31:145 |
  | 1.32 | kc-1.32:149 |
  | 1.33 | kc-1.33:152 |
  | 1.34 | kc-1.34:150 |
  | 1.35 | kc-1.35:158 |
  | 1.36 | kc-1.36:146 |
  | 1.37 | kc-1.37:146 |

  Consequences:
  - The `serialize && max > 1` rejection (for example 1.37:validation.go:178-180) can never trigger, so `max-parallel-image-pulls >= 2` is always valid.
  - When the setting is unset, Bottlerocket pulls with no limit, unlike upstream's serial default.
  - `max-parallel-image-pulls = 1` is the only way to serialize pulls. It uses the parallel puller with one token, not the serial puller.
- **Templates:** rendered in every version as `{{#if settings.kubernetes.max-parallel-image-pulls}}maxParallelImagePulls: {{...}}{{/if}}`:

  | version | lines |
  |---|---|
  | 1.31 | kc-1.31:218-220 |
  | 1.32 | kc-1.32:225-227 |
  | 1.33 | kc-1.33:232-234 |
  | 1.34 | kc-1.34:230-232 |
  | 1.35 | kc-1.35:239-241 |
  | 1.36 | kc-1.36:227-229 |
  | 1.37 | kc-1.37:233-235 |

  - Unquoted YAML int.
  - `0` is skipped. That is the right call, because rendering 0 would be fatal, and because it gives users a way back to "no limit" since there is no unset.
  - No gate. Rendered in every supported version.
- **Migration:** present (v1.51.0, `main.rs:13`).
- **Docs:** present at `website/repo/data/settings/1.51.x/kubernetes.toml:13-17`. They do not state that Bottlerocket's default is no limit (because of `serializeImagePulls: false`), that the minimum is 1, or how 0 behaves.

### How to verify it works on a node
- B: `apiclient set --json '{"kubernetes":{"max-parallel-image-pulls":1}}'`. A: unset.
- **configz:** `kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq '.kubeletconfig | {serializeImagePulls,maxParallelImagePulls}'`.
  - B: `{false, 1}`.
  - A: `{false, null}`. The field is omitted when nil (`omitempty`).
  - Same in all versions.
- **Workload:** create 5 pods at once, each with a different image that is not cached. Five is below `registryBurst` 10, and the images must be in separate pods because one pod pulls its containers sequentially.

  ```
  for img in python:3.12-slim node:22-slim ruby:3.3-slim perl:5.40-slim golang:1.23-alpine; do
    n=pp-$(echo "$img" | tr ':.' '--')
    kubectl run "$n" --image=public.ecr.aws/docker/library/$img --restart=Never --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" -- sleep 600 &
  done; wait; sleep 120
  kubectl get events --field-selector reason=Pulled -o jsonpath='{range .items[*]}{.involvedObject.name}{"\t"}{.message}{"\n"}{end}' | grep '^pp-'
  # node side (sheltie): containerd logs CRI PullImage start/end at info (containerd-1.7.36 pkg/cri/instrument/instrumented_service.go:983-989; 2.2.10/2.3.7 internal/cri/instrument/instrumented_service.go:354-360)
  journalctl -u containerd --since -10min --no-pager | grep 'msg="PullImage ' | awk '/returns image reference|failed/{c--;next}{c++; if(c>m)m=c} END{print "max in-flight PullImage:", m}'
  ```

- **Expected results:**
  - B: every pull after the first shows `(Ys including waiting)` with Y/X > 1.5, the upstream "delayed pull" heuristic (1.37:test/e2e_node/image_pull_test.go:111-115, 203-213). Max in-flight is 1.
  - A: Y is roughly X for every pull, and max in-flight is 5.
  - The containerd log-line format under journald is inferred.
  - containerd's own `max_concurrent_downloads` limits layers per pull, not the number of CRI calls, so it does not change the in-flight count.
- **Negative test.** `apiclient set --json '{"kubernetes":{"max-parallel-image-pulls":-1}}'`. The journal shows `invalid configuration: maxParallelImagePulls -1 must be a positive number` and kubelet crash-loops. `0` instead leaves configz with `maxParallelImagePulls` null, which is no limit.
- **Upstream test.** `test/e2e_node/image_pull_test.go` "parallel image pull with MaxParallelImagePulls=5" and "serialize image pull" (1.32+, CRI proxy based). Bottlerocket cannot reproduce the second case's `SerializeImagePulls=true`; `max=1` is the closest equivalent.

Time: about 5 minutes plus image download time.

### Findings
- **[bug] Negative values are accepted and rendered, and kubelet refuses to start (1.31-1.37).**
  - Input: `settings.kubernetes.max-parallel-image-pulls = -1`.
  - kc-1.37:233-235 renders `maxParallelImagePulls: -1`, because negative numbers are truthy under handlebars `is_normal`.
  - 1.37:validation.go:175-177 rejects it, which is fatal at 1.37:cmd/kubelet/app/server.go:265-267. Same at 1.31:validation.go:134-136.
  - Fix: a non-negative or positive model type. If 0 stays allowed, document it as "no limit".
- **[nit] `0` silently means "no limit".** This differs from upstream, where 0 is invalid. It is undocumented, but it is the only way to reset after setting a value. Document it, or reject 0 and document an alternative.
- **[nit] Docs omit Bottlerocket's default.** Pulls are unlimited by default because `serializeImagePulls: false` is hard-coded (kc-1.31:145 ... kc-1.37:146). Add this to `1.51.x/kubernetes.toml:14`.
- **Not a bug:** `max-parallel-image-pulls` cannot produce the `serializeImagePulls` conflict error in any version, because serialization is always rendered false.

---

## Script feedback

All commands were run from the grove root with `T=/home/fedora/Repositories/bottlerocket-forest/skills/add-kubernetes-setting/scripts`.

1. **`python3 -I $T/k8s-field-report.py field maxParallelImagePulls`** (and `field serializeImagePulls`) prints `gate RotateKubeletServerCertificate: Beta default=true` for every version.
   - That gate only appears in the line after the validation block (`if kc.ServerTLSBootstrap && !localFeatureGate.Enabled(features.RotateKubeletServerCertificate)`), so it is attributed to the wrong field.
   - Only report gates that appear inside the matched statement for the field, or label context-window gates "nearby (unrelated?)".
2. **`... field imageMinimumGCAge` / `field imageMaximumGCAge`: the "Changes between consecutive versions" section reports false changes.**
   - Example: the 1.36 -> 1.37 diff shows `- if kc.ImageMinimumGCAge.Duration < 0 {` / `+ if len(kc.DefaultPodSysctls) > 0 {`. That is only a shift in the trailing context lines; the rule did not change.
   - Diff only the matched statements, not the surrounding context.
3. **`... field imageMaximumGCAge` prints no "default @" line,** with nothing to say why. It should state "no defaulter: zero value (0s) means disabled".
   - For `maxParallelImagePulls`, "default @" points at the `SerializeImagePulls` defaulter (which is relevant). It should be labeled as a cross-field default and should say the field itself defaults to nil.
4. **`python3 -I $T/k8s-field-report.py gate ImageMaximumGCAge` prints maturity history without a `path:line`.** The citation had to be found with grep: `kube_features.go` for 1.31, `versioned_kube_features.go` for 1.32, then `kube_features.go` again for 1.33+. Print the spec location.
5. **`python3 -I $T/kubelet-config-lint.py` reports "no issues" for all 7 versions.** It only checks that paths exist and that gates are defined. It misses every finding in this report. Useful additions:
   - Flag `includeZero=true` (or a plain `{{#if}}` on a signed int) when kubelet validation rejects `< 1`.
   - Flag model types that are looser than kubelet validation, such as `i32` against `>= 1`, or `KubernetesDurationValue` against `>= 3s`.
   - Evaluate cross-field rules against constants the template hard-codes, such as `serializeImagePulls: false` against the max/serialize rule, or a rendered max against the default 2m min.
6. **`python3 -I $T/template-drift.py kubernetes --matrix` shows only whether a key is present per version, not the guard helper** (`if` / `if includeZero=true` / `if_not_null` / `default`). A version with a different guard would not be caught. I confirmed by grep that this group's guards are identical in 1.31-1.37. Add a guard column, or diff the rendering block per key.
7. **`k8s-field-report.py field` "e2e_node tests mentioning it" lists files by name only.** For example, `container_log_rotation_test.go` for `containerLogMaxWorkers` never asserts the worker count. Print the matching line or `It(...)` title so readers can judge what the test covers.
8. **Missing check worth adding: metrics.** `field` could note when the metric the consumer increments is not registered. `kubelet_image_garbage_collected_total` is defined but not registered in 1.31, which broke an obvious verification path.
