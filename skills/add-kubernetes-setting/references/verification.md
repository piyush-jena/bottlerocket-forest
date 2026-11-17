# Verifying a Kubernetes setting on nodes

**Keywords:** verification ladder, configz, apiclient, sheltie, EKS test node, behavior test, A/B, evidence

Offline checks (render tests, `kubelet-config-lint.py`, `kubelet-validate.sh`) prove the kubelet would start and receive the value.
Only a node proves the feature works, that the API accepts what it should and rejects what it should, and that nodes without the setting are unchanged.

## Test nodes

- Use an EKS cluster at the same minor as the variant (`aws eks list-clusters`; the team clusters are `bottlerocket-cluster-1XX` in us-west-2).
  They are shared: never change cluster-wide objects, and keep your nodes and pods to yourself.
- Network and IAM: copy them from the cluster's eksctl stacks.
  ```bash
  c=136
  aws cloudformation describe-stack-resources --stack-name eksctl-bottlerocket-cluster-$c-cluster \
    --query "StackResources[?LogicalResourceId=='ClusterSharedNodeSecurityGroup'].PhysicalResourceId" --output text
  aws cloudformation describe-stacks --query "Stacks[?contains(StackName, 'bottlerocket-cluster-$c-nodegroup')].StackName"
  aws cloudformation describe-stack-resources --stack-name <nodegroup-stack> \
    --query "StackResources[?ResourceType=='AWS::IAM::InstanceProfile' || ResourceType=='AWS::EC2::SecurityGroup'].PhysicalResourceId"
  ```
  `SG_ID` is the nodegroup group plus the shared-node group; `SUBNET_ID` is one of the cluster's subnets.
- User data: `launch-bottlerocket-ec2/scripts/get-eks-details.sh <cluster> base.toml` (fresh CA), then append:
  ```toml
  max-container-restart-period = "5s"          # the setting under test, in [settings.kubernetes]

  [settings.kubernetes.node-taints]
  "k8s-settings-test" = ["pilot:NoSchedule"]   # keep other workloads off

  [settings.kubernetes.node-labels]
  "k8s-settings-test" = "<role>"               # find your nodes: kubectl get nodes -l k8s-settings-test

  [settings.host-containers.admin]
  enabled = true                               # verify-node.sh reads host files through sheltie
  ```
- Launch with `launch-bottlerocket-ec2/scripts/launch-instance.sh`, append every instance and AMI to a ledger, and wait with `eks-smoke-test/scripts/wait-for-node-join.sh`.
- For a cluster that is not your current kube context, use a separate kubeconfig instead of switching the user's context:
  `kubectl config view --minify --flatten --context=<arn> > /tmp/kc-1XX; export KUBECONFIG=/tmp/kc-1XX`.
- Test pods: own namespace (`k8s-settings-test`), `nodeName: <node>`, and a toleration for `k8s-settings-test`.

Nodes for one setting, typically:

| Node | Image | User data | Proves |
|---|---|---|---|
| A | new build, newest rendered minor | setting set | rungs 1-6 |
| B | new build, same minor | setting not set | rung 5 baseline, rung 7 |
| S | stock AMI, same minor (`/aws/service/bottlerocket/aws-k8s-1.X/x86_64/latest/image_id`) | same as B, or reproducing the bug | rung 7 diff; bug reproduction for fixes |
| O | new build, a minor that does not render it | setting set | rung 8 |

## The ladder

`T=~/Repositories/bottlerocket-forest/skills/add-kubernetes-setting/scripts`, `SSM=~/Repositories/bottlerocket-forest/skills/ssm-executor/scripts`.

1. **Joins.**
   `wait-for-node-join.sh <instance> 600`.
   If it never registers, read why before anything else: `$SSM/sheltie-command.sh <id> <region> "journalctl -u kubelet -b --no-pager -o cat" | grep -E 'command failed|invalid configuration'`.
   (sheltie only allows some programs: `journalctl` and `cat` work, `systemctl` does not.)
2. **Accepted.**
   `$SSM/control-container-command.sh <id> <region> "apiclient get settings.kubernetes.<name>"`.
   `apiclient get` needs the `settings.` prefix; `apiclient set` adds it.
3. **Rejected.**
   For each out-of-range or wrongly typed value: `apiclient set kubernetes.<name>=<bad>` must fail with the model's message, and `apiclient get` must still show the old value.
4. **Effective.**
   `$T/verify-node.sh --instance <id> --region <r> --setting <name> --kubelet <json.path> --expect <value>`.
   Passes only when the rendered file and the live `/configz` agree and the kubelet logged no `strict decoding`, `unknown field`, or `invalid configuration` messages this boot.
   `/configz` prints values as the kubelet holds them: durations normalized (`60s` is `1m0s`), quantities canonicalized, maps of strings quoted.
   Use `--flag <name>` for kubelet flags and `--file <path> --file-path <toml.path>` for containerd (`plugins."io.containerd.cri.v1.runtime".<key>` on 2.x).
5. **Behavior.**
   The setting-specific test, run on A and B at the same time, with numbers in the evidence (see below).
6. **Live change.**
   `apiclient set kubernetes.<name>=<other>`, then rerun rung 4 with `--expect <other>` and rerun the behavior test with a fresh pod.
   kubelet restarts on `settings.kubernetes.*` changes; work already running keeps old behavior until recreated (for containerd settings, containers must be recreated).
7. **Default unchanged.**
   On B, the setting's path is absent from the render and `/configz` shows the upstream default.
   Gated fields are defaulted once their gate is on (for example `imagePullCredentialsVerificationPolicy: NeverVerifyPreloadedImages` on 1.35+), so compare the value with the default rather than using `--expect absent`.
   Then `diff <(kubectl get --raw .../S/proxy/configz | jq -S .kubeletconfig) <(... B ...)`: only per-node values (`providerID`) and settings that differ in user data may appear.
8. **Not-rendered minor.**
   On O: rung 2 shows the value, rung 4 with `--expect absent` passes (gated structs may show as `{}`), the node is Ready, and no warnings are logged.
9. **Upgrade and downgrade** (`upgrade-downgrade-test` skill): needs an HTTPS-served S3 prefix; ask the user which bucket.

Keep each command and its output in `planning/<setting>/evidence-*.md`; `verify-node.sh` already prints markdown.

## Behavior tests by kind of setting

Pick the cheapest test that would fail if the kubelet ignored the value.
Durations below the default are the fastest to observe.

| Kind | Test | Expected A vs B |
|---|---|---|
| Container restart backoff (`max-container-restart-period`) | `references/probes/crashloop-backoff-probe.sh 240 <A> <B>`: a container that exits at once; records the gaps between restarts | gaps stop growing at the cap (plus up to about 15s of sync jitter) vs doubling 10, 20, 40, 80s |
| Eviction thresholds and merging | `kubectl get --raw .../configz \| jq .kubeletconfig.evictionHard`; `kubectl describe node` conditions | with merge on, unspecified signals keep their defaults (`imagefs.available: 15%`, ...) |
| Memory QoS, OOM, swap | Burstable pod with requests and limits; read `/sys/fs/cgroup/kubepods.slice/.../memory.{min,low,high,swap.max,oom.group}` with sheltie | values computed from requests, limits and the factor (`settings-catalog/memory-oom.md`, `swap-cgroup.md`) |
| Log rotation | pod writing logs faster than `container-log-max-size`; watch `/var/log/pods/...` file count and rotation times | rotation interval tracks `container-log-monitor-interval` |
| Image GC by age | pull an image on the node, delete its pods, wait past `image-maximum-gc-age` | image removed by kubelet (`kubelet_image_garbage_collected_total` from 1.32) |
| Parallel pulls | schedule several pods with distinct large images at once; compare `Pulling`/`Pulled` event times | overlapping pulls up to the limit vs serialized |
| CPU and topology manager options | `/configz` plus the kubelet startup log (`journalctl -u kubelet \| grep -i 'topology manager\|cpu manager'`); real behavior needs SMT or multi-NUMA instances (`settings-catalog/cpu-topology.md`) | options listed; Guaranteed pod pinned per option |
| User namespaces (`ids-per-pod`) | pod with `hostUsers: false`; `cat /proc/<pid>/uid_map` via sheltie | range length equals the setting (only on 1.35+, see catalog) |
| Static pods | write a manifest through `settings.kubernetes.static-pods`; check the mirror pod | no mirror pod when disabled |
| containerd device ownership | Block-mode local PV backed by a loop device; `ls -ln` inside a `runAsUser` pod (`settings-catalog/containerd.md`) | owner is the pod's UID/GID when true, root when false |
| Image pull credential verification | private image the node role cannot pull; pod 1 pulls it with an image pull secret, pod 2 without the secret uses it with `imagePullPolicy: IfNotPresent`; for preloaded images, pull with `ctr` through sheltie first; `kubelet_imagemanager_image_mustpull_checks_total` in `/metrics` | pod 2 Running under `NeverVerify`, `ErrImagePull`/`ImagePullBackOff` under the default and `AlwaysVerify`; preloaded images allowed by the default and by a matching allowlist only |
| Kubelet flags (`container-runtime-endpoint`) | `verify-node.sh --flag <name>`; `crictl --runtime-endpoint` on the node | flag on the running process; pods still run |

## Evidence format for the PR

```markdown
**Testing done:**

Built aws-k8s-1.36 and aws-k8s-1.34 (x86_64) from these changes with a local core-kit, and launched them into EKS 1.36 and 1.34.

- Joins: node Ready with `settings.kubernetes.<name> = "<v>"` in user data.
- Rejected: `apiclient set kubernetes.<name>=<bad>` -> `<message>`; value unchanged.
- Effective: rendered `/etc/kubernetes/kubelet/config` and `/configz` both show `<path>: <v>`; no kubelet config warnings.
- Behavior: <numbers for A vs B>.
- Live change: set `<v2>`; `/configz` shows `<v2>`; behavior <numbers>.
- Default unchanged: `/configz` of a node without the setting equals a stock 1.69.0 node's, apart from providerID.
- 1.34: accepted by the API, not rendered, `/configz` shows the default, node Ready.
- Offline: render tests for 1.31-1.37; `kubelet-validate.sh` OK on every rendered version for <values>; FATAL on 1.32-1.34 when forced (why those versions do not render it).
```
