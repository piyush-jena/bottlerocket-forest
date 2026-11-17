#!/usr/bin/env python3
"""Check every key a core-kit kubelet-config template renders against that version's upstream types.

Usage: kubelet-config-lint.py [MINOR...] [--template PATH]

For each packages/kubernetes-1.X/kubelet-config (or --template, checked against every MINOR given):
  UNKNOWN  a YAML path that is not a field of KubeletConfiguration v1beta1 in that version.
           kubelet decodes leniently and ignores it with only a log warning, so it silently does nothing.
  SCALAR   children rendered under a field whose upstream type is not a struct or map.
  GATED    a field that needs a feature gate (named by a +featureGate marker, or enclosing the
           field's validation) that is off by default in that version.
           Unless the template also enables the gate, kubelet either rejects the field (run
           kubelet-validate.sh to see which) or silently ignores it.
  GATE     a featureGates entry that version does not define (kubelet refuses to start),
           or one locked to a different value (kubelet refuses to start).
Feature gates set by the template are listed with their maturity so per-version intent is visible.
Exits 1 when anything is flagged.

Both branches of every {{#if}}/{{else}} are checked, because the parser ignores handlebars lines.
Env: CORE_KIT, BR_SRC_CACHE (see fetch-package-source.sh).
"""

import re
import sys
from pathlib import Path

# Scripts run with python3 -I, which leaves the script directory off sys.path. Do not write
# __pycache__ into the skill directory.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from k8ssrc import (CORE_KIT, TYPES_V1BETA1, all_gates, enclosing_gates, fetch,  # noqa: E402
                    gate_markers, gate_spec, packages, read, struct_fields)

VALIDATION_DIR = "pkg/kubelet/apis/config/validation"


KEY_LINE = re.compile(r"^([A-Za-z_][\w.\-/]*|\"[^\"]*\")\s*:\s*(.*)$")


def yaml_paths(lines):
    """Yield (lineno, path_parts, value) for mapping keys, skipping front matter and handlebars lines.

    A list element is the path part "[]", so "reservedMemory:\\n- numaNode: 0" yields
    ["reservedMemory", "[]", "numaNode"].
    """
    body = lines.index("+++") + 1 if "+++" in lines else 0
    stack = []  # (indent, key)
    for i in range(body, len(lines)):
        line = lines[i]
        stripped = line.strip()
        if not stripped or stripped == "---" or stripped.startswith(("{{", "#")):
            continue
        indent = len(line) - len(line.lstrip())
        if stripped.startswith("- "):
            # A sequence may sit at the same indent as its parent key; a new item closes the last one.
            while stack and (stack[-1][0] > indent or (stack[-1][0] == indent and stack[-1][1] == "[]")):
                stack.pop()
            stack.append((indent, "[]"))
            stripped, indent = stripped[2:].lstrip(), indent + 2
        m = KEY_LINE.match(stripped)
        if not m or "{{" in m.group(1):
            continue
        while stack and stack[-1][0] >= indent:
            stack.pop()
        stack.append((indent, m.group(1).strip('"')))
        yield i + 1, [k for _, k in stack], m.group(2)


def validation_gates(root, known):
    """Map Go field name -> gates whose enabled-check encloses validation of that field."""
    gates = {}
    for vfile in sorted((root / VALIDATION_DIR).glob("validation*.go")):
        if vfile.name.endswith("_test.go"):
            continue
        lines = read(vfile)
        for i, line in enumerate(lines):
            for name in re.findall(r"\.([A-Z]\w*)\b", line):
                found = enclosing_gates(lines, i, known)
                if found:
                    gates.setdefault(name, set()).update(found)
    return gates


def walk(type_lines, parts, comments=None):
    """Resolve parts from KubeletConfiguration. Return (status, detail).

    status: ok | map | list | external | unknown | scalar
    If comments is a list, the doc comment of every resolved field is appended to it.
    """
    struct = "KubeletConfiguration"
    parts = list(parts)
    n = 0
    comments = comments if comments is not None else []
    while n < len(parts):
        part = parts[n]
        fields = {f[2]: f for f in struct_fields(type_lines, struct)}
        if part not in fields:
            return "unknown", f"'{part}' is not a field of {struct}"
        go_type = fields[part][1]
        comments.append((fields[part][0], fields[part][3]))
        rest = parts[n + 1:]
        n += 1
        if go_type.startswith("map["):
            return "map", go_type
        if go_type.startswith("[]"):
            if not rest:
                return "list", go_type
            if rest[0] != "[]":
                return "scalar", f"{part} is {go_type}"
            n += 1
            go_type = go_type[2:]
            if len(parts) == n:
                return "list", go_type
        name = go_type.lstrip("*")
        rest = parts[n:]
        if "." in name:  # metav1.Duration, logsapi.LoggingConfiguration, ...
            scalarish = name in ("metav1.Duration", "resource.Quantity")
            if rest and scalarish:
                return "scalar", f"{part} is {go_type}"
            return ("ok" if scalarish else "external"), go_type
        if not any(re.match(rf"^type {name} struct \{{", l) for l in type_lines):
            if rest:
                return "scalar", f"{part} is {go_type}"
            return "ok", go_type
        struct = name
    return "ok", struct


def lint(template, pkg, version, root):
    minor = ".".join(version.split(".")[:2])
    type_lines = read(root / TYPES_V1BETA1)
    lines = template.read_text().splitlines()
    gates = all_gates(root)
    vgates = validation_gates(root, gates)
    problems, notes = [], []
    for lineno, parts, value in yaml_paths(lines):
        if parts[:1] in (["kind"], ["apiVersion"]):
            continue
        if parts[0] == "featureGates" and len(parts) == 2:
            gate = parts[1]
            if gate not in gates:
                problems.append(f"GATE    {template.name}:{lineno} featureGates.{gate}: not defined in {version}")
                continue
            _, effective = gate_spec(root, gate, minor)
            if effective and "locked" in effective and f"default={value.strip()}" not in effective:
                problems.append(f"GATE    {template.name}:{lineno} featureGates.{gate}={value}: {effective}")
            notes.append(f"gate    featureGates.{gate}={value.strip()}  ({effective})")
            continue
        comments = []
        status, detail = walk(type_lines, parts, comments)
        needed = set()
        if comments:
            go_name, comment = comments[-1]
            # Gates named by +featureGate markers, and gates whose enabled-check encloses the
            # field's validation (many gated fields have no marker).
            needed = gate_markers(comment) | vgates.get(go_name, set())
        for gate in sorted(needed):
            _, effective = gate_spec(root, gate, minor)
            if gate in gates and (effective is None or "default=false" in effective):
                problems.append(f"GATED   {template.name}:{lineno} {'.'.join(parts)}: needs feature gate {gate}, "
                                f"which is {effective or 'not available'} here; kubelet rejects or ignores it")
        if status == "unknown":
            problems.append(f"UNKNOWN {template.name}:{lineno} {'.'.join(parts)}: {detail}")
        elif status == "scalar":
            problems.append(f"SCALAR  {template.name}:{lineno} {'.'.join(parts)}: {detail}")
    print(f"== {pkg} ({version}) {template}")
    for line in problems + notes:
        print(f"  {line}")
    if not problems:
        print("  every rendered path exists upstream")
    return len(problems)


def main(argv):
    args = argv[1:]
    if "-h" in args or "--help" in args:
        print(__doc__)
        return 0
    template = None
    if "--template" in args:
        i = args.index("--template")
        template = Path(args[i + 1])
        del args[i:i + 2]
    rows = fetch(packages("kubernetes-", args))
    flagged = 0
    for pkg, version, root in rows:
        path = template or CORE_KIT / "packages" / pkg / "kubelet-config"
        flagged += lint(path, pkg, version, root)
    print(f"\n{flagged} issue(s) flagged" if flagged else "\nno issues")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
