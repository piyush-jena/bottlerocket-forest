#!/usr/bin/env python3
"""cov-analyze.py - per-function, per-region and per-line coverage of chosen Rust files.

Merges the LLVM profiles of every scenario directory under --cov (except `unit` and `junk`),
of all scenarios together (e2e), and of the unit tests (--cov/unit), then writes to --out:

  <scenario>.profdata, e2e.profdata, unit.profdata
  cov-functions.json  each function's call count end to end, per scenario and in unit tests
  cov-regions.json    never-executed regions inside functions that did run end to end
  uncovered/<file>    never-run lines in contiguous blocks, tagged by unit-test reach
  annotated/<file>    `llvm-cov show` listing
  report.txt          per-file `llvm-cov report` summary

Usage: cov-analyze.py --src ROOT --cov DIR --out DIR --object BIN [--object BIN]...
                      [--unit-object BIN]... FILE...
FILEs are relative to ROOT. LLVM_BIN overrides the toolchain's llvm-tools directory.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

LINE = re.compile(r"^\s*(\d+)\|\s*([0-9.kMGTPE]*)\|")


def sh(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw).stdout


def llvm_bin(src):
    if os.environ.get("LLVM_BIN"):
        return os.environ["LLVM_BIN"]
    sysroot = sh("rustc", "--print", "sysroot", cwd=src).strip()
    host = re.search(r"^host: (\S+)", sh("rustc", "-vV", cwd=src), re.M).group(1)
    path = f"{sysroot}/lib/rustlib/{host}/bin"
    if not os.path.exists(f"{path}/llvm-cov"):
        sys.exit(f"no llvm-cov in {path}; run `rustup component add llvm-tools` in {src}")
    return path


class Cov:
    def __init__(self, llvm, src, files, out):
        self.llvm, self.src, self.files, self.out = llvm, src, set(files), out

    def merge(self, name, profraws):
        path = f"{self.out}/{name}.profdata"
        sh(f"{self.llvm}/llvm-profdata", "merge", "-sparse", *profraws, "-o", path)
        return path

    def objects(self, objects):
        return [objects[0]] + [a for o in objects[1:] for a in ("-object", o)]

    def functions(self, profdata, objects):
        """(file, first line) -> [name, count, {region: count}] for the chosen files; the
        instantiations of a generic function are combined."""
        data = json.loads(
            sh(f"{self.llvm}/llvm-cov", "export", "-instr-profile", profdata, *self.objects(objects))
        )
        funcs = data["data"][0]["functions"]
        names = sh("rustfilt", input="".join(f["name"] + "\n" for f in funcs)).splitlines()
        out = {}
        for f, name in zip(funcs, names):
            path = os.path.relpath(f["filenames"][0], self.src)
            if path not in self.files:
                continue
            # Code regions (kind 0) in the function's own file (file id 0).
            regions = [r for r in f["regions"] if r[5] == 0 and r[7] == 0]
            if not regions:
                continue
            key = (path, min(r[0] for r in regions))
            entry = out.setdefault(key, [name, 0, {}])
            entry[1] += f["count"]
            for r in regions:
                entry[2][tuple(r[:4])] = entry[2].get(tuple(r[:4]), 0) + r[4]
        return out

    def show(self, profdata, objects, path, *extra):
        return sh(
            f"{self.llvm}/llvm-cov", "show", "-instr-profile", profdata, *self.objects(objects),
            "-Xdemangler=rustfilt", "-show-instantiations=false", *extra,
            os.path.join(self.src, path),
        )

    def line_counts(self, profdata, objects, path):
        counts = {}
        for line in self.show(profdata, objects, path).split("\n"):
            m = LINE.match(line)
            if m and m.group(2):
                counts[int(m.group(1))] = m.group(2) != "0"
        return counts


def uncovered(path, source, e2e, unit):
    """Never-run lines in contiguous blocks; `U` marks lines the unit tests run."""
    out = [f"===== {path}"]
    blocks = []
    for n in sorted(n for n, hit in e2e.items() if not hit):
        if blocks and n == blocks[-1][-1] + 1:
            blocks[-1].append(n)
        else:
            blocks.append([n])
    for block in blocks:
        hit = [n for n in block if unit.get(n)]
        tag = "unit:all" if len(hit) == len(block) else "unit:some" if hit else "unit:none"
        out.append(f"--- L{block[0]}-{block[-1]} ({len(block)} lines, {tag})")
        out += [f"  {n:5} {'U' if n in hit else ' '} {source[n - 1]}" for n in block]
    return "\n".join(out) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--cov", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--object", action="append", required=True)
    p.add_argument("--unit-object", action="append", default=[])
    p.add_argument("files", nargs="+")
    a = p.parse_args()
    src = os.path.abspath(a.src)
    for d in ("annotated", "uncovered"):
        os.makedirs(f"{a.out}/{d}", exist_ok=True)
    cov = Cov(llvm_bin(src), src, a.files, a.out)

    scenarios = sorted(
        os.path.basename(d)
        for d in glob.glob(f"{a.cov}/*")
        if os.path.basename(d) not in ("unit", "junk") and glob.glob(f"{d}/*.profraw")
    )
    if not scenarios:
        sys.exit(f"no scenario directories with .profraw files under {a.cov}")
    per, all_raw = {}, []
    for s in scenarios:
        raws = glob.glob(f"{a.cov}/{s}/*.profraw")
        all_raw += raws
        per[s] = cov.functions(cov.merge(s, raws), a.object)
    e2e_prof = cov.merge("e2e", all_raw)
    e2e = cov.functions(e2e_prof, a.object)
    unit_raw = glob.glob(f"{a.cov}/unit/*.profraw")
    unit_prof = cov.merge("unit", unit_raw) if unit_raw and a.unit_object else None
    unit = cov.functions(unit_prof, a.unit_object) if unit_prof else {}

    rows = []
    for key in sorted(set(e2e) | set(unit)):
        rows.append({
            "file": key[0],
            "line": key[1],
            "name": (e2e.get(key) or unit.get(key))[0],
            "e2e": e2e[key][1] if key in e2e else None,
            "scenarios": {s: per[s][key][1] if key in per[s] else None for s in scenarios},
            "unit": unit[key][1] if key in unit else None,
        })
    with open(f"{a.out}/cov-functions.json", "w") as f:
        json.dump({"scenarios": scenarios, "functions": rows}, f, indent=1)

    gaps = []
    for key, (name, count, regions) in sorted(e2e.items()):
        if count == 0:
            continue
        unit_regions = unit.get(key, [None, 0, {}])[2]
        gaps += [
            {"file": key[0], "function": name, "lines": [r[0], r[2]], "unit": unit_regions.get(r)}
            for r, n in sorted(regions.items())
            if n == 0
        ]
    with open(f"{a.out}/cov-regions.json", "w") as f:
        json.dump(gaps, f, indent=1)

    missing = []
    for path in a.files:
        flat = path.replace("/", "__") + ".txt"
        e2e_lines = cov.line_counts(e2e_prof, a.object, path)
        if not e2e_lines:
            missing.append(path)
            continue
        unit_lines = cov.line_counts(unit_prof, a.unit_object, path) if unit_prof else {}
        with open(os.path.join(src, path)) as f:
            source = f.read().split("\n")
        with open(f"{a.out}/uncovered/{flat}", "w") as f:
            f.write(uncovered(path, source, e2e_lines, unit_lines))
        with open(f"{a.out}/annotated/{flat}", "w") as f:
            f.write(cov.show(e2e_prof, a.object, path, "-show-line-counts-or-regions"))
    report = sh(
        f"{cov.llvm}/llvm-cov", "report", "-instr-profile", e2e_prof, *cov.objects(a.object),
        *(os.path.join(src, p) for p in a.files if p not in missing),
    )
    with open(f"{a.out}/report.txt", "w") as f:
        f.write(report)

    never = sum(1 for r in rows if not r["e2e"])
    print(f"scenarios: {', '.join(scenarios)}; unit tests: {'yes' if unit_prof else 'no'}")
    print(f"functions: {len(rows)}; never run end to end: {never}; "
          f"never-run regions in functions that ran: {len(gaps)}")
    for path in missing:
        print(f"no coverage data for {path}: not instrumented, or in none of the objects")


if __name__ == "__main__":
    main()
