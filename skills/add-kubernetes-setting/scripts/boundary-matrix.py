#!/usr/bin/env python3
"""Differential test of a setting: the Bottlerocket model against each kubelet version, value by value.

Usage: boundary-matrix.py --setting KEY --kubelet-path PATH --values FILE [--base FILE]... [--out DIR] [MINOR...]

  --setting KEY       settings.kubernetes key, e.g. max-container-restart-period
  --kubelet-path PATH dotted KubeletConfiguration path it renders to, e.g. crashLoopBackOff.maxContainerRestartPeriod
  --values FILE       one JSON value per line, e.g. "1s", 300, true, ["a", "b"]; blank and # lines skipped
  --base FILE         settings (TOML user data or JSON) applied to every case, e.g. a field this one
                      depends on; repeatable
  --out DIR           work directory (default: a new temp dir)
  MINOR               versions to check, like 1.35 (default: every kubernetes-1.X package)

For each value: the model verdict (render-template.sh exits 0 = accepted, 3 = rejected by the API),
then per version whether the template rendered the value, and kubelet's verdict from
kubelet-validate.sh (OK, IGNORED, FATAL). Where the value is not rendered, or the model rejects it,
the value is forced in with counterfactual.py and the verdict is shown in brackets: it tells whether
leaving the version out is necessary and whether the model is stricter than kubelet.

BUG  the model accepts a value that some rendering version's kubelet does not accept as OK.
Exit status 1 if any BUG is found. The value is forced in as-is; for settings whose template
transforms the value (lists into maps, for example), read the bracketed verdicts with care.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

SCRIPTS = Path(__file__).resolve().parent


def run(*args):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True)


def verdicts(directory, minors):
    """{minor: 'OK' | 'IGNORED' | 'FATAL' | '?'} from kubelet-validate.sh."""
    out = run(SCRIPTS / "kubelet-validate.sh", directory, *minors).stdout
    found = {}
    for line in out.splitlines():
        if "__kubelet-config: " not in line:
            continue
        name, result = line.split("__kubelet-config: ", 1)
        minor = name.removeprefix("kubernetes-")
        kind = result.split(" ", 1)[0]
        # Keep the worst result when a file has several lines (IGNORED and FATAL).
        if found.get(minor) != "FATAL":
            found[minor] = kind if kind in ("OK", "IGNORED", "FATAL") else "?"
    return found


def path_value(config_file, path):
    doc = yaml.safe_load(Path(config_file).read_text()) or {}
    for part in path.split("."):
        if not isinstance(doc, dict) or part not in doc:
            return None
        doc = doc[part]
    return doc


def nested(path, value):
    out = value
    for part in reversed(path.split(".")):
        out = {part: out}
    return out


def main(argv):
    args = argv[1:]
    opts = {"--base": []}
    minors = []
    while args:
        a = args.pop(0)
        if a in ("--setting", "--kubelet-path", "--values", "--out"):
            opts[a] = args.pop(0)
        elif a == "--base":
            opts["--base"].append(args.pop(0))
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            minors.append(a)
    if not all(k in opts for k in ("--setting", "--kubelet-path", "--values")):
        print(__doc__, file=sys.stderr)
        return 2
    work = Path(opts.get("--out") or tempfile.mkdtemp(prefix="boundary-matrix-"))
    work.mkdir(parents=True, exist_ok=True)
    key, kpath = opts["--setting"], opts["--kubelet-path"]
    base_args = [x for b in opts["--base"] for x in ("--settings", b)]

    # A render without the setting, as the base for counterfactuals.
    plain = work / "plain"
    result = run(SCRIPTS / "render-template.sh", *base_args, "--out", plain, "--kubelet-config", *minors)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        return 1
    minors = minors or sorted(p.name.split("__")[0].removeprefix("kubernetes-")
                              for p in plain.glob("kubernetes-1.*__kubelet-config"))

    values = [l for l in Path(opts["--values"]).read_text().splitlines() if l.strip() and not l.startswith("#")]
    bugs = 0
    print("value\tmodel\t" + "\t".join(minors))
    for i, raw in enumerate(values):
        value = json.loads(raw)
        case = work / f"case-{i}"
        case.mkdir(exist_ok=True)
        settings = case / "settings.json"
        settings.write_text(json.dumps({"settings": {"kubernetes": {key: value}}}))
        rendered = case / "render"
        r = run(SCRIPTS / "render-template.sh", *base_args, "--settings", settings, "--out", rendered,
                "--kubelet-config", *minors)
        accepted = r.returncode == 0
        if r.returncode not in (0, 3):
            print(f"{raw}\terror\t{r.stderr.strip()[:80]}")
            continue
        forced = case / "forced"
        run(sys.executable, "-I", SCRIPTS / "counterfactual.py", plain, forced, yaml.safe_dump(nested(kpath, value)),
            *minors)
        forced_verdicts = verdicts(forced, minors)
        rendered_verdicts = verdicts(rendered, minors) if accepted else {}
        cells = []
        for m in minors:
            is_rendered = accepted and path_value(rendered / f"kubernetes-{m}__kubelet-config", kpath) is not None
            if is_rendered:
                verdict = rendered_verdicts.get(m, "?")
                if verdict != "OK":
                    bugs += 1
                    verdict = f"BUG:{verdict}"
                cells.append(f"R {verdict}")
            else:
                cells.append(f"- [{forced_verdicts.get(m, '?')}]")
        print(f"{raw}\t{'accept' if accepted else 'reject'}\t" + "\t".join(cells))
    print(f"\nR = rendered, - = not rendered; [..] = kubelet verdict with the value forced in. Work dir: {work}")
    print(f"{bugs} BUG(s)" if bugs else "no model/kubelet disagreement on rendered versions")
    return 1 if bugs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
