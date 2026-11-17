#!/usr/bin/env python3
"""Point a repo's settings-sdk dependencies at an unreleased local settings-sdk commit (dev only).

Usage: use-local-settings-sdk.py SOURCES_DIR SDK_REPO [REV]

  SOURCES_DIR  the cargo workspace to rewrite: kits/bottlerocket-core-kit/sources or bottlerocket/sources
  SDK_REPO     a settings-sdk git checkout holding the commit (a normal clone, not a worktree)
  REV          commit to use (default: HEAD of SDK_REPO)

Rewrites every [workspace.dependencies.X] that uses the upstream settings-sdk git URL with a
bottlerocket-settings-models-v* tag: git -> file://SDK_REPO, tag -> rev, version -> the crate's
version at REV. Adds the file URL to deny.toml allow-git (the variant build runs cargo-deny) and
refreshes Cargo.lock for just those crates.

Why not [patch] or a path dependency: twoliter vendors crates on the host with
`cargo vendor --locked` and builds with --network=none, so a git source that cargo can vendor is
the only override that reaches the build container unchanged.

The result is a DO-NOT-MERGE change: commit it separately so it can be dropped once the real
settings-models tag exists, and replace it with the tag bump.
"""

import re
import subprocess
import sys
from pathlib import Path

UPSTREAM = "https://github.com/bottlerocket-os/bottlerocket-settings-sdk"
BLOCK = re.compile(r"(?ms)^\[workspace\.dependencies\.([\w-]+)\]\n(.*?)(?=^\[|\Z)")


def sh(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def crate_versions(sdk, rev):
    """Map crate name -> version for every Cargo.toml in the SDK at rev."""
    versions = {}
    for path in sh("git", "ls-tree", "-r", "--name-only", rev, cwd=sdk).splitlines():
        if not path.endswith("Cargo.toml"):
            continue
        text = sh("git", "show", f"{rev}:{path}", cwd=sdk)
        name = re.search(r'(?m)^name\s*=\s*"([^"]+)"', text)
        version = re.search(r'(?m)^version\s*=\s*"([^"]+)"', text)
        if name and version:
            versions[name.group(1)] = version.group(1)
    return versions


def main(argv):
    if len(argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    sources, sdk = Path(argv[1]).resolve(), Path(argv[2]).resolve()
    rev = sh("git", "rev-parse", argv[3] if len(argv) == 4 else "HEAD", cwd=sdk)
    url = f"file://{sdk}"
    versions = crate_versions(sdk, rev)

    manifest = sources / "Cargo.toml"
    text = manifest.read_text()
    changed = []

    def rewrite(m):
        name, body = m.group(1), m.group(2)
        if f'git = "{UPSTREAM}"' not in body or not re.search(r'tag = "bottlerocket-settings-models-v', body):
            return m.group(0)
        if name not in versions:
            raise SystemExit(f"{name}: not found in {sdk} at {rev}")
        body = body.replace(f'git = "{UPSTREAM}"', f'git = "{url}"')
        body = re.sub(r'tag = "[^"]+"', f'rev = "{rev}"', body)
        body = re.sub(r'version = "[^"]+"', f'version = "{versions[name]}"', body)
        changed.append(name)
        return f"[workspace.dependencies.{name}]\n{body}"

    text = BLOCK.sub(rewrite, text)
    if not changed:
        print(f"no settings-models tag dependencies found in {manifest}", file=sys.stderr)
        return 1
    manifest.write_text(text)

    deny = sources / "deny.toml"
    if deny.exists():
        deny_text = deny.read_text()
        if url not in deny_text:
            deny_text = re.sub(r'(allow-git = \[\n)', rf'\1    "{url}",  # DO NOT MERGE: local settings-sdk\n', deny_text, count=1)
            deny.write_text(deny_text)

    args = ["cargo", "update", "--manifest-path", str(manifest)]
    for name in changed:
        args += ["-p", name]
    subprocess.run(args, check=True)

    print(f"Pointed {', '.join(changed)} at {url} rev {rev}")
    print(sh("git", "diff", "--stat", "--", ".", cwd=sources))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
