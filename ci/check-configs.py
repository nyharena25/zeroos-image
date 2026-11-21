#!/usr/bin/env python3
"""Parse and sanity-check the configuration files of the image.

Run from the repository root: python3 ci/check-configs.py
Exit status 0 when every check passes, 1 otherwise. Needs PyYAML for the YAML file.
"""

import json
import re
import sys
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SYS = ROOT / "system_files"
REGISTRY = "ghcr.io/nyharena25/zeroos"
KEY_PATH = "/etc/pki/containers/zeroos-cosign.pub"

errors: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def lines(path: Path) -> list[str]:
    """Non-empty lines that are not comments."""
    text = path.read_text(encoding="utf-8").splitlines()
    return [line for line in text if line.strip() and not line.lstrip().startswith(("#", ";"))]


def main() -> int:
    policy = json.loads((ROOT / "build_files/containers-policy-zeroos.json").read_text(encoding="utf-8"))
    entry = policy.get(REGISTRY, [{}])[0]
    check(entry.get("type") == "sigstoreSigned", "policy: type is not sigstoreSigned")
    check(entry.get("keyPath") == KEY_PATH, f"policy: keyPath is not {KEY_PATH}")
    check(entry.get("signedIdentity") == {"type": "matchRepository"}, "policy: signedIdentity is not matchRepository")

    registries = yaml.safe_load((SYS / "etc/containers/registries.d/zeroos.yaml").read_text(encoding="utf-8"))
    check(registries["docker"][REGISTRY]["use-sigstore-attachments"] is True, "registries.d: sigstore attachments off")

    for toml_file in (SYS / "usr/lib/bootc/kargs.d").glob("*.toml"):
        kargs = tomllib.loads(toml_file.read_text(encoding="utf-8")).get("kargs")
        check(isinstance(kargs, list) and all(isinstance(k, str) for k in kargs), f"{toml_file.name}: kargs is not a list of strings")

    for zone in (SYS / "etc/firewalld/zones").glob("*.xml"):
        check(ET.parse(zone).getroot().tag == "zone", f"{zone.name}: root element is not <zone>")

    for preset in (SYS / "usr/lib/systemd/system-preset").glob("*.preset"):
        for line in lines(preset):
            check(re.fullmatch(r"(enable|disable) \S+", line) is not None, f"{preset.name}: bad line {line!r}")

    for conf in (SYS / "usr/lib/sysctl.d").glob("*.conf"):
        for line in lines(conf):
            check(re.fullmatch(r"[a-z0-9_.-]+ = \S+", line) is not None, f"{conf.name}: bad line {line!r}")

    for conf in (SYS / "usr/lib/modprobe.d").glob("*.conf"):
        for line in lines(conf):
            check(re.fullmatch(r"install [a-z0-9_-]+ /bin/false", line) is not None, f"{conf.name}: bad line {line!r}")

    build_sh = ROOT / "build_files/build.sh"
    check(build_sh.stat().st_mode & 0o111 != 0, "build_files/build.sh is not executable (the Containerfile runs it directly)")

    pub = (ROOT / "cosign.pub").read_text(encoding="utf-8")
    check(pub.startswith("PLACEHOLDER") or pub.startswith("-----BEGIN PUBLIC KEY-----"), "cosign.pub: neither placeholder nor PEM")
    check("PRIVATE KEY" not in pub, "cosign.pub: contains a private key")

    for path in [ROOT / "Containerfile", *ROOT.glob("build_files/*"), *SYS.rglob("*")]:
        if path.is_file():
            check("<owner>" not in path.read_text(encoding="utf-8"), f"{path.relative_to(ROOT)}: unfilled <owner>")

    for message in errors:
        print(f"error: {message}", file=sys.stderr)
    print(f"check-configs: {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
