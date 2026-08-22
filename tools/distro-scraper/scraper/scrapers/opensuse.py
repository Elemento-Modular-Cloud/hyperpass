import asyncio
import re

from ..base import BaseScraper, make_session
from ..listing import (
    distro_arch,
    fetch_href_names,
    first_matching,
    head_size_and_version,
    parse_sha256_checksums,
    resolve_min_disk,
    versioned_aliases,
)
from ..models import SUPPORTED_ARCHITECTURES

LEAP_APPLIANCES_URL = "https://download.opensuse.org/distribution/leap/{version}/appliances/"
TW_APPLIANCES_URL = "https://download.opensuse.org/tumbleweed/appliances/"
TW_AARCH64_APPLIANCES_URL = (
    "https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/"
)
# Keep Leap releases we know publish Minimal-VM Cloud images.
LEAP_VERSIONS = ("15.6",)


class OpenSUSEScraper(BaseScraper):
    @property
    def name(self) -> str:
        return "openSUSE"

    async def _fetch_cloud_image(
        self,
        session,
        *,
        appliances_url: str,
        label: str,
        stable_name: str,
        version_label: str,
    ) -> tuple[str, dict] | None:
        arch = distro_arch(label)
        if arch not in ("x86_64", "aarch64"):
            return None

        self.logger.info("Fetching openSUSE listing from %s", appliances_url)
        try:
            files = await fetch_href_names(session, appliances_url)
        except Exception as exc:
            self.logger.error("Failed to list %s: %s", appliances_url, exc)
            return None

        qcow2 = first_matching(files, re.escape(stable_name))
        if not qcow2:
            self.logger.error("No cloud image %s at %s", stable_name, appliances_url)
            return None

        sha_name = first_matching(files, re.escape(f"{stable_name}.sha256"))
        if not sha_name:
            self.logger.error("No sha256 for %s", stable_name)
            return None

        checksum_text = await self._fetch_text(session, appliances_url + sha_name)
        sha256 = parse_sha256_checksums(checksum_text).get(qcow2)
        if not sha256:
            # openSUSE files are usually "hash  filename"
            match = re.search(
                rf"^([0-9a-f]{{64}})\s+{re.escape(qcow2)}\s*$",
                checksum_text,
                re.MULTILINE | re.IGNORECASE,
            )
            sha256 = match.group(1) if match else None
        if not sha256:
            raise RuntimeError(f"SHA256 not found for {qcow2}")

        qcow2_url = appliances_url + qcow2
        size, image_version = await head_size_and_version(session, qcow2_url)
        if not image_version:
            image_version = version_label.replace(".", "")
        return label, {
            "image_location": qcow2_url,
            "id": sha256,
            "version": image_version,
            "size": size,
            "min_disk": await resolve_min_disk(session, qcow2_url, self.name),
        }

    async def _fetch_leap(self, session, leap_version: str) -> dict[str, dict]:
        base = LEAP_APPLIANCES_URL.format(version=leap_version)
        results = await asyncio.gather(
            *[
                self._fetch_cloud_image(
                    session,
                    appliances_url=base,
                    label=label,
                    stable_name=(
                        f"openSUSE-Leap-{leap_version}-Minimal-VM."
                        f"{distro_arch(label)}-Cloud.qcow2"
                    ),
                    version_label=leap_version,
                )
                for label in SUPPORTED_ARCHITECTURES
            ]
        )
        return {label: data for result in results if result for label, data in [result]}

    async def _fetch_tumbleweed(self, session) -> dict[str, dict]:
        items: dict[str, dict] = {}
        specs = {
            "x86_64": (TW_APPLIANCES_URL, "openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2"),
            "arm64": (
                TW_AARCH64_APPLIANCES_URL,
                "openSUSE-Tumbleweed-Minimal-VM.aarch64-Cloud.qcow2",
            ),
        }
        for label, (url, name) in specs.items():
            result = await self._fetch_cloud_image(
                session,
                appliances_url=url,
                label=label,
                stable_name=name,
                version_label="tumbleweed",
            )
            if result:
                items[result[0]] = result[1]
        return items

    async def fetch(self) -> list[dict]:
        async with make_session() as session:
            products: list[dict] = []

            for leap_version in LEAP_VERSIONS:
                items = await self._fetch_leap(session, leap_version)
                if not items:
                    self.logger.error("Skipping openSUSE Leap %s: no images", leap_version)
                    continue
                products.append(
                    {
                        "aliases": versioned_aliases(
                            ["opensuse", "suse", "leap"],
                            leap_version,
                            latest=True,
                            extra=["opensuse-leap", f"opensuse-leap-{leap_version}"],
                        ),
                        "os": "openSUSE",
                        "release": leap_version,
                        "release_codename": f"Leap {leap_version}",
                        "release_title": f"Leap {leap_version}",
                        "items": items,
                    }
                )

            tw_items = await self._fetch_tumbleweed(session)
            if tw_items:
                products.append(
                    {
                        "aliases": "tumbleweed, opensuse-tumbleweed, tw",
                        "os": "openSUSE",
                        "release": "tumbleweed",
                        "release_codename": "Tumbleweed",
                        "release_title": "Tumbleweed",
                        "items": tw_items,
                    }
                )
            else:
                self.logger.error("Skipping openSUSE Tumbleweed: no images")

            if not products:
                raise RuntimeError("Failed to fetch openSUSE images")
            return products
