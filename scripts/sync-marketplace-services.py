#!/usr/bin/env python3
"""Bundle the elemento-marketplace service library into a Flutter asset.

The GUI prefers a live download of the marketplace (cached under the app
support directory). The committed Flutter asset remains the offline /
first-run fallback, so releases still ship a known-good snapshot.

Flutter only bundles assets that live inside the GUI package and does not
recurse into undeclared subdirectories, so the whole service library is
flattened into a single JSON file that the existing `assets/` declaration
already covers.

The bundle is a verbatim copy of every text file in each service directory;
interpreting `service.yaml` (entrypoint, `files:` list) is left to the Dart
side so this script needs no YAML dependency.

Usage:
    scripts/sync-marketplace-services.py           # regenerate the fallback asset
    scripts/sync-marketplace-services.py --check   # fail if the asset is stale
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SERVICES_DIR = REPO_ROOT / "3rd-party" / "elemento-marketplace" / "services"
BUNDLE_PATH = REPO_ROOT / "src" / "client" / "gui" / "assets" / "marketplace_services.json"

SCHEMA_VERSION = 1
REPO_URL = "https://github.com/Elemento-Modular-Cloud/elemento-marketplace.git"

# Editor/OS droppings and binaries that must never reach the bundle.
EXCLUDED_NAMES = {".DS_Store", "Thumbs.db"}


def submodule_commit() -> str:
    """Resolve the pinned submodule commit, or "unknown" outside a checkout."""
    try:
        result = subprocess.run(
            ["git", "-C", str(SERVICES_DIR.parent), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"
    return result.stdout.strip()


def collect_service(service_dir: Path) -> dict:
    files = {}
    for path in sorted(service_dir.rglob("*")):
        if not path.is_file() or path.name in EXCLUDED_NAMES:
            continue
        relative = path.relative_to(service_dir).as_posix()
        try:
            files[relative] = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            print(f"  skipping non-text file {relative}", file=sys.stderr)
    return {"id": service_dir.name, "files": files}


def build_bundle() -> dict:
    if not SERVICES_DIR.is_dir():
        raise SystemExit(
            f"Service library not found at {SERVICES_DIR}.\n"
            "Run: git submodule update --init 3rd-party/elemento-marketplace"
        )

    services = []
    for service_dir in sorted(p for p in SERVICES_DIR.iterdir() if p.is_dir()):
        if not (service_dir / "service.yaml").is_file():
            print(f"  skipping {service_dir.name}: no service.yaml", file=sys.stderr)
            continue
        services.append(collect_service(service_dir))

    if not services:
        raise SystemExit(f"No services with a service.yaml found in {SERVICES_DIR}")

    # No timestamp: the bundle is committed, so it must stay byte-stable when
    # the upstream library has not changed.
    return {
        "schema": SCHEMA_VERSION,
        "source": {"repo": REPO_URL, "commit": submodule_commit()},
        "services": services,
    }


def serialise(bundle: dict) -> str:
    return json.dumps(bundle, indent=2, sort_keys=False, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the committed bundle matches the submodule instead of writing it",
    )
    args = parser.parse_args()

    payload = serialise(build_bundle())
    service_count = len(json.loads(payload)["services"])

    if args.check:
        current = BUNDLE_PATH.read_text(encoding="utf-8") if BUNDLE_PATH.is_file() else ""
        if current != payload:
            print(
                f"{BUNDLE_PATH.relative_to(REPO_ROOT)} is out of date.\n"
                "Run: scripts/sync-marketplace-services.py",
                file=sys.stderr,
            )
            return 1
        print(f"Bundle is up to date ({service_count} services).")
        return 0

    BUNDLE_PATH.parent.mkdir(parents=True, exist_ok=True)
    BUNDLE_PATH.write_text(payload, encoding="utf-8")
    size_kb = len(payload.encode("utf-8")) / 1024
    print(
        f"Wrote {BUNDLE_PATH.relative_to(REPO_ROOT)} "
        f"({service_count} services, {size_kb:.0f} KiB)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
