#!/usr/bin/env python3
"""Make counterfactual kubelet configs: rendered files with YAML merged in, for kubelet-validate.sh.

Usage: counterfactual.py RENDER_DIR OUT_DIR SNIPPET [MINOR...]

  RENDER_DIR  output of render-template.sh --kubelet-config
  OUT_DIR     where to write the modified copies (same file names; RENDER_DIR is not touched)
  SNIPPET     a YAML file, or inline YAML such as 'crashLoopBackOff: {maxContainerRestartPeriod: 60s}'
              or 'featureGates: {KubeletEnsureSecretPulledImages: true}'
  MINOR       versions to copy, like 1.34 (default: every rendered file)

Maps are merged key by key (a featureGates entry is added next to the existing ones); other
values replace. Use it to answer "what would this kubelet do if the template rendered X here?":
for a version the spec leaves out, a FATAL result is the evidence; IGNORED means the field does not
exist in that version.
"""

import sys
from pathlib import Path

import yaml


def merge(base, extra):
    for key, value in extra.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value
    return base


def main(argv):
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    render_dir, out_dir, snippet = Path(argv[1]), Path(argv[2]), argv[3]
    extra = yaml.safe_load(Path(snippet).read_text() if Path(snippet).is_file() else snippet)
    if not isinstance(extra, dict):
        print("SNIPPET must be a YAML mapping", file=sys.stderr)
        return 2
    minors = argv[4:] or sorted(p.name.split("__")[0].removeprefix("kubernetes-")
                                for p in render_dir.glob("kubernetes-1.*__kubelet-config"))
    out_dir.mkdir(parents=True, exist_ok=True)
    for minor in minors:
        name = f"kubernetes-{minor}__kubelet-config"
        source = render_dir / name
        if not source.exists():
            print(f"missing {source}", file=sys.stderr)
            return 1
        config = yaml.safe_load(source.read_text()) or {}
        merged = merge(config, yaml.safe_load(yaml.safe_dump(extra)))
        (out_dir / name).write_text(yaml.safe_dump(merged, sort_keys=False))
    print(out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
