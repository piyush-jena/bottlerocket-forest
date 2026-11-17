# Code patterns

**Keywords:** modeled type, Scalar, Validate, KubernetesSettingsV1, handlebars guard, if_not_null, includeZero, schnauzer test, AddSettingsMigration, differential test

Snippets are from merged PRs or the pilot (bottlerocket#4979, `max-container-restart-period`).

## settings-sdk

### Pick a type

| Kubelet type | Bottlerocket type | Watch out for |
|---|---|---|
| `*bool` | `bool` | none |
| `int32`, `*int32` with bounds | a bounded type, or `bounded_integer` | plain `i32` accepts negatives and zero that kubelet rejects |
| `metav1.Duration` | `KubernetesDurationValue`, or a bounded duration type | the regex accepts `0s` and huge values; add bounds when kubelet has them |
| `map[string]string` of quantities | `HashMap<KubernetesReservedResourceKey, KubernetesQuantityValue>` | the quantity regex accepts `1K` and `-1`, which kubelet rejects |
| enum string | `enum` with `Scalar` and `#[serde(rename = ...)]` | add aliases only if the canonical form is what renders |
| `float64` | `f64` newtype with `Validate` (`KubernetesMemoryThrottlingFactor`) | reject NaN and infinities |

### Bounded type with Scalar and Validate

```rust
/// KubernetesMaxContainerRestartPeriod is the kubelet's crashLoopBackOff.maxContainerRestartPeriod,
/// a Kubernetes duration that the kubelet requires to be between 1 second and 300 seconds.
#[derive(Debug, Clone, Eq, PartialEq, Scalar)]
pub struct KubernetesMaxContainerRestartPeriod {
    inner: String,
}

impl Validate for KubernetesMaxContainerRestartPeriod {
    fn validate<S: Into<String>>(input: S) -> Result<Self, ValidationError> {
        let input = input.into();
        let millis = kubernetes_duration_millis(&input).ok_or_else(|| {
            ValidationError::new(format!("'{input}' is not a valid Kubernetes duration"))
        })?;
        if (1_000..=300_000).contains(&millis) {
            Ok(Self { inner: input })
        } else {
            Err(ValidationError::new(format!(
                "max container restart period '{input}' must be between 1s and 300s"
            )))
        }
    }
}
```

Strings render through handlebars HTML escaping (`{{x}}` turns `&`, `<`, `>`, `"`, `'`, `=` and backtick into entities), so a string type must exclude those characters, or the template must use `{{{x}}}` and quote the value itself.

Do not derive `Hash` on a `Scalar` type: the derive implements `PartialEq` itself, and clippy rejects `Hash` with a manual `PartialEq` (`derived_hash_with_manual_eq`).
Mirror the kubelet's arithmetic exactly (here `Duration.Milliseconds()` truncation) and cite the upstream validation line in the doc comment.

### Field and tests on KubernetesSettingsV1

```rust
    container_runtime_endpoint: Url,
    max_container_restart_period: KubernetesMaxContainerRestartPeriod,
}
```

Add the field to `test_generate_kubernetes` (`max_container_restart_period: None,`) and three tests:

```rust
#[test]
fn test_max_container_restart_period_is_optional() {
    let settings: KubernetesSettingsV1 = serde_json::from_str("{}").unwrap();
    assert!(settings.max_container_restart_period.is_none());
    assert!(serde_json::to_value(settings).unwrap().get("max-container-restart-period").is_none());
}

#[test]
fn test_max_container_restart_period_round_trip() {
    for period in ["1s", "60s", "2m30s", "300s"] {
        let input = serde_json::json!({"max-container-restart-period": period});
        let settings: KubernetesSettingsV1 = serde_json::from_value(input.clone()).unwrap();
        assert_eq!(serde_json::to_value(settings).unwrap(), input);
    }
}

#[test]
fn test_max_container_restart_period_rejects_out_of_range() {
    for value in [json!("0s"), json!("999ms"), json!("301s"), json!("1h"), json!(60), json!("")] {
        let input = json!({"max-container-restart-period": value});
        assert!(serde_json::from_value::<KubernetesSettingsV1>(input).is_err());
    }
}
```

### Versions

Minor-bump every crate whose public API changed, then `settings-models`, and the workspace pins:
`modeled-types` 0.20.0 -> 0.21.0 (`bottlerocket-modeled-types = { ..., version = "0.21" }`), `settings-extensions/kubernetes` 0.11.0 -> 0.12.0, `settings-models` 0.33.0 -> 0.34.0.

### Differential test against upstream

Every value the model accepts must be accepted by every kubelet that renders it.
The default method uses kubelet's own code for every packaged version, so it also covers parsers that live in kubelet packages and change between versions:

```bash
printf '%s\n' '"1s"' '"300s"' '"0.5s"' '"301s"' '"1s1m"' 60 > values.txt
python3 -I $T/boundary-matrix.py --setting max-container-restart-period \
  --kubelet-path crashLoopBackOff.maxContainerRestartPeriod --values values.txt
```

```
value   model   1.31         1.32       ...  1.35   1.36   1.37
"1s"    accept  - [IGNORED]  - [FATAL]  ...  R OK   R OK   R OK
"1s1m"  reject  - [IGNORED]  - [FATAL]  ...  - [OK] - [OK] - [OK]   <- model stricter than kubelet: fine, document it
```

Put one value per case when kubelet stops at the first bad entry of a list.
For a quick check of a stdlib parser, a scratch Go program outside any download also works:

```go
// Mirrors 1.35 pkg/kubelet/apis/config/validation/validation.go (IsInRange(ms, 1000, 300000)).
package main

import ("fmt"; "os"; "time")

func main() {
	for _, in := range os.Args[1:] {
		d, err := time.ParseDuration(in)
		fmt.Printf("%q\t%v\n", in, err == nil && d.Milliseconds() >= 1000 && d.Milliseconds() <= 300000)
	}
}
```

`go run main.go "" 0s 999ms 0.9999s 1s 1.5s 300s 5m 5m1ms 1s1m 1.s` and compare with the Rust tests.
Inputs upstream accepts but the model rejects are fine if documented (`1s1m`, `1.s`); the reverse is a bug.
For quantities, use `resource.ParseQuantity` from the source's `staging/src/k8s.io/apimachinery` (or render and run `kubelet-validate.sh`, which runs kubelet's own parsing).

## core-kit templates

### Guards

| Want | Guard | Renders for |
|---|---|---|
| omit when unset; `false`/`0`/`""` mean "unset" upstream | `{{#if settings.kubernetes.x}}` | truthy values only (note: also drops subnormal floats) |
| omit only when unset; `false` is meaningful | `{{#if_not_null settings.kubernetes.x}}` | everything except null |
| omit when unset; `0` is meaningful | `{{#if settings.kubernetes.x includeZero=true}}` | numbers including 0 |
| tri-state (unset / true / false) | `if_not_null` around `#if ... else` | see `staticPodPath` in any `kubelet-config` |
| default when unset | `{{default 110 settings.kubernetes.max-pods}}` | always renders |

Handlebars `or` and `and` read only their first two arguments: nest them (`(or a (or b c))`).
`{{x}}` HTML-escapes strings; see "Pick a type".
Strict mode is on: a helper argument that is missing errors; `#if` on a missing key is fine.

### Cross-field guards

When kubelet only accepts field B together with a value of field A, render B only under that value, so no API input can stop the kubelet.
The `eq` must sit inside an `#if`, because strict mode errors on a missing helper argument:

```handlebars
{{#if settings.kubernetes.image-pull-credentials-verification-policy}}
imagePullCredentialsVerificationPolicy: {{settings.kubernetes.image-pull-credentials-verification-policy}}
{{#if (eq settings.kubernetes.image-pull-credentials-verification-policy "NeverVerifyAllowlistedImages")}}
{{#if settings.kubernetes.preloaded-images-verification-allowlist}}
preloadedImagesVerificationAllowlist:
{{#each settings.kubernetes.preloaded-images-verification-allowlist}}
- "{{this}}"
{{/each}}
{{/if}}
{{/if}}
{{/if}}
```

Document that B is ignored otherwise.

### Nested kubelet structs

Render the parent key only inside the guard, and merge into an existing parent if one is already rendered (`userNamespaces:`, `memorySwap:`).

```handlebars
{{#if settings.kubernetes.max-container-restart-period}}
crashLoopBackOff:
  maxContainerRestartPeriod: {{settings.kubernetes.max-container-restart-period}}
{{/if}}
```

### Per-version option lists

When option names have per-version maturity, list exactly the non-Alpha options per template:

```handlebars
{{#each settings.kubernetes.cpu-manager-policy-options}}
{{#if (or (eq this "full-pcpus-only") (or (eq this "strict-cpu-reservation") (eq this "distribute-cpus-across-numa")))}}
    {{this}}: "true"
{{/if}}
{{/each}}
```

### Render test (sources/api/schnauzer/tests/)

Needs `serde_yaml.workspace = true` in schnauzer's `[dev-dependencies]`.

```rust
use schnauzer::v2::import::{JsonSettingsResolver, StaticHelperResolver};
use serde_json::json;
use test_case::test_matrix;

struct Importer {
    settings_resolver: JsonSettingsResolver,
    helper_resolver: StaticHelperResolver,
}

schnauzer::impl_template_importer!(Importer, JsonSettingsResolver, StaticHelperResolver);

async fn render(version: u8, period: Option<&str>) -> serde_yaml::Value {
    let mut kubernetes = json!({
        "cluster-domain": "cluster.local", "server-tls-bootstrap": true, "max-pods": 29,
        "kube-reserved": {"cpu": "100m", "memory": "442Mi"}
    });
    if let Some(period) = period {
        kubernetes["max-container-restart-period"] = json!(period);
    }
    let importer = Importer {
        settings_resolver: JsonSettingsResolver::new(json!({"settings": {"kubernetes": kubernetes}})),
        helper_resolver: StaticHelperResolver,
    };
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join(format!("../../../packages/kubernetes-1.{version}/kubelet-config"));
    serde_yaml::from_str(&schnauzer::v2::render_template_file(&importer, path).await.unwrap()).unwrap()
}

// KubeletCrashLoopBackOffMax is Beta and on by default from Kubernetes 1.35.
#[test_matrix(35..=37, ["1s", "60s", "5m"])]
#[tokio::test]
async fn renders_on_versions_with_the_gate_on(version: u8, period: &str) {
    let config = render(version, Some(period)).await;
    let value = config.get("crashLoopBackOff").and_then(|c| c.get("maxContainerRestartPeriod"));
    assert_eq!(value.and_then(serde_yaml::Value::as_str), Some(period));
}

#[test_matrix(31..=34)]
#[tokio::test]
async fn never_rendered_where_the_gate_is_off(version: u8) {
    assert!(render(version, Some("60s")).await.get("crashLoopBackOff").is_none());
}
```

Also assert "absent when unset" for every version.
`test_matrix` takes literal lists and ranges; a `const` array does not compile.
Run it once with the template change stashed to see it fail.

## bottlerocket

### Migration crate

`sources/settings-migrations/v1.70.0/kubernetes-max-container-restart-period/Cargo.toml`:

```toml
[package]
name = "kubernetes-max-container-restart-period"
version = "0.1.0"
license = "Apache-2.0 OR MIT"
edition = "2021"
publish = false
exclude = ["README.md"]

[dependencies]
migration-helpers.workspace = true
```

`src/main.rs`:

```rust
use migration_helpers::common_migrations::AddSettingsMigration;
use migration_helpers::{migrate, Result};
use std::process;

/// We added a new setting for the kubelet's crashLoopBackOff.maxContainerRestartPeriod:
/// - settings.kubernetes.max-container-restart-period
fn run() -> Result<()> {
    migrate(AddSettingsMigration(&[
        "settings.kubernetes.max-container-restart-period",
    ]))
}

// Returning a Result from main makes it print a Debug representation of the error, but with Snafu
// we have nice Display representations of the error, so we wrap "main" (run) and print any error.
// https://github.com/shepmaster/snafu/issues/110
fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        process::exit(1);
    }
}
```

Use `AddPrefixesMigration(vec!["settings.kubernetes.<map-or-struct>"])` when the setting is a map or struct with keys below it.
Register the crate in `sources/Cargo.toml` `members` after the previous version's migrations, and list `migrate_v1.70.0_kubernetes-max-container-restart-period.lz4` in the `"(1.69.0, 1.70.0)"` edge of `Release.toml`.

### Version bump (only when Release.toml's version is already tagged)

```toml
# Release.toml
version = "1.70.0"
...
"(1.69.0, 1.70.0)" = [
]
```

and `release-version = "1.70.0"` in `Twoliter.toml`, in one commit `release: update Bottlerocket version to 1.70.0`.

## Dev-only overrides (DO NOT MERGE commits)

- `use-local-settings-sdk.py <repo>/sources <sdk-clone> <rev>` in core-kit and bottlerocket (the same rev in both).
- `Twoliter.override` in bottlerocket (gitignored) plus the resulting `Twoliter.lock` change:
  ```toml
  [bottlerocket.bottlerocket-core-kit]
  registry = "localhost:6642"
  ```
