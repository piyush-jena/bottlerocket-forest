# nvidia-smoke-test (ctr on Bottlerocket aws-mantle-1-nvidia*)

Run `nvidia-smoke-test` on a running Bottlerocket NVIDIA instance through the containerd API (`ctr`) — no
Docker, no kubelet/CRI. Encodes the working recipe recorded in the mantle-e2e-test-suite (AC-6): bare
`ctr run --device nvidia.com/gpu=all` fails on Bottlerocket (SELinux `control_t` on a read-only rootfs), so we
use a writable rootfs + `data_t`/`container_t` labels + a custom OCI spec with the boot-generated CDI merged in.

## Usage

```bash
# INSTANCE_ID as env or arg1; must be a running -nvidia / -nvidia-fips host with admin+control ON, SSM Online
INSTANCE_ID=i-0123456789abcdef0 ./run-nvidia-smoke.sh
# or
./run-nvidia-smoke.sh i-0123456789abcdef0 us-west-2
```

Requires local `aws` CLI creds for the instance's region/account and `python3`.

## Files

| File | Purpose |
| --- | --- |
| `run-nvidia-smoke.sh` | Entrypoint. Orchestrates the 9-step recipe on `$INSTANCE_ID`. |
| `sheltie.sh` | **Polling** copy of `ssm-executor/scripts/sheltie-command.sh` — runs one host binary via `apiclient exec admin sheltie` and polls the SSM invocation to completion (the skill version's fixed 4s wait truncates pulls/GPU runs). `sheltie.sh IID REGION "CMD" [TIMEOUT]`. |
| `deliver-file.sh` | Chunked base64 delivery of the OCI spec to the shell-less host (via the admin container). |
| `merge_cdi.py` | Merges `/etc/cdi/nvidia.json` containerEdits into the base OCI spec + sets the SELinux labels + writable `root.path`. |

## What it does (9 steps)
1. `ctr images pull` the image.
2. `ctr images mount --rw` → writable rootfs at `/local/nvidia-rootfs`.
3. `chcon … data_t` relabel the rootfs.
4. `ctr container create` + `ctr container info` → capture the image's base OCI runtime spec.
5. `cat /etc/cdi/nvidia.json` → the CDI spec generated at boot by `nvidia-container-toolkit-ecs`.
6. Merge locally: SELinux `container_t`/`data_t`, `root.path`, + CDI device nodes/hooks/driver mounts.
7. Deliver the merged spec to the host.
8. `ctr run --rm --rootfs -c <spec>` → runs the GPU workload; prints its output.
9. Cleanup (helper container, unmount, snapshot rm).

Expected: the CUDA sample battery — `deviceQuery` → `Device 0: "NVIDIA L4"`, `NumDevs = 1`, `Result = PASS`;
`vectorAdd Test PASSED`. Works identically on `-nvidia-fips`.

## Caveats
- SSM returns only the last ~24000 chars of a command's stdout inline; fine for `container info` /
  `cat nvidia.json`, but a very chatty step could clip.
- CDI device name defaults to `all`; adjust in `merge_cdi.py` if `ctr`/CDI reports it differently.
- Not yet validated end-to-end against a live GPU host in this session — run it and check step 8's output.
