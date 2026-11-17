# Spec: settings.kubernetes.<name>

**Requested by:** <issue link or user>
**Upstream target:** `KubeletConfiguration.<json.path>` | kubelet flag `--<flag>` | containerd `<table>.<key>`
**KEP / docs:** <links>

## What it does

One paragraph in user terms: what changes on the node when it is set, and why someone wants it.

## Upstream per packaged version

Fill from `k8s-field-report.py` and the opened source; one row per `kubernetes-1.X` package in core-kit.

| Version (gover) | Exists | Type | Default when unset | Validation | Gate: maturity/default | Behavior notes | Citations |
|---|---|---|---|---|---|---|---|
| 1.31 (1.31.14) | | | | | | | |
| ... | | | | | | | |

What changes between versions, in plain statements with citations:

-

## Decision per version

| Version | Render? | Why | Evidence |
|---|---|---|---|
| 1.31 | no | field absent | report |
| 1.32-1.34 | no | gate Alpha/off; kubelet rejects the field | `kubelet-validate.sh` counterfactual: FATAL "<message>" |
| 1.35-1.37 | yes | gate Beta/on | render tests; `kubelet-validate.sh` OK |

Versions that do not render it accept the setting and ignore it: the docs must say so.
In the evidence column, a forced-in field shows `FATAL` (kubelet rejects it, the reason to leave the version out) or `IGNORED` (the field does not exist there); `boundary-matrix.py` prints both.

## Related fields considered

Companion fields (an allowlist for a policy, a period for a feature switch), and whether each is exposed now, later, or never, with the reason.

## Model

- Name: `settings.kubernetes.<name>` (why this name; siblings it follows).
- Type: existing `<Type>` | new `<Type>` with rule `<rule>` (cite the upstream validation line).
- Accepted by Bottlerocket but rejected by some rendered kubelet: none (differential test inputs: ...).
- Accepted by kubelet but rejected by Bottlerocket (stricter, documented): ...
- Cross-field rules the model cannot enforce: ...

## Render

- Template file(s): `packages/kubernetes-1.X/kubelet-config` for X in ...
- Guard: `#if` | `if_not_null` | `includeZero=true`, because ...
- Rendered as:
  ```yaml
  ```
- Unset renders nothing, so nodes that do not set it are unchanged.

## Migration and docs

- Release version: current `Release.toml` is X (tagged? yes/no), so the migration goes in `v<Y>`.
- Migration: `AddSettingsMigration(&["settings.kubernetes.<name>"])` | `AddPrefixesMigration(...)`.
- Website: `data/settings/<Y>.x/kubernetes.toml` text.

## Verification plan

- Behavior test: <what, where, how long, expected A vs B>.
- Instance type: <type> (why).
- Nodes: A (Y, minor <newest>), B (Y, no setting), S (stock), O (minor <not rendered>).
- Boundary values for the offline matrix: <min>, <max>, <typical>; rejected: <...>.

## Open questions for the user

-
