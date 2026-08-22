import re

from ..base import BaseScraper, make_session
from ..listing import (
    fetch_href_names,
    first_matching,
    head_size_and_version,
    parse_sha256_checksums,
    resolve_min_disk,
)
from ..models import SUPPORTED_ARCHITECTURES

IMAGES_URL = "https://geo.mirror.pkgbuild.com/images/latest/"
STABLE_NAME = "Arch-Linux-x86_64-cloudimg.qcow2"


class ArchScraper(BaseScraper):
    @property
    def name(self) -> str:
        return "Arch"

    async def fetch(self) -> list[dict]:
        async with make_session() as session:
            self.logger.info("Fetching Arch Linux images from %s", IMAGES_URL)
            files = await fetch_href_names(session, IMAGES_URL)

            qcow2 = first_matching(files, re.escape(STABLE_NAME))
            if not qcow2:
                # Fall back to a dated cloudimg if the stable symlink name is absent.
                dated = [
                    name
                    for name in files
                    if re.fullmatch(r"Arch-Linux-x86_64-cloudimg-\d+\.\d+\.qcow2", name)
                ]
                if not dated:
                    raise RuntimeError(f"No Arch cloudimg at {IMAGES_URL}")
                qcow2 = sorted(dated)[-1]

            sha_name = first_matching(files, re.escape(f"{qcow2}.SHA256"))
            if not sha_name:
                raise RuntimeError(f"No SHA256 for {qcow2}")

            checksum_text = await self._fetch_text(session, IMAGES_URL + sha_name)
            sha256 = parse_sha256_checksums(checksum_text).get(qcow2)
            if not sha256:
                match = re.search(
                    rf"^([0-9a-f]{{64}})\s+{re.escape(qcow2)}\s*$",
                    checksum_text,
                    re.MULTILINE | re.IGNORECASE,
                )
                sha256 = match.group(1) if match else None
            if not sha256:
                raise RuntimeError(f"SHA256 not found for {qcow2}")

            qcow2_url = IMAGES_URL + qcow2
            size, image_version = await head_size_and_version(session, qcow2_url)
            dated_match = re.search(r"cloudimg-(\d+)\.(\d+)\.qcow2", qcow2)
            if dated_match and not image_version:
                image_version = dated_match.group(1)

            # Arch currently publishes x86_64 cloud images only.
            items = {
                "x86_64": {
                    "image_location": qcow2_url,
                    "id": sha256,
                    "version": image_version or "latest",
                    "size": size,
                    "min_disk": await resolve_min_disk(session, qcow2_url, self.name),
                }
            }
            # Keep schema happy if other arches are ever required by callers that
            # only look up the host arch — omit unsupported arches intentionally.
            _ = SUPPORTED_ARCHITECTURES

            return [
                {
                    "aliases": "arch, archlinux, archlinux-latest",
                    "os": "Arch",
                    "release": "rolling",
                    "release_codename": "rolling",
                    "release_title": "rolling",
                    "items": items,
                }
            ]
