#!/usr/bin/env python3
"""Parse Twoliter.toml for the SDK image and pull it via Docker.

Usage:
    python3 pull-sdk.py <path-to-Twoliter.toml>

Outputs the fully-qualified SDK image reference on stdout, e.g.:
    public.ecr.aws/bottlerocket/bottlerocket-sdk:v0.70.0

Also prints the lowest Go version available in the SDK on a second line, e.g.:
    1.24
"""
import subprocess
import sys

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore[no-redef]


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <Twoliter.toml>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = tomllib.load(f)

    registry = data["vendor"]["bottlerocket"]["registry"]
    name = data["sdk"]["name"]
    version = data["sdk"]["version"]
    image = f"{registry}/{name}:v{version}"

    subprocess.run(["docker", "pull", image], check=True,
                   stdout=sys.stderr, stderr=sys.stderr)

    result = subprocess.run(
        ["docker", "run", "--rm", image, "bash", "-c",
         r'ls -d /usr/libexec/go-* | sed "s|.*/go-||" | sort -V | head -1'],
        capture_output=True, text=True, check=True,
    )
    default_go = result.stdout.strip()

    # stdout: line 1 = image, line 2 = default go version
    print(image)
    print(default_go)


if __name__ == "__main__":
    main()
