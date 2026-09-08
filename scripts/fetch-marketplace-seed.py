#!/usr/bin/env python3
"""Fetch the live elemento-marketplace library and write the GUI seed catalog.

The GUI prefers a runtime download + disk cache. The seed is the last-resort
catalog shipped in the app, so it should contain every current service.

Usage:
    scripts/fetch-marketplace-seed.py
    scripts/fetch-marketplace-seed.py --ref feat-cloudinit-imp
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SEED_PATH = REPO_ROOT / "src" / "client" / "gui" / "assets" / "marketplace_seed.json"

OWNER = "Elemento-Modular-Cloud"
REPO = "elemento-marketplace"
REPO_URL = f"https://github.com/{OWNER}/{REPO}.git"
DEFAULT_REF = os.environ.get("ELP_MARKETPLACE_REF", "feat-cloudinit-imp")
EXCLUDED_NAMES = {".DS_Store", "Thumbs.db"}


def github_token() -> str | None:
    return os.environ.get("ELP_MARKETPLACE_TOKEN") or os.environ.get("GITHUB_TOKEN")


def request_json(url: str) -> dict:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "Electros-LaunchPad",
    }
    token = github_token()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode())


def request_bytes(url: str) -> bytes:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "Electros-LaunchPad",
    }
    token = github_token()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response:
        return response.read()


def resolve_commit(ref: str) -> str:
    data = request_json(f"https://api.github.com/repos/{OWNER}/{REPO}/commits/{ref}")
    sha = data.get("sha")
    if not isinstance(sha, str) or not sha:
        raise SystemExit(f"Could not resolve commit for {OWNER}/{REPO}@{ref}")
    return sha


def decode_text(payload: bytes) -> str | None:
    try:
        return payload.decode("utf-8")
    except UnicodeDecodeError:
        return None


def bundle_from_zipball(payload: bytes, commit: str) -> dict:
    by_service: dict[str, dict[str, str]] = {}
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            name = info.filename.replace("\\", "/")
            parts = name.split("/")
            try:
                services_idx = parts.index("services")
            except ValueError:
                continue
            if services_idx + 1 >= len(parts):
                continue
            service_id = parts[services_idx + 1]
            relative_parts = parts[services_idx + 2 :]
            if not service_id or not relative_parts:
                continue
            relative = "/".join(relative_parts)
            if relative_parts[-1] in EXCLUDED_NAMES:
                continue
            text = decode_text(archive.read(info))
            if text is None:
                print(f"  skipping non-text file {service_id}/{relative}", file=sys.stderr)
                continue
            by_service.setdefault(service_id, {})[relative] = text

    services = [
        {"id": service_id, "files": by_service[service_id]}
        for service_id in sorted(by_service)
        if "service.yaml" in by_service[service_id]
    ]
    if not services:
        raise SystemExit("Marketplace zipball contained no service.yaml files")
    return {
        "schema": 1,
        "source": {"repo": REPO_URL, "commit": commit},
        "services": services,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default=DEFAULT_REF, help=f"Git ref (default {DEFAULT_REF})")
    args = parser.parse_args()

    try:
        commit = resolve_commit(args.ref)
        zip_bytes = request_bytes(
            f"https://api.github.com/repos/{OWNER}/{REPO}/zipball/{args.ref}"
        )
    except urllib.error.HTTPError as exc:
        print(
            f"GitHub HTTP {exc.code} fetching {OWNER}/{REPO}@{args.ref}. "
            "Set ELP_MARKETPLACE_TOKEN or GITHUB_TOKEN if the repo is private.",
            file=sys.stderr,
        )
        return 1

    bundle = bundle_from_zipball(zip_bytes, commit)
    SEED_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(bundle, indent=2, ensure_ascii=False) + "\n"
    SEED_PATH.write_text(payload, encoding="utf-8")
    size_kb = len(payload.encode("utf-8")) / 1024
    print(
        f"Wrote {SEED_PATH.relative_to(REPO_ROOT)} "
        f"({len(bundle['services'])} services, {size_kb:.0f} KiB, {commit[:12]})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
