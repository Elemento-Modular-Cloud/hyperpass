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

STREAMS = ("9", "10")
IMAGES_URL = "https://cloud.centos.org/centos/{stream}-stream/{arch}/images/"


class CentOSScraper(BaseScraper):
    @property
    def name(self) -> str:
        return "CentOS"

    async def _fetch_image_for_arch(
        self, session, stream: str, label: str
    ) -> tuple[str, dict] | None:
        arch = distro_arch(label)
        if arch not in ("x86_64", "aarch64"):
            return None

        images_url = IMAGES_URL.format(stream=stream, arch=arch)
        self.logger.info("Fetching CentOS Stream %s %s from %s", stream, arch, images_url)
        try:
            files = await fetch_href_names(session, images_url)
        except Exception as exc:
            self.logger.error("Failed to list %s: %s", images_url, exc)
            return None

        pattern = (
            rf"CentOS-Stream-GenericCloud-{re.escape(stream)}-"
            rf"[0-9.]+.{re.escape(arch)}\.qcow2"
        )
        candidates = [name for name in files if re.fullmatch(pattern, name)]
        if not candidates:
            self.logger.error("No GenericCloud image for CentOS Stream %s/%s", stream, arch)
            return None

        # Names sort chronologically by the YYYYMMDD.build suffix.
        qcow2 = sorted(candidates)[-1]
        sha_name = first_matching(files, re.escape(f"{qcow2}.SHA256SUM"))
        if not sha_name:
            raise RuntimeError(f"No SHA256SUM for {qcow2}")

        checksum_text = await self._fetch_text(session, images_url + sha_name)
        sha256 = parse_sha256_checksums(checksum_text).get(qcow2)
        if not sha256:
            match = re.search(
                rf"^SHA256\s*\({re.escape(qcow2)}\)\s*=\s*([0-9a-f]+)",
                checksum_text,
                re.MULTILINE | re.IGNORECASE,
            )
            if not match:
                match = re.search(
                    rf"^([0-9a-f]{{64}})\s+{re.escape(qcow2)}\s*$",
                    checksum_text,
                    re.MULTILINE | re.IGNORECASE,
                )
            sha256 = match.group(1) if match else None
        if not sha256:
            raise RuntimeError(f"SHA256 not found for {qcow2}")

        qcow2_url = images_url + qcow2
        size, image_version = await head_size_and_version(session, qcow2_url)
        build = re.search(rf"GenericCloud-{re.escape(stream)}-([0-9.]+)\.", qcow2)
        if not image_version and build:
            image_version = build.group(1).replace(".", "")
        return label, {
            "image_location": qcow2_url,
            "id": sha256,
            "version": image_version or "",
            "size": size,
            "min_disk": await resolve_min_disk(session, qcow2_url, self.name),
        }

    async def _fetch_stream(self, session, stream: str) -> dict[str, dict]:
        results = await asyncio.gather(
            *[
                self._fetch_image_for_arch(session, stream, label)
                for label in SUPPORTED_ARCHITECTURES
            ]
        )
        return {label: data for result in results if result for label, data in [result]}

    async def fetch(self) -> list[dict]:
        async with make_session() as session:
            products: list[dict] = []
            latest = STREAMS[-1]
            for stream in STREAMS:
                items = await self._fetch_stream(session, stream)
                if not items:
                    self.logger.error("Skipping CentOS Stream %s: no images", stream)
                    continue
                products.append(
                    {
                        "aliases": versioned_aliases(
                            ["centos", "centos-stream", "cs"],
                            stream,
                            latest=(stream == latest),
                            extra=[f"centos-stream-{stream}", f"cs{stream}"],
                        ),
                        "os": "CentOS",
                        "release": stream,
                        "release_codename": f"Stream {stream}",
                        "release_title": f"Stream {stream}",
                        "items": items,
                    }
                )

            if not products:
                raise RuntimeError("Failed to fetch CentOS Stream images")
            return products
