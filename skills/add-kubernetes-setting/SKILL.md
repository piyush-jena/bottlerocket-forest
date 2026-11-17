---
name: add-kubernetes-setting
description: Add or fix a Bottlerocket settings.kubernetes.* setting (kubelet config field, kubelet flag, or containerd CRI option) across bottlerocket-settings-sdk, bottlerocket-core-kit and bottlerocket, deciding per Kubernetes version from the exact packaged source, checking renders with schnauzer and kubelet's own validation offline, and proving the behavior on EKS nodes. Also audits existing settings.
---

# Skill: Add a Kubernetes Setting

**Keywords:** kubernetes, kubelet, kubelet-config, settings, settings-sdk, settings-models, core-kit, schnauzer, migration, configz, feature-gate, per-version

Takes a Kubernetes knob (a `KubeletConfiguration` field, a kubelet flag, a containerd CRI option, a KEP, or a GitHub issue) and produces:

1. a setting spec with a per-version decision for every Kubernetes minor core-kit packages, backed by citations into that version's source;
2. the settings-sdk, core-kit, bottlerocket and docs changes, each tested;
3. evidence from real nodes that the kubelet received the value and that the feature works, plus evidence that nothing changed for nodes that do not set it;
4. PR descriptions, without pushing anything.

The same tools audit settings that already shipped: see "Auditing an existing setting".

## When to use

- A user asks for a new `settings.kubernetes.*` setting (for example an issue like bottlerocket#4979).
- A setting renders wrongly on some Kubernetes versions, or a new `kubernetes-1.X` package is being added (run Phase 2 checks across all versions).
- Reviewing a PR that adds or changes a Kubernetes setting.

## How it fits together (read first)

**Four repos, in release order.**
Each step waits for the previous one to be released:

| Repo | What changes | What it controls |
|---|---|---|
| bottlerocket-settings-sdk | field on `KubernetesSettingsV1`, modeled type, crate versions | what the Bottlerocket API accepts and how it normalizes values |
| bottlerocket-core-kit | `packages/kubernetes-1.X/kubelet-config` (or `kubelet-exec-start-conf`, `containerd-*/containerd-config-toml_*`), settings-models tag | what the kubelet or containerd receives, per Kubernetes minor |
| bottlerocket | settings-models tag, migration, `Release.toml`, version bump, core-kit version | whether the API accepts the key on a variant; downgrades removing it |
| bottlerocket-project-website | `data/settings/<release>.x/kubernetes.toml` | what users are told |

**The API gate is the variant's settings plugin.**
`bottlerocket/sources/settings-plugins/<variant>` compiles `KubernetesSettingsV1` from the settings-models tag pinned in `bottlerocket/sources/Cargo.toml`.
Templates can land in core-kit first; the setting becomes usable only when the bottlerocket repo bumps the tag.

**core-kit must know every key the bottlerocket repo accepts.**
pluto (core-kit) deserializes `settings.kubernetes` into `KubernetesSettingsV1` (`sources/api/pluto/src/api.rs:117-174`), and the model derive adds `deny_unknown_fields` (`bottlerocket-settings-models/model-derive/src/lib.rs:112`).
A key the bottlerocket model has but core-kit's model lacks breaks pluto, and with it boot, on aws-k8s variants.
So the settings-models tag in `bottlerocket/sources/Cargo.toml` must equal the one inside the core-kit pinned in `bottlerocket/Twoliter.lock`.
When Bottlerocket 1.49.0 rolled back to core-kit 10.6.0 over an unrelated regression in 10.7.0, bottlerocket#4660 had to revert #4650's models bump and migration with it; #4661 re-landed them with core-kit 10.7.1.

**The kubelet fails in two different ways.**
An unknown or misplaced key is decoded leniently and ignored with only a log warning (`pkg/kubelet/kubeletconfig/util/codec/codec.go`), so the setting silently does nothing (core-kit #1060: `idsPerPod` at the root for ten months).
A value that fails validation or startup parsing makes the kubelet exit, so the node never joins (most findings in `references/settings-catalog/`).
"The rendered file contains the line" proves neither.

**Behavior differs per Kubernetes version.**
There is one model for every variant but one template per Kubernetes minor.
For each packaged minor, the field may not exist, its default may differ, validation may differ, allowed values may change, and the feature gate it needs may be Alpha (off), Beta (on), or GA (locked).
Some fields exist but are rejected while their gate is off (`crashLoopBackOff.maxContainerRestartPeriod` before 1.35); some exist and are silently ignored while their gate is off (`memoryThrottlingFactor` before 1.37).
The per-version decision is the heart of this skill.
Versions that do not render a setting still accept it through the API and silently ignore it: say so in the docs.

## Tools

All scripts run from the grove root and read core-kit from `./kits/bottlerocket-core-kit`; set `CORE_KIT` when working in another clone.
Python scripts run with `python3 -I` (they never write bytecode into the skill directory).
Versions are always given as minors like `1.35`.
`T=~/Repositories/bottlerocket-forest/skills/add-kubernetes-setting/scripts`

| Script | Use it to |
|---|---|
| `fetch-package-source.sh [PKG...]` | unpack the exact upstream source (sha512-verified) each `kubernetes-1.X` or `containerd-*` package builds; cached |
| `k8s-field-report.py field\|flag\|gate\|containerd NAME [MINOR...]` | per version: JSON path, type, doc comment, defaults, validation, gates (from markers, conditions and enclosing blocks; maturity, default, `path:line`), functions in other packages that validation calls (with a body digest, so changes there show between versions), consumers, and what changes between versions |
| `render-template.sh --settings FILE --kubelet-config [MINOR...]` | render each `kubelet-config` with schnauzer itself (strict mode, real helpers) after passing settings through the model like the API does; then lint each render |
| `kubelet-config-lint.py [MINOR...] [--template FILE]` | every rendered YAML path exists in that version's types, `featureGates` are defined and not locked to another value, fields whose gate (marker or validation block) is off are not rendered; a fast first pass, not a substitute for `kubelet-validate.sh` |
| `kubelet-validate.sh RENDERED_DIR [MINOR...]` | run each kubelet version's own startup code on the rendered file, offline: strict decode, loader, gates, `ValidateKubeletConfiguration`, reserved and eviction parsing, CPU and topology policy options |
| `counterfactual.py RENDER_DIR OUT_DIR SNIPPET [MINOR...]` | copy renders with YAML merged in (a field forced into a version, or a gate turned on) for `kubelet-validate.sh` |
| `boundary-matrix.py --setting KEY --kubelet-path PATH --values FILE [--base FILE] [MINOR...]` | the differential test: per value, the model verdict and each kubelet's verdict, rendered or forced in; flags values the model accepts but a rendering kubelet rejects |
| `template-drift.py [kubernetes\|containerd] [--key PREFIX] [--matrix]` | keys that a newer version lost, keys rendered at different paths, and keys a variant template (NVIDIA) is missing |
| `use-local-settings-sdk.py SOURCES_DIR SDK_REPO [REV]` | point a repo at an unreleased local settings-sdk commit (dev only, DO NOT MERGE) |
| `verify-node.sh --instance ID --region R ...` | evidence from a node: API value, rendered file, live `/configz`, kubelet flags, other rendered files, kubelet config warnings; markdown output |

`kubelet-validate.sh` compiles hash-pinned Kubernetes source in the Bottlerocket SDK image with `--network=none` and the source mounted read-only; nothing from the sources runs on the host.
The first run per version compiles for about 30 seconds on a large machine (longer on small ones); later runs take under a second.

## Procedure

Keep notes and evidence in `planning/<setting>/` in the forest (gitignored).
Work on local branches in each repo; never push or open PRs without the user's go-ahead.

### Before you start: work from current upstream

The forest's bare repos (`.forest/bare/*.git`) only change when someone syncs them, and can be weeks behind GitHub.
Run `forester sync-seed` from the forest root, then `git fetch` in each grove member and branch from the fresh `origin/develop`.
If you cannot sync, check the facts that decide the work against GitHub directly: `gh api repos/bottlerocket-os/bottlerocket/contents/Release.toml?ref=develop`, `gh api repos/bottlerocket-os/bottlerocket/git/refs/tags/v<version>`, and the `packages/kubernetes-*` templates of `bottlerocket-core-kit` develop.
(The pilot run used a stale mirror: GitHub develop was already on an untagged 1.70.0, so its version-bump commit was unnecessary.)

### Phase 0: Research and spec (no code)

1. **Classify the target.**
   A `KubeletConfiguration` field renders in `kubelet-config`.
   A kubelet flag renders in `kubelet-exec-start-conf`, but every flag bound to a config field is deprecated (`AddKubeletConfigFlags`), so prefer the field.
   A containerd CRI option renders in every `containerd-*/containerd-config-toml_*k8s*` template, including the NVIDIA ones, and the TOML table differs between containerd 1.7 and 2.x (`references/settings-catalog/containerd.md`).
2. **Check it does not exist and is not in flight.**
   `grep -n <kebab-name> bottlerocket-settings-sdk/bottlerocket-settings-models/settings-extensions/kubernetes/src/lib.rs`, `grep -rn <kebab-name> kits/bottlerocket-core-kit/packages/kubernetes-1.*`, and for each of bottlerocket, bottlerocket-core-kit, bottlerocket-settings-sdk and bottlerocket-project-website: `gh search issues "<kubelet field>" --repo bottlerocket-os/<repo> --include-prs`.
3. **Read upstream, per packaged version.**
   ```bash
   python3 -I $T/k8s-field-report.py field <json.path>          # or: flag NAME, containerd KEY
   python3 -I $T/k8s-field-report.py gate <GateName>            # every gate the report names
   ```
   Then open the cited lines in each version's source (`fetch-package-source.sh` prints the paths).
   Follow `references/k8s-source-guide.md`: types, defaults (including conditional defaults), validation in `validation*.go`, startup parsing in `cmd/kubelet/app/server.go`, gates, the consuming code, and `test/e2e_node` for how upstream tests it.
   For behavior that may depend on version, compare the consuming code across versions, not just the field.
   When validation calls into another package (the report lists those calls with a body digest), a digest that changes between versions means that package's rules changed: diff it (`diff <(sed -n ... 1.35/...) <(... 1.36/...)`).
   Look at related fields too (a companion allowlist, a policy the field only applies under) and decide on them in the spec.
   Cross-check with the kubelet config reference and the KEP, but source wins.
4. **Decide per version.**
   For every packaged minor, one of:
   - **render**: field exists, any gate it needs is on by default, semantics are what the setting promises;
   - **do not render**: field absent, gate off (rejected or ignored), or semantics differ enough to mislead;
   - **render and enable a gate**: only with explicit user approval, because Bottlerocket would then ship a non-default gate (run the counterfactual with the gate on, so the user decides with evidence);
   - **render, with a documented upstream bug** on that version: decide with the user (`references/k8s-source-guide.md`, "Signals").
   Prove the "do not render" calls that rest on rejection with the counterfactual check in Phase 2.
5. **Design the model.**
   Name: kebab-case of the kubelet field, flattened like existing siblings (`memorySwap.swapBehavior` became `memory-swap-behavior`, `userNamespaces.idsPerPod` became `ids-per-pod`).
   Reuse an existing modeled type when its accepted set fits (`KubernetesDurationValue`, `KubernetesQuantityValue`, enums with `Scalar`), and add a bounded type otherwise.
   The model must never accept a value that any rendered version's kubelet rejects: most shipped bugs are exactly that (`references/settings-catalog/logs-images.md`, `eviction-reserved.md`, `pods-runtime.md`).
   Being stricter than upstream is fine (for example rejecting `1s1m`); document it.
   Cross-field rules cannot be expressed per field.
   When one field is only valid together with a value of another (an allowlist only with a policy that uses it), guard it in the template so no API value can stop the kubelet (`references/patterns.md`, "Cross-field guards").
   Rules the template cannot enforce (`imageMaximumGCAge` > `imageMinimumGCAge`) are checked in the Phase 2 matrix and documented.
   String values render through handlebars HTML escaping: the model must exclude `& < > " ' = ` and backticks unless the template uses `{{{ }}}` (`references/patterns.md`).
6. **Design the render.**
   Unset must render nothing, so nodes that do not opt in are unchanged (lesson of core-kit #747, where a new default broke `kubectl logs`).
   Choose the guard by what `false`, `0` and `""` mean upstream: `{{#if}}` drops them, `{{#if_not_null}}` keeps them, `{{#if x includeZero=true}}` keeps 0 (`references/patterns.md`).
   Nested kubelet structs must merge into an existing parent key rather than repeat it.
7. **Design the behavior test** (`references/verification.md`): what a pod or the node shows with the setting and without it, how long it takes, and which instance type is needed.
8. **Write the spec** from `references/spec-template.md` into `planning/<setting>/spec.md`.
9. **Gate: the user approves the spec.**
   Names and version scope are public API, and removing a setting later needs a migration.

### Phase 1: settings-sdk

1. Branch from the latest `bottlerocket-settings-models-v*` release in a normal clone (the dev override in Phase 5 needs a clone, not a worktree).
2. Add the modeled type if needed (`bottlerocket-settings-models/modeled-types/src/kubernetes.rs`) with good and bad value tests.
   **Differential-test the type against upstream**: run the same inputs through Go's own parser and kubelet's check (`references/patterns.md`, "Differential test"), and keep every input where they disagree as a test case.
3. Add the field to `KubernetesSettingsV1` (`settings-extensions/kubernetes/src/lib.rs`), update `test_generate_kubernetes`, and add tests: absent is `None` and not serialized; valid values round-trip; invalid values are rejected.
4. Bump versions in a separate `chore: bump ...` commit, as the repo does: `modeled-types` (if changed), `settings-extensions/kubernetes`, and `settings-models` crate versions, plus the workspace `Cargo.toml` pins (`Cargo.lock` is not tracked there).
   Do not edit `CHANGELOG.md`; draft the line in the PR description.
5. `cargo fmt --all`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`.
   Fix pre-existing lint failures in a separate commit rather than suppressing them.
   As of 2026-11-17, rustc 1.98 clippy reports 19 findings on develop; until they are fixed upstream, cherry-pick `5428cdc` from `~/scratch/k8s-settings-pilot/settings-sdk` (branch `pilot/max-container-restart-period`).

### Phase 2: core-kit

1. Edit the template for exactly the versions the spec renders, in the same position in each file.
2. Add a schnauzer render test in `sources/api/schnauzer/tests/` that renders every `kubernetes-1.*` template, parses the YAML (`serde_yaml`), and asserts the exact nested path and value per version, including "absent when unset" and "absent where not rendered" (`references/patterns.md`; full examples `kubelet_crash_loop_backoff.rs` and `kubelet_policy_options.rs` on the grove's core-kit branch `local/k8s-settings-pilot`, `kubelet_eviction_settings.rs` upstream).
   `test_matrix` takes literal lists and ranges, not `const` arrays.
   Confirm the test fails without the template change.
3. Point core-kit at the local SDK commit (pluto must know the key):
   ```bash
   python3 -I $T/use-local-settings-sdk.py kits/bottlerocket-core-kit/sources <sdk-clone> <rev>
   ```
   Commit it alone as `DO NOT MERGE: use local settings-sdk ...`.
4. Run the offline checks.
   **First run them on the base branch** and record what already fails (as of 2026-11-17, `template-drift.py` fails on develop with the topology options lost in 1.36/1.37): fix pre-existing failures in a separate commit, or scope the check to your keys with `--key settings.kubernetes.<name>`.
   On your branch, everything must pass apart from the recorded pre-existing failures:
   ```bash
   python3 -I $T/template-drift.py kubernetes            # and: containerd, for CRI options
   python3 -I $T/kubelet-config-lint.py
   $T/render-template.sh --settings planning/<setting>/values-<v>.toml --out planning/<setting>/render-<v> --kubelet-config
   $T/kubelet-validate.sh planning/<setting>/render-<v>
   ```
   **Boundary matrix and differential test**: list values in a file, one JSON value per line (the smallest and largest valid values, typical values, values just outside every bound, wrong types, and inputs upstream's parser treats specially), then
   ```bash
   python3 -I $T/boundary-matrix.py --setting <name> --kubelet-path <json.path> --values planning/<setting>/values.txt [--base planning/<setting>/base.toml]
   ```
   It must report no BUG: every value the model accepts is `OK` on every version that renders it.
   Its bracketed verdicts are the **counterfactual** for versions you leave out (`FATAL` is the evidence for leaving a version out; `IGNORED` means the field does not exist there) and show where the model is stricter than kubelet.
   For a single hand-made case, `counterfactual.py <render> <out> '<yaml>'` then `kubelet-validate.sh <out>`; use it with `featureGates: {<Gate>: true}` to test the "render and enable a gate" option.
   **Unset is unchanged**: render with no settings on the base branch and on yours (`render-template.sh --out ... --kubelet-config` in each checkout) and `diff -r` the two directories; they must be identical.
5. `cargo test -p schnauzer`, `cargo clippy -p schnauzer --all-targets -- -D warnings`, `cargo fmt -p schnauzer -- --check`.
6. Commit template changes and tests per logical change, with the reason per version in the message.

### Phase 3: bottlerocket

1. If `Release.toml`'s `version` is already tagged (`git tag -l v<version>`), bump it and `Twoliter.toml` `release-version` in one commit (`release: update Bottlerocket version to X`), adding an empty `"(prev, X)" = [\n]` edge.
2. Add `sources/settings-migrations/v<X>/kubernetes-<name>/` with `AddSettingsMigration` for leaf keys or `AddPrefixesMigration` for maps and structs (`references/patterns.md`), register it in `sources/Cargo.toml` members, and add `migrate_v<X>_kubernetes-<name>.lz4` to the edge.
3. Point the repo at the local SDK commit with `use-local-settings-sdk.py bottlerocket/sources ...` (DO NOT MERGE commit).
   `cargo check -p settings-plugin-aws-k8s` must pass.

### Phase 4: docs

Add the setting to bottlerocket-project-website `data/settings/<X>.x/kubernetes.toml`: accepted values, default when unset, the Kubernetes versions that apply it, and that other versions accept and ignore it.
Many shipped settings have no entry at all (`references/prior-art.md`), so do not skip this.

### Phase 5: Local build

1. Build and publish core-kit to the local registry (`build-kit-locally` skill): `brdev registry start`, `brdev twoliter use-local-publish`, `make build ARCH=x86_64`, `make publish VENDOR=local`.
   Run `make` from the core-kit root, not `sources/`.
2. Point the bottlerocket repo at it (`build-variant-from-local-kits` skill): in `bottlerocket/`, `brdev twoliter use-local-deps` writes a `Twoliter.override` that keeps the vendor name and redirects only the kits published locally:
   ```toml
   [bottlerocket.bottlerocket-core-kit]
   registry = "localhost:<port>"
   ```
   Then `cargo make install-twoliter && ./tools/twoliter/twoliter update` (the log says `overridden-to: localhost:...`), and commit the `Twoliter.lock` change as DO NOT MERGE.
   (Changing `vendor = "local"` in `Twoliter.toml` fails with "cannot define a dependency on a vendor that is not specified"; brdev before 2026-11-17 wrote an override twoliter ignores.)
3. Build the variants the tests need: the newest and oldest rendered versions and one version that does not render the setting.
   `cargo make -e BUILDSYS_VARIANT=aws-k8s-1.X -e BUILDSYS_ARCH=x86_64`, then check the migration is in `build/images/<arch>-<variant>/latest/*-migrations.tar`.
4. Register AMIs with `skills/upgrade-downgrade-test/scripts/register-ami.sh <bottlerocket> <prefix>` (unique names, recorded in a ledger).

### Phase 6: Verify on nodes

Follow `references/verification.md`.
Use an EKS cluster at the same minor; existing `bottlerocket-cluster-1XX` clusters are shared, so taint test nodes `NoSchedule` with a unique key, pin test pods to them, and terminate everything you launched.
Launch test nodes with `[settings.host-containers.admin] enabled = true` so `verify-node.sh` can read host files.

For each rendered version, every rung must pass and its output goes into the PR:

1. **Joins**: the node with the setting in user data reaches Ready (`eks-smoke-test` `wait-for-node-join.sh`).
2. **Accepted**: `apiclient get settings.kubernetes.<name>` returns the value.
3. **Rejected**: `apiclient set` with an out-of-range value fails, and the old value stays.
4. **Effective**: `verify-node.sh ... --kubelet <path> --expect <value>` passes: rendered file and live `/configz` agree, and the kubelet logged no configuration warnings.
   `/configz` normalizes durations (`60s` is reported as `1m0s`).
5. **Behavior**: the behavior test from the spec, against a node of the same build without the setting.
6. **Live change**: `apiclient set` a new value on the running node; kubelet restarts and `/configz` follows; the behavior follows for new work.
7. **Default unchanged**: on a node of the same build without the setting, the field is absent from the render and `/configz` shows the upstream default (a gated field shows its default once the gate is on, so check the value, not absence); diff its `/configz` against a stock node of the same minor (only the intended differences may appear).
8. **Not-rendered version**: on a version the spec leaves out, the API accepts the value, nothing renders, `/configz` shows the default, and the node is Ready.

### Phase 7: Upgrade and downgrade

Run the `upgrade-downgrade-test` skill with the setting set on the new version: upgrade from the previous release keeps everything working, and downgrading removes the key through the migration so the old API starts.
It needs an HTTPS-served S3 prefix for the test TUF repo: ask the user which bucket to use before writing to one.

### Phase 8: PRs and release order

Drafts only, until the user says to open them.

1. settings-sdk PR (model, tests, versions); maintainers release `bottlerocket-settings-models-vN`.
2. core-kit PR: templates, render tests, and the settings-models tag bump (replace the DO NOT MERGE commit); released in core-kit `M`.
3. bottlerocket PR: settings-models tag bump (equal to core-kit `M`'s), migration, version bump, and the core-kit `M` pin.
4. website PR.

Each description states the per-version decision with citations, the testing rungs with output, and links the others.
If a core-kit release is rolled back, roll back the bottlerocket tag bump and migration with it, and rename the migration when it re-lands (bottlerocket#4660, #4661).

### Phase 9: Clean up

Terminate instances, deregister AMIs and delete their snapshots (from the ledger), delete test pods and namespaces, `brdev twoliter use-upstream`-style cleanup of `Twoliter.override` and `Infra.toml`, and drop the DO NOT MERGE commits once real tags exist.

## Auditing an existing setting

Run Phase 0 steps 3-4 and Phase 2 step 4 against the current templates, then compare with what ships.
`references/settings-catalog/` holds a full audit of the settings shipped up to 2026-11-17 by group, with per-version tables, findings, and node checks; start there.

## Known open findings (2026-11-17)

Checked with `kubelet-validate.sh` unless marked otherwise; details and citations in `references/settings-catalog/`.

Fixed on the local pilot branch (core-kit `local/k8s-settings-pilot`), not yet upstream:

- kubernetes-1.36/1.37 never render `topology-manager-policy-options` (reproduced on a stock aws-k8s-1.36 v1.69.0 node: `/configz` shows `null`).
- kubernetes-1.32 renders the Alpha `strict-cpu-reservation` CPU option: kubelet 1.32 is `FATAL` ("Alpha-level Options not enabled").
- kubernetes-1.33 drops `distribute-cpus-across-numa`: the handlebars `or` helper reads only two arguments.

Open: the API accepts values that make kubelet exit (node never joins), on every version that renders them:

- `container-log-max-workers` <= 0; `container-log-monitor-interval` < 3s; `image-maximum-gc-age` not greater than the minimum (default 2m); negative `max-parallel-image-pulls`; negative `ids-per-pod`.
- `kube-reserved` / `system-reserved` quantities such as `1K`; `eviction-hard` values of `0`.
- Strings are HTML-escaped by handlebars: `provider-id = "aws:///z/i-0?x=1&y=2"` (accepted by `Url`) renders `x&#x3D;1&amp;y&#x3D;2` (checked with `render-template.sh`); the same applies to every `Url` or string setting rendered with `{{ }}`.
- Inferred, needs a node: most `ids-per-pod` values on 1.35+ (user-namespace ID range), `container-runtime-endpoint` values other than `unix://` paths and values with spaces, durations that overflow Go's `time.Duration`.

Tooling and repo state: `template-drift.py` fails on core-kit develop until the topology fix lands; the forest's bare repos may be behind GitHub (see "Before you start").

Docs: no website entry for `memory-swap-behavior`, `static-pods-enabled`, `container-runtime-endpoint`, `memory-reservation-policy`, `memory-throttling-factor`, `kube-reserved.pid`; the `device-ownership-from-security-context` default is documented wrongly.

## Common issues

| Symptom | Cause | Fix |
|---|---|---|
| Setting accepted, nothing changes | key misplaced, version not rendered, or gate off | `verify-node.sh` `/configz`; `kubelet-config-lint.py`; check the spec's version table |
| Node never joins after setting a value | kubelet validation or startup parse failure | `kubelet-validate.sh` on that render; `journalctl -u kubelet` |
| pluto or boot fails with an unknown field | bottlerocket accepts a key core-kit's model does not know | make the settings-models tags equal (Phase 8) |
| `cannot define a dependency on a vendor that is not specified` | `vendor = "local"` in `Twoliter.toml` | use the `Twoliter.override` form in Phase 5 |
| `verify-node.sh` exits 2 | admin container disabled | enable it in user data, or `apiclient set host-containers.admin.enabled=true` |
| `apiclient get host-containers...` prints `{}` | `apiclient get` needs the `settings.` prefix (`set` adds it implicitly) | `apiclient get settings.host-containers...` |
| `render-template.sh` says a template looks like a minor | `1.35` given without `--kubelet-config` | add `--kubelet-config` |
| Rendered strings contain `&amp;`, `&#x3D;` | handlebars HTML escaping of `{{x}}` | restrict the model's characters, or use `{{{x}}}` and quote safely |
| Render test passes but a value is missing on a node | template edited in the wrong `kubernetes-1.X`, or variant built from an old kit | `template-drift.py`; check `Twoliter.lock` digest and `git log` in core-kit |

## Supporting files

| File | Contents |
|---|---|
| `references/prior-art.md` | every shipped Kubernetes setting with its four PRs, and the lessons each taught |
| `references/k8s-source-guide.md` | where each question is answered in Kubernetes and containerd source, and how to read it per version |
| `references/patterns.md` | code patterns: modeled types, model fields and tests, template guards, render tests, migrations, differential tests |
| `references/verification.md` | node verification commands and behavior tests by kind of setting, evidence format |
| `references/spec-template.md` | the Phase 0 spec |
| `references/settings-catalog/*.md` | per-version audit of shipped settings |
| `references/base-settings-aws-k8s.json` | sanitized settings of a real aws-k8s-1.36 node, the base for renders |
| `references/pilot-max-container-restart-period.md` | a complete worked run of this skill (bottlerocket#4979) |
