import asyncio
import re

from ..base import BaseScraper, make_session
from ..listing import (
    distro_arch,
    fetch_href_names,
    first_matching,
    head_size_and_version,
    parse_checksum_sizes,
    parse_sha256_checksums,
    versioned_aliases,
)
from ..models import SUPPORTED_ARCHITECTURES

RELEASES_URL = "https://dl.rockylinux.org/pub/rocky/"
MIN_MAJOR = 8


class RockyScraper(BaseScraper):
    @property
    def name(self) -> str:
        return "Rocky"

    async def _fetch_image_for_arch(
        self, session, version: str, label: str
    ) -> tuple[str, dict]:
        arch = distro_arch(label)
        images_url = f"{RELEASES_URL}{version}/images/{arch}/"
        self.logger.info("Fetching Rocky listing for %s from %s", arch, images_url)

        files = await fetch_href_names(session, images_url)
        qcow2 = first_matching(
            files,
            rf"Rocky-{re.escape(version)}-GenericCloud-Base\.latest\.{re.escape(arch)}\.qcow2",
        )
        if not qcow2:
            qcow2 = first_matching(
                files,
                rf"Rocky-{re.escape(version)}-GenericCloud\.latest\.{re.escape(arch)}\.qcow2",
            )
        if not qcow2:
            raise RuntimeError(f"No GenericCloud qcow2 found for arch={arch} version={version}")

        checksum_name = first_matching(files, re.escape(qcow2) + r"\.CHECKSUM") or first_matching(
            files, r"CHECKSUM"
        )
        if not checksum_name:
            raise RuntimeError(f"No CHECKSUM file found for arch={arch} version={version}")

        checksum_text = await self._fetch_text(session, images_url + checksum_name)
        sha256 = parse_sha256_checksums(checksum_text).get(qcow2)
        if not sha256:
            raise RuntimeError(f"SHA256 not found for {qcow2}")

        qcow2_url = images_url + qcow2
        size, image_version = await head_size_and_version(session, qcow2_url)
        if size == 0:
            size = parse_checksum_sizes(checksum_text).get(qcow2, 0)
        return label, {
            "image_location": qcow2_url,
            "id": sha256,
            "version": image_version,
            "size": size
        }

    async def _fetch_all_arches(self, session, version: str) -> dict[str, dict]:
        results = await asyncio.gather(
            *[
                self._fetch_image_for_arch(session, version, label)
                for label in SUPPORTED_ARCHITECTURES
            ],
            return_exceptions=True,
        )

        items: dict[str, dict] = {}
        for label, result in zip(SUPPORTED_ARCHITECTURES, results):
            if isinstance(result, Exception):
                self.logger.error("Failed to fetch arch %s: %s", label, result)
            else:
                _, data = result
                items[label] = data
        return items

    async def fetch(self) -> list[dict]:
        async with make_session() as session:
            entries = await fetch_href_names(session, RELEASES_URL)
            versions = sorted(
                (e for e in entries if re.fullmatch(r"\d+", e) and int(e) >= MIN_MAJOR),
                key=int,
                reverse=True,
            )
            if not versions:
                raise RuntimeError(f"No numeric release versions found at {RELEASES_URL}")

            results = await asyncio.gather(
                *[self._fetch_all_arches(session, version) for version in versions],
                return_exceptions=True,
            )

            products: list[dict] = []
            latest = versions[0]
            for version, result in zip(versions, results):
                if isinstance(result, Exception):
                    self.logger.error("Failed to fetch Rocky Linux %s: %s", version, result)
                    continue
                if not result:
                    self.logger.error("Skipping Rocky Linux %s: no images", version)
                    continue
                products.append(
                    {
                        "aliases": versioned_aliases(
                            ["rocky"], version, latest=(version == latest)
                        ),
                        "os": "Rocky",
                        "release": version,
                        "release_codename": f"Rocky Linux {version}",
                        "release_title": version,
                        "items": result,
                    }
                )

            if not products:
                raise RuntimeError("Failed to fetch Rocky images for all architectures")

            return products
