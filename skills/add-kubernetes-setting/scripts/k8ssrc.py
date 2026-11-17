"""Shared readers for the Kubernetes sources that core-kit packages build from.

Used by k8s-field-report.py and kubelet-config-lint.py; not a CLI.
"""

import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
CORE_KIT = Path(os.environ.get("CORE_KIT", "./kits/bottlerocket-core-kit"))

TYPES_V1BETA1 = "staging/src/k8s.io/kubelet/config/v1beta1/types.go"
DEFAULTS = "pkg/kubelet/apis/config/v1beta1/defaults.go"
VALIDATION_DIR = "pkg/kubelet/apis/config/validation"
FEATURES = "pkg/features/kube_features.go"
FLAGS = "cmd/kubelet/app/options/options.go"


def fetch(packages):
    """Return [(package, version, root)] using fetch-package-source.sh (cached)."""
    result = subprocess.run(
        [str(SCRIPTS / "fetch-package-source.sh"), *packages],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(result.stderr.strip() or f"fetch-package-source.sh failed for {' '.join(packages)}")
    rows = []
    for line in result.stdout.splitlines():
        pkg, version, root = line.split(" ", 2)
        rows.append((pkg, version, Path(root)))
    return rows


def packages(prefix, minors):
    """Package names for MINOR arguments ("1.35"), or every package with the prefix."""
    if minors:
        pattern = r"\d+\.\d+" if prefix == "kubernetes-" else r"[\w.]+"
        bad = [m for m in minors if not re.fullmatch(pattern, m)]
        if bad:
            sys.exit(f"invalid version {', '.join(bad)}: give minors like 1.35")
        return [f"{prefix}{m}" for m in minors]
    names = [p.name for p in (CORE_KIT / "packages").glob(f"{prefix}*") if p.is_dir()]
    return sorted(names, key=lambda n: [int(x) for x in re.findall(r"\d+", n)])


def read(path):
    try:
        return path.read_text().splitlines()
    except FileNotFoundError:
        return []


def struct_fields(lines, struct):
    """Yield (go_name, go_type, json_tag, comment_lines, lineno) for a Go struct."""
    start = next((i for i, l in enumerate(lines) if re.match(rf"^type {struct} struct \{{", l)), None)
    if start is None:
        return
    comment = []
    for i in range(start + 1, len(lines)):
        line = lines[i]
        if line.startswith("}"):
            return
        stripped = line.strip()
        if stripped.startswith("//"):
            comment.append(stripped)
            continue
        m = re.match(r"^\s+(\w+)\s+(\S+)\s+`.*json:\"([^\",]*)", line)
        if m:
            yield m.group(1), m.group(2), m.group(3), comment, i + 1
        if not stripped or m:
            comment = []


def resolve_field(root, dotted):
    """Walk a dotted JSON path from KubeletConfiguration. Return dict or None if absent.

    A path that continues past a map-typed field (kubeReserved.pid) resolves to the map field,
    with "map_key" set to the rest of the path.
    """
    lines = read(root / TYPES_V1BETA1)
    struct, go_path, result = "KubeletConfiguration", [], None
    parts = dotted.split(".")
    for i, part in enumerate(parts):
        if result and result["go_type"].lstrip("*").startswith("map["):
            result["map_key"] = ".".join(parts[i:])
            return result
        found = next((f for f in struct_fields(lines, struct) if f[2] == part), None)
        if found is None:
            return None
        go_name, go_type, _, comment, lineno = found
        go_path.append(go_name)
        result = {"go_path": go_path[:], "go_type": go_type, "comment": comment,
                  "where": f"{TYPES_V1BETA1}:{lineno}", "struct": struct, "map_key": None}
        struct = re.sub(r"^[\*\[\]]*(map\[[^\]]+\])?\*?", "", go_type).split(".")[-1]
    return result


def gate_markers(comment):
    """Feature gate names from +featureGate= markers in a field's doc comment."""
    return {g for line in comment for m in re.findall(r"\+featureGate=([\w,]+)", line) for g in m.split(",")}


def grep_context(path, rel, pattern, before=1, after=3):
    """Return [(rel:line, context_lines)], merging hits whose context windows overlap."""
    lines = read(path)
    windows = []
    for i, line in enumerate(lines):
        if re.search(pattern, line):
            lo, hi = max(0, i - before), min(len(lines), i + after + 1)
            if windows and lo <= windows[-1][2]:
                windows[-1][2] = hi
            else:
                windows.append([i, lo, hi])
    return [(f"{rel}:{i + 1}", [l.rstrip() for l in lines[lo:hi]]) for i, lo, hi in windows]


def all_gates(root):
    return set(re.findall(r"^\t(\w+) featuregate\.Feature = \"", (root / FEATURES).read_text(), re.M))


def parse_spec(body):
    """Parse one '{Version: ..., Default: ..., PreRelease: ..., LockToDefault: ...}' entry."""
    get = lambda pattern: (re.search(pattern, body) or [None, None])[1]
    return (get(r'Version: version\.MustParse\("([\d.]+)"\)'), get(r"Default: (\w+)"),
            get(r"LockToDefault: (\w+)"), get(r"PreRelease: featuregate\.(\w+)"))


def gate_spec(root, gate, minor):
    """Return (entries, effective) for a feature gate in this source tree.

    Handles all layouts in use: versioned blocks in kube_features.go (1.33+), versioned blocks in
    versioned_kube_features.go (1.32), and unversioned single-line map entries (1.31 and older).
    """
    entries = []
    for name in ("kube_features.go", "versioned_kube_features.go"):
        path = root / "pkg/features" / name
        if not path.exists():
            continue
        text = path.read_text()
        block = re.search(rf"^\t{gate}: \{{\n(.*?)^\t\}},", text, re.M | re.S)
        if block:
            entries += [parse_spec(e) for e in re.findall(r"\{([^{}]*Version:[^{}]*)\}", block.group(1))]
        line = re.search(rf"^\t{gate}: \{{([^{{}}\n]*Default:[^{{}}\n]*)\}},", text, re.M)
        if line and not entries:
            entries.append(("unversioned", *parse_spec(line.group(1))[1:]))
    key = lambda v: [int(x) for x in v.split(".")] if v and v[0].isdigit() else [0]
    effective = None
    for version, default, lock, pre in sorted(entries, key=lambda e: key(e[0])):
        if key(version) <= key(minor):
            effective = f"{pre} default={default}" + (" locked" if lock == "true" else "")
    return entries, effective


def gate_location(root, gate):
    for name in ("kube_features.go", "versioned_kube_features.go"):
        rel = f"pkg/features/{name}"
        for i, line in enumerate(read(root / rel)):
            if re.match(rf"^\t{gate}: \{{", line):
                return f"{rel}:{i + 1}"
    return "?"


def show_gates(root, minor, gates):
    out = []
    for gate in sorted(gates):
        entries, effective = gate_spec(root, gate, minor)
        if not entries:
            out.append(f"  gate {gate}: NOT DEFINED in this version (misspelled marker, or removed)")
            continue
        history = ", ".join(f"{v} {p}/{d}" for v, d, _, p in entries)
        out.append(f"  gate {gate}: {effective or 'not yet introduced'}  ({gate_location(root, gate)})  [{history}]")
    return out


def enclosing_gates(lines, index, known):
    """Feature gates named in the if/else blocks that enclose lines[index], up to its func."""
    gates = set()
    indent = len(lines[index]) - len(lines[index].lstrip("\t "))
    for j in range(index - 1, -1, -1):
        line = lines[j]
        if line.startswith("func "):
            break
        if not line.strip():
            continue
        level = len(line) - len(line.lstrip("\t "))
        if level < indent and line.rstrip().endswith("{"):
            gates |= {g for g in re.findall(r"features\.(\w+)", line) if g in known}
            indent = level
    return gates


def _func_body(lines, start):
    body, depth = [], 0
    for line in lines[start:]:
        body.append(line.strip())
        depth += line.count("{") - line.count("}")
        if depth <= 0 and len(body) > 1:
            break
    return body


def function_digest(root, name, depth=3):
    """(path:line, short digest) of Go func NAME under pkg/ or staging/, including the functions
    of the same package it calls (to DEPTH levels), so a change anywhere below it changes the digest."""
    for base in ("pkg", "staging/src/k8s.io"):
        found = subprocess.run(
            ["grep", "-rnE", rf"^func (\([^)]*\) )?{re.escape(name)}\(", base, "--include=*.go"],
            cwd=root, capture_output=True, text=True,
        ).stdout.splitlines()
        found = [f for f in found if "_test.go" not in f.split(":", 1)[0]]
        if not found:
            continue
        path, lineno, _ = found[0].split(":", 2)
        package_dir = (root / path).parent
        # Index the package's functions: name -> (lines, start).
        funcs = {}
        for go in package_dir.glob("*.go"):
            if go.name.endswith("_test.go"):
                continue
            lines = read(go)
            for i, line in enumerate(lines):
                m = re.match(r"^func (?:\([^)]*\) )?(\w+)\(", line)
                if m:
                    funcs.setdefault(m.group(1), (lines, i))
        seen, frontier, bodies = set(), [name], []
        for _ in range(depth):
            nxt = []
            for fn in frontier:
                if fn in seen or fn not in funcs:
                    continue
                seen.add(fn)
                body = _func_body(*funcs[fn])
                bodies.append("\n".join(body))
                nxt += re.findall(r"\b(\w+)\(", "\n".join(body[1:]))
            frontier = nxt
        digest = hashlib.sha256("\n\n".join(bodies).encode()).hexdigest()[:10]
        return f"{path}:{lineno}", f"{digest} ({len(seen)} funcs)"
    return None, None
