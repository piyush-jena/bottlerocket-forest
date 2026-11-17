#!/usr/bin/env python3
"""rt-analyze.py - merge rettrace dumps and find constant return values and arguments.

Reads every <rt>/<scenario>/rettrace-*.json, merges the distinct values each function's
return value and arguments took (by the hash of their capped Debug output), and writes to
--out: rt-merged.json, and rt-constant.json with the functions whose return value, or one of
whose arguments, took a single known value in every call of every scenario.

Usage: rt-analyze.py --rt DIR --out DIR
"""
import argparse
import glob
import json
import os
from collections import defaultdict


def new_values():
    return {"seen": 0, "opaque": 0, "truncated": 0, "overflow": False, "distinct": {}}


def add(acc, v):
    acc["seen"] += v["seen"]
    acc["opaque"] += v["opaque"]
    acc["truncated"] += v["truncated"]
    acc["overflow"] |= v["overflow"]
    for example, count, h in v["distinct"]:
        acc["distinct"].setdefault(h, [example, 0])[1] += count


def single(v):
    # One known value, never cut short, in every recorded call.
    return (
        v is not None
        and v["seen"] > 0
        and v["opaque"] == 0
        and v["truncated"] == 0
        and not v["overflow"]
        and len(v["distinct"]) == 1
    )


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--rt", required=True)
    p.add_argument("--out", required=True)
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)

    merged = defaultdict(
        lambda: {"calls": 0, "scenarios": defaultdict(int), "ret": None, "args": {}}
    )
    for path in sorted(glob.glob(f"{a.rt}/*/rettrace-*.json")):
        scenario = os.path.basename(os.path.dirname(path))
        with open(path) as f:
            functions = json.load(f)["functions"]
        for label, fn in functions.items():
            m = merged[label]
            m["calls"] += fn["calls"]
            m["scenarios"][scenario] += fn["calls"]
            if fn["ret"] is not None:
                m["ret"] = m["ret"] or new_values()
                add(m["ret"], fn["ret"])
            for name, v in fn["args"].items():
                add(m["args"].setdefault(name, new_values()), v)

    constant = []
    for label, m in sorted(merged.items()):
        ret = m["ret"]
        entry = {
            "function": label,
            "calls": m["calls"],
            "scenarios": dict(m["scenarios"]),
            "constant_return": next(iter(ret["distinct"].values()))[0] if single(ret) else None,
            "return_values": len(ret["distinct"]) if ret else None,
            "constant_args": {
                name: next(iter(v["distinct"].values()))[0]
                for name, v in m["args"].items()
                if single(v)
            },
        }
        if entry["constant_return"] is not None or entry["constant_args"]:
            constant.append(entry)

    with open(f"{a.out}/rt-merged.json", "w") as f:
        json.dump(merged, f, indent=1, default=dict)
    with open(f"{a.out}/rt-constant.json", "w") as f:
        json.dump(constant, f, indent=1)
    print(f"functions traced: {len(merged)}; with a constant return value or argument: "
          f"{len(constant)}")


if __name__ == "__main__":
    main()
