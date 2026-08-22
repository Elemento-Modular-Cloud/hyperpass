import asyncio
import re

from ..base import BaseScraper, make_session
from ..listing import (
    fetch_href_names,
    first_matching,
    head_size_and_version,
    parse_sha512_checksums,
    resolve_min_disk,
    versioned_aliases,
)
from ..models import SUPPORTED_ARCHITECTURES

CLOUD_URL = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/"
IMAGE_PATTERNS = {
    "x86_64": re.compile(
        r"generic_alpine-(?P<version>\d+\.\d+\.\d+)-x86_64-bios-cloudinit-r0\.qcow2"
    ),
    "arm64": re.compile(
        r"generic_alpine-(?P<version>\d+\.\d+\.\d+)-aarch64-uefi-cloudinit-r0\.qcow2"
    ),
}


class AlpineScraper(BaseScraper):
    @property
    def name(self) -> str:
        return "Alpine"

    async def _fetch_image_for_arch(
        self, session, label: str, files: list[str]
    ) -> tuple[str, dict] | None:
        pattern = IMAGE_PATTERNS.get(label)
        if not pattern:
            return None

        matches = [name for name in files if pattern.fullmatch(name)]
        if not matches:
            self.logger.error("No Alpine cloud-init image for %s", label)
            return None

        qcow2 = sorted(matches)[-1]
        version = pattern.fullmatch(qcow2).group("version")  # type: ignore[union-attr]

        sha_name = first_matching(files, re.escape(f"{qcow2}.sha512"))
        if not sha_name:
            raise RuntimeError(f"No sha512 for {qcow2}")

        checksum_text = await self._fetch_text(session, CLOUD_URL + sha_name)
        sha512 = parse_sha512_checksums(checksum_text).get(qcow2)
        if not sha512:
            stripped = checksum_text.strip()
            if re.fullmatch(r"[0-9a-f]{128}", stripped, re.IGNORECASE):
                sha512 = stripped.lower()
        if not sha512:
            raise RuntimeError(f"SHA512 not found for {qcow2}")

        qcow2_url = CLOUD_URL + qcow2
        size, image_version = await head_size_and_version(session, qcow2_url)
        if not image_version:
            image_version = version.replace(".", "")
        return label, {
            "image_location": qcow2_url,
            "id": f"sha512:{sha512}",
            "version": image_version,
            "size": size,
            "min_disk": await resolve_min_disk(session, qcow2_url, self.name),
        }

    async def fetch(self) -> list[dict]:
        async with make_session() as session:
            self.logger.info("Fetching Alpine cloud images from %s", CLOUD_URL)
            files = await fetch_href_names(session, CLOUD_URL)

            results = await asyncio.gather(
                *[
                    self._fetch_image_for_arch(session, label, files)
                    for label in SUPPORTED_ARCHITECTURES
                ]
            )
            items = {
                label: data for result in results if result for label, data in [result]
            }
            if not items:
                raise RuntimeError("Failed to fetch Alpine images")

            version = ""
            for name in files:
                match = IMAGE_PATTERNS["x86_64"].fullmatch(name) or IMAGE_PATTERNS[
                    "arm64"
                ].fullmatch(name)
                if match:
                    version = match.group("version")
                    break
            if not version:
                raise RuntimeError("Could not determine Alpine release version")

            return [
                {
                    "aliases": versioned_aliases(["alpine"], version, latest=True),
                    "os": "Alpine",
                    "release": version,
                    "release_codename": version,
                    "release_title": version,
                    "items": items,
                }
            ]
