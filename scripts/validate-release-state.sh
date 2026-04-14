#!/usr/bin/env bash
#
# Validate local release metadata that CI relies on.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_ROOT}"

python3 - <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path.cwd()

manifest = json.loads((root / ".release-please-manifest.json").read_text())
config = json.loads((root / "release-please-config.json").read_text())
version_file = (root / "VERSION").read_text().strip()
roulette_text = (root / "roulette").read_text()

match = re.search(r'^VERSION="([^"]+)"\s+# x-release-please-version$', roulette_text, re.MULTILINE)
if not match:
    print("release-check: missing release-please version marker in roulette", file=sys.stderr)
    sys.exit(1)

roulette_version = match.group(1)
manifest_version = manifest.get(".")
extra_files = config.get("packages", {}).get(".", {}).get("extra-files", [])
extra_paths = {entry.get("path") for entry in extra_files}

expected_paths = {"roulette", "VERSION"}
missing_paths = sorted(expected_paths - extra_paths)
if missing_paths:
    print(f"release-check: release-please config missing tracked files: {', '.join(missing_paths)}", file=sys.stderr)
    sys.exit(1)

versions = {
    "VERSION": version_file,
    "roulette": roulette_version,
    ".release-please-manifest.json": manifest_version,
}

if len(set(versions.values())) != 1:
    print("release-check: version mismatch detected", file=sys.stderr)
    for name, value in versions.items():
      print(f"  {name}: {value}", file=sys.stderr)
    sys.exit(1)

print(f"Release metadata valid: {version_file}")
PY
