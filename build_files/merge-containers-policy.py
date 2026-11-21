#!/usr/bin/env python3
"""Merge ZeroOS entries into the containers signature policy of the base image.

Usage: merge-containers-policy.py FRAGMENT POLICY [POLICY...]

FRAGMENT maps registry scopes to policy requirements for the "docker" transport
(containers-policy.json(5)). The POLICY paths are listed in containers/image's order of
precedence; only the first one that exists is in effect, so the scopes are merged into that
file in place, keeping every entry the base image already ships (docs/os/03, OS-25).
Aurora and Fedora 45 ship no /etc/containers/policy.json: their policy is
/usr/share/containers/policy.json. Writing a new /etc copy instead would freeze a snapshot
of the vendor policy into mutable /etc. A scope that the base already defines differently
is an error, so a base change is noticed instead of silently overwritten. Runs at image
build time only; python3 is present because firewalld and Anaconda depend on it.
"""

import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2

    fragment = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    candidates = [Path(p) for p in argv[2:]]
    policy_path = next((p for p in candidates if p.is_file()), None)
    if policy_path is None:
        print(f"no containers policy found in: {', '.join(map(str, candidates))}", file=sys.stderr)
        return 1
    policy = json.loads(policy_path.read_text(encoding="utf-8"))

    docker = policy.setdefault("transports", {}).setdefault("docker", {})
    for scope, requirements in fragment.items():
        if scope in docker and docker[scope] != requirements:
            print(f"{policy_path}: {scope} already has a different policy", file=sys.stderr)
            return 1
        docker[scope] = requirements
        print(f"{policy_path}: policy for {scope} set")

    tmp = policy_path.with_name(policy_path.name + ".tmp")
    tmp.write_text(json.dumps(policy, indent=4) + "\n", encoding="utf-8")
    tmp.chmod(0o644)
    tmp.replace(policy_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
