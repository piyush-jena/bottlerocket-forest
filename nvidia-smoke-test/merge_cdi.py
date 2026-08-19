#!/usr/bin/env python3
"""merge_cdi.py INFO_JSON CDI_JSON ROOTFS_PATH  ->  prints a runnable OCI spec on stdout.

Takes the base OCI runtime spec from `ctr container info <helper>` (.Spec) and:
  - sets process.selinuxLabel = system_u:system_r:container_t:s0
  - sets linux.mountLabel     = system_u:object_r:data_t:s0
  - sets root.path = ROOTFS_PATH (readonly=false)   <- the writable `ctr images mount --rw` rootfs
  - merges the CDI /etc/cdi/nvidia.json containerEdits (global + device "all"):
      env, deviceNodes -> linux.devices + linux.resources.devices allow,
      createContainer hooks, and driver-library/tool bind mounts.
This is the transformation containerd's oci.WithCDIDevices performs; needed because bare `ctr`
gives no SELinux label (container lands in control_t on a read-only rootfs -> writes denied).
"""
import json, sys

info = json.load(open(sys.argv[1]))
cdi = json.load(open(sys.argv[2]))
rootfs = sys.argv[3]

spec = info["Spec"]  # `ctr container info` embeds the decoded OCI runtime spec here.

spec.setdefault("process", {})["selinuxLabel"] = "system_u:system_r:container_t:s0"
spec.setdefault("linux", {})["mountLabel"] = "system_u:object_r:data_t:s0"
spec["root"] = {"path": rootfs, "readonly": False}

edits = []
if cdi.get("containerEdits"):
    edits.append(cdi["containerEdits"])
by_name = {d.get("name"): d for d in cdi.get("devices", [])}
dev = by_name.get("all") or (list(by_name.values())[0] if by_name else None)
if dev and dev.get("containerEdits"):
    edits.append(dev["containerEdits"])

linux = spec.setdefault("linux", {})
resources = linux.setdefault("resources", {})
devallow = resources.setdefault("devices", [])
for e in edits:
    for env in e.get("env", []) or []:
        spec["process"].setdefault("env", []).append(env)
    for dn in e.get("deviceNodes", []) or []:
        entry = {"path": dn["path"], "type": dn.get("type", "c")}
        for k in ("major", "minor", "fileMode", "uid", "gid"):
            if k in dn:
                entry[k] = dn[k]
        linux.setdefault("devices", []).append(entry)
        devallow.append({"allow": True, "type": entry["type"],
                         "major": entry.get("major"), "minor": entry.get("minor"),
                         "access": "rwm"})
    for h in e.get("hooks", []) or []:
        htype = h.get("hookName", "createContainer")
        hook = {"path": h["path"]}
        if h.get("args"):
            hook["args"] = h["args"]
        if h.get("env"):
            hook["env"] = h["env"]
        spec.setdefault("hooks", {}).setdefault(htype, []).append(hook)
    for m in e.get("mounts", []) or []:
        spec.setdefault("mounts", []).append({
            "destination": m["containerPath"],
            "source": m["hostPath"],
            "type": "bind",
            "options": m.get("options", ["ro", "rbind", "rprivate"]),
        })

json.dump(spec, sys.stdout)
