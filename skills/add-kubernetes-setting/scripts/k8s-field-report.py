#!/usr/bin/env python3
"""Per-version facts about a kubelet setting, read from the exact source each core-kit package builds.

Usage:
  k8s-field-report.py field JSON.PATH [MINOR...]   KubeletConfiguration field, e.g. memorySwap.swapBehavior
  k8s-field-report.py flag NAME [MINOR...]         kubelet command-line flag, e.g. container-runtime-endpoint
  k8s-field-report.py gate NAME [MINOR...]         feature gate, e.g. MemoryQoS
  k8s-field-report.py containerd TOML_KEY          containerd CRI config key, e.g. device_ownership_from_security_context

MINOR defaults to every kubernetes-1.* package in core-kit (or every containerd-* package).
Env: CORE_KIT (default ./kits/bottlerocket-core-kit), BR_SRC_CACHE (see fetch-package-source.sh).

The report is evidence to read, not a verdict: always open the cited lines before deciding.
"""

import difflib
import re
import subprocess
import sys
from pathlib import Path

# Scripts run with python3 -I, which leaves the script directory off sys.path. Do not write
# __pycache__ into the skill directory.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from k8ssrc import (DEFAULTS, FLAGS, TYPES_V1BETA1, VALIDATION_DIR, all_gates,  # noqa: E402
                    enclosing_gates, fetch, function_digest, gate_markers, grep_context, packages,
                    read, resolve_field, show_gates)


def consumers(root, go_name):
    """Non-test, non-generated uses of a field in kubelet code, for behavior-test design."""
    out = subprocess.run(
        ["grep", "-rnE", rf"\.{go_name}\b", "pkg/kubelet", "cmd/kubelet", "--include=*.go"],
        cwd=root, capture_output=True, text=True,
    ).stdout.splitlines()
    skip = ("_test.go", "zz_generated", "/apis/config/", "/testing/", "_mock.go", "/fake")
    keep = [l for l in out if not any(x in l.split(":", 1)[0] for x in skip)]
    e2e = subprocess.run(["grep", "-rlE", rf"\b{go_name}\b", "test/e2e_node"], cwd=root,
                         capture_output=True, text=True).stdout.split()
    return keep, sorted(e2e)


# Receivers and packages in validation code that are not worth following.
NOT_PACKAGES = {"fmt", "kc", "obj", "errors", "strings", "ptr", "sets", "field", "utilvalidation",
                "utilfeature", "localFeatureGate", "featureGate", "metav1", "time", "allErrors", "math"}


def condition_gates(ctx, field_pattern, known):
    """Gates named on the lines of a match window that mention the field, or the if line above it."""
    gates = set()
    for i, line in enumerate(ctx):
        nxt = ctx[i + 1] if i + 1 < len(ctx) else ""
        if re.search(field_pattern, line) or (line.strip().startswith(("if ", "} else if")) and re.search(field_pattern, nxt)):
            gates |= {g for g in re.findall(r"features\.(\w+)", line) if g in known}
    return gates


def report_field(rows, dotted):
    snapshots = []
    for pkg, version, root in rows:
        minor = ".".join(version.split(".")[:2])
        out = [f"== {pkg} ({version})"]
        field = resolve_field(root, dotted)
        if field is None:
            out.append(f"  ABSENT: no '{dotted}' in KubeletConfiguration v1beta1")
            snapshots.append((pkg, out))
            continue
        go_path = ".".join(field["go_path"])
        leaf = field["go_path"][-1]
        out.append(f"  field: {go_path} {field['go_type']}  ({field['where']})")
        if field["map_key"]:
            out.append(f"  '{field['map_key']}' is a key of this map, not a struct field: find the code that"
                       f" parses the map's keys and values (see consumers below)")
        out += [f"    {c}" for c in field["comment"]]
        known = all_gates(root)
        gates = {g for g in known if any(re.search(rf"\b{g}\b", c) for c in field["comment"])}
        markers = gate_markers(field["comment"])
        gates |= markers
        # Validation sometimes goes through a local alias (userNs := kc.UserNamespaces), so also match
        # the bare field name.
        field_pattern = rf"(kc|obj)\.{re.escape(go_path)}\b|\.{leaf}\b"
        for where, ctx in grep_context(root / DEFAULTS, DEFAULTS, rf"obj\.{re.escape(go_path)}\b", before=1, after=1):
            out.append(f"  default @ {where}")
            out += [f"    {l}" for l in ctx]
        callees = {}
        for vfile in sorted((root / VALIDATION_DIR).glob("validation*.go")):
            if vfile.name.endswith("_test.go"):
                continue
            rel = f"{VALIDATION_DIR}/{vfile.name}"
            for where, ctx in grep_context(vfile, rel, field_pattern, before=2, after=2):
                out.append(f"  validation @ {where}")
                out += [f"    {l}" for l in ctx]
                gates |= condition_gates(ctx, field_pattern, known)
                for alias, name in re.findall(r"\b([a-z]\w*)\.([A-Z]\w*)\(", "\n".join(ctx)):
                    if alias not in NOT_PACKAGES:
                        callees[f"{alias}.{name}"] = name
            # Gates checked by an enclosing block (if localFeatureGate.Enabled(...) { ... field ... }).
            vlines = read(vfile)
            for i, line in enumerate(vlines):
                if re.search(field_pattern, line):
                    gates |= enclosing_gates(vlines, i, known)
        out += show_gates(root, minor, gates)
        # Validation that calls into other packages: behavior can change there while this file does not.
        for call, name in sorted(callees.items()):
            where, digest = function_digest(root, name)
            if where:
                out.append(f"  validation calls {call} @ {where}  body#{digest}")
        uses, e2e = consumers(root, leaf)
        out.append(f"  direct references in pkg/kubelet, cmd/kubelet: {len(uses)} (follow the plumbing from here)")
        out += [f"    {l[:160]}" for l in uses[:12]]
        if e2e:
            out.append(f"  e2e_node files that mention it (not proof of coverage): {', '.join(e2e[:8])}")
        snapshots.append((pkg, out))
    emit(snapshots)


def report_flag(rows, flag):
    snapshots = []
    for pkg, version, root in rows:
        out = [f"== {pkg} ({version})"]
        found = False
        for path in sorted((root / "cmd/kubelet/app/options").glob("*.go")):
            if path.name.endswith("_test.go"):
                continue
            rel = f"cmd/kubelet/app/options/{path.name}"
            for where, ctx in grep_context(path, rel, rf'"{re.escape(flag)}"', before=0, after=1):
                found = True
                out.append(f"  {where}")
                out += [f"    {l.strip()}" for l in ctx]
                bound = re.search(r"&c\.(\w+)", " ".join(ctx))
                if bound:
                    out.append(f"  DEPRECATED: bound to KubeletConfiguration field {bound.group(1)}, and AddKubeletConfigFlags"
                               f" deprecates every config-bound flag; prefer rendering the config file field")
                if any("MarkDeprecated" in l for l in ctx):
                    out.append("  DEPRECATED flag")
        if not found:
            out.append(f"  ABSENT: no --{flag} in cmd/kubelet/app/options/*.go")
        snapshots.append((pkg, out))
    emit(snapshots)


def report_gate(rows, gate):
    snapshots = []
    for pkg, version, root in rows:
        minor = ".".join(version.split(".")[:2])
        snapshots.append((pkg, [f"== {pkg} ({version})", *show_gates(root, minor, {gate})]))
    emit(snapshots)


def report_containerd(rows, key):
    snapshots = []
    for pkg, version, root in rows:
        out = [f"== {pkg} ({version})"]
        res = subprocess.run(["grep", "-rn", "--include=*.go", f'toml:"{key}"', "."], cwd=root,
                             capture_output=True, text=True).stdout.splitlines()
        res = [r for r in res if "_test.go" not in r and "/vendor/" not in r]
        if not res:
            out.append(f"  ABSENT: no toml:\"{key}\" outside vendor/")
        for r in res:
            path, lineno, _ = r.split(":", 2)
            lines = read(root / path)
            i = int(lineno) - 1
            j = i
            while j > 0 and lines[j - 1].strip().startswith("//"):
                j -= 1
            struct = next((re.match(r"^type (\w+) struct", lines[k]).group(1)
                           for k in range(i, -1, -1) if re.match(r"^type (\w+) struct", lines[k])), "?")
            out.append(f"  {path[2:]}:{lineno} (struct {struct})")
            out += [f"    {l.strip()}" for l in lines[j:i + 1]]
            go_name = lines[i].split()[0]
            for d in subprocess.run(["grep", "-rnE", rf"\b{go_name}:", "--include=*.go", "."], cwd=root,
                                    capture_output=True, text=True).stdout.splitlines():
                if "_test.go" not in d and "/vendor/" not in d:
                    out.append(f"  default/literal @ {d[2:][:160]}")
        snapshots.append((pkg, out))
    emit(snapshots)


def emit(snapshots):
    for _, out in snapshots:
        print("\n".join(out))
        print()
    print("== Changes between consecutive versions (line numbers ignored)")
    # Compare substance only: drop line numbers, gate history, and brace or blank context lines.
    strip = lambda out: [re.sub(r"\s+\[.*\]$", "", re.sub(r"(\.go):\d+", r"\1", l))
                         for l in out[1:] if l.strip() not in ("", "}", "{")]
    absent = lambda out: any("ABSENT" in l for l in out)
    changed = False
    for (a, oa), (b, ob) in zip(snapshots, snapshots[1:]):
        if absent(oa) != absent(ob):
            changed = True
            print(f"  {b}: {'removed' if absent(ob) else 'added'}\n")
            continue
        diff = list(difflib.unified_diff(strip(oa), strip(ob), a, b, lineterm="", n=0))
        if diff:
            changed = True
            print("\n".join(diff))
            print()
    if not changed:
        print("  none")


def main(argv):
    if len(argv) < 3 or argv[1] not in {"field", "flag", "gate", "containerd"}:
        print(__doc__, file=sys.stderr)
        return 2
    mode, name, minors = argv[1], argv[2], argv[3:]
    if mode == "containerd":
        rows = fetch(packages("containerd-", [m for m in minors]))
        report_containerd(rows, name)
        return 0
    rows = fetch(packages("kubernetes-", minors))
    {"field": report_field, "flag": report_flag, "gate": report_gate}[mode](rows, name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
