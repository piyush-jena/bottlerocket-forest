#!/usr/bin/env python3
"""Find settings that drifted between core-kit templates that should agree.

Usage:
  template-drift.py [kubernetes|containerd] [--key PREFIX] [--matrix]

kubernetes (default): compares every file in packages/kubernetes-1.* across versions.
  DRIFT     a key rendered in 1.N but not in 1.N+1 (newer versions should never lose a setting)
  PATH      a key rendered at a different YAML path or flag in different versions
  MISSING   a key in a template (kubelet-env) but not in its variant (kubelet-env-nvidia)
containerd: compares containerd-config-toml_*k8s* templates across containerd-* packages and,
  within each package, across template flavors (for example the NVIDIA variant).
  MISSING   a key present in some k8s templates but not others

--key limits the report to keys starting with PREFIX (default: settings.kubernetes.).
--matrix also prints the key x version presence table.
Exits 1 when anything is flagged, so it can gate a change.

Env: CORE_KIT (default ./kits/bottlerocket-core-kit).
"""

import os
import re
import sys
from collections import defaultdict
from pathlib import Path

CORE_KIT = Path(os.environ.get("CORE_KIT", "./kits/bottlerocket-core-kit"))
KEY_RE = re.compile(r"settings\.[A-Za-z0-9_.\[\]-]+")


def version_key(name):
    return [int(x) for x in re.findall(r"\d+", name)]


def rendered_at(lines, index):
    """Describe where line `index` renders: a YAML path, a CLI flag, or a TOML key."""
    line = lines[index]
    flag = re.search(r"(--[\w-]+)=", line)
    if flag:
        return flag.group(1)
    own = re.match(r"^(\s*)([A-Za-z_][\w.-]*)\s*[:=]", line)
    if not own:
        # A value line inside a block: attribute it to the nearest key line above it.
        for j in range(index - 1, -1, -1):
            if re.match(r"^\s*[A-Za-z_][\w.-]*\s*[:=]", lines[j]) and "{{" not in lines[j].split(":")[0]:
                return rendered_at(lines, j) + "[]"
        return "?"
    indent, name = len(own.group(1)), own.group(2)
    path = [name]
    for j in range(index - 1, -1, -1):
        prev = lines[j]
        if prev.lstrip().startswith("{{") or not prev.strip():
            continue
        m = re.match(r"^(\s*)([A-Za-z_][\w.-]*)\s*:", prev)
        if m and len(m.group(1)) < indent:
            path.insert(0, m.group(2))
            indent = len(m.group(1))
            if indent == 0:
                break
    return ".".join(path)


def scan(files, prefix):
    """Return {key: set(rendered_at)} for keys under prefix referenced in files."""
    found = defaultdict(set)
    for path in files:
        try:
            lines = path.read_text().splitlines()
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        for i, line in enumerate(lines):
            for key in KEY_RE.findall(line):
                if key.startswith(prefix):
                    found[key].add(f"{path.name}:{rendered_at(lines, i)}" if "{{#" not in line else f"{path.name}:(condition)")
    return found


def kubernetes(prefix, matrix):
    pkgs = sorted((p for p in (CORE_KIT / "packages").glob("kubernetes-1.*") if p.is_dir()),
                  key=lambda p: version_key(p.name))
    per = {p.name: scan(sorted(f for f in p.iterdir() if f.is_file()), prefix) for p in pkgs}
    keys = sorted(set().union(*per.values()))
    flagged = 0
    if matrix:
        names = [p.name.removeprefix("kubernetes-") for p in pkgs]
        print(f"{'key':70} " + " ".join(f"{n:>5}" for n in names))
        for key in keys:
            print(f"{key:70} " + " ".join(f"{'x' if key in per[p.name] else '.':>5}" for p in pkgs))
        print()
    for a, b in zip(pkgs, pkgs[1:]):
        for key in keys:
            if key in per[a.name] and key not in per[b.name]:
                print(f"DRIFT  {key}: rendered in {a.name}, missing in {b.name}")
                flagged += 1
    for key in keys:
        shapes = {}
        for p in pkgs:
            # Compare where the key renders, not which file renders it (variants add files).
            spots = {s.split(":", 1)[1] for s in per[p.name].get(key, set()) if not s.endswith("(condition)")}
            if spots:
                shapes[p.name] = tuple(sorted(spots))
        if len(set(shapes.values())) > 1:
            flagged += 1
            print(f"PATH   {key}:")
            for name, shape in shapes.items():
                print(f"         {name}: {', '.join(shape)}")
    # Variant files (kubelet-env-nvidia next to kubelet-env) must render the same keys.
    for p in pkgs:
        files = sorted(f for f in p.iterdir() if f.is_file())
        for base in files:
            for variant in (f for f in files if f.name.startswith(base.name + "-")):
                missing = set(scan([base], prefix)) - set(scan([variant], prefix))
                for key in sorted(missing):
                    print(f"MISSING {key}: in {p.name}/{base.name}, not in {variant.name}")
                    flagged += 1
    return flagged


def containerd(prefix, matrix):
    flagged = 0
    pkgs = sorted((p for p in (CORE_KIT / "packages").glob("containerd-*") if p.is_dir()),
                  key=lambda p: version_key(p.name))
    union_by_pkg = {}
    for p in pkgs:
        templates = sorted(f for f in p.iterdir() if f.is_file() and f.name.startswith("containerd-config-toml_") and "k8s" in f.name)
        per_file = {f.name: set(scan([f], prefix)) for f in templates}
        union = set().union(*per_file.values()) if per_file else set()
        union_by_pkg[p.name] = union
        if matrix:
            print(f"{p.name}: " + ", ".join(f"{n} ({len(k)} keys)" for n, k in per_file.items()))
        for name, keys in per_file.items():
            for key in sorted(union - keys):
                print(f"MISSING {key}: in other k8s templates of {p.name}, not in {name}")
                flagged += 1
    for a, b in zip(pkgs, pkgs[1:]):
        for key in sorted(union_by_pkg[a.name] - union_by_pkg[b.name]):
            print(f"DRIFT  {key}: rendered in {a.name}, missing in {b.name}")
            flagged += 1
    return flagged


def main(argv):
    args = argv[1:]
    if "-h" in args or "--help" in args:
        print(__doc__)
        return 0
    matrix = "--matrix" in args
    prefix = "settings.kubernetes."
    if "--key" in args:
        prefix = args[args.index("--key") + 1]
    mode = next((a for a in args if a in ("kubernetes", "containerd")), "kubernetes")
    if not (CORE_KIT / "packages").is_dir():
        print(f"core-kit not found at {CORE_KIT} (set CORE_KIT)", file=sys.stderr)
        return 2
    flagged = kubernetes(prefix, matrix) if mode == "kubernetes" else containerd(prefix, matrix)
    print(f"\n{flagged} issue(s) flagged" if flagged else "no drift found")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
