import asyncio
import re

from ..base import BaseScraper, make_session
from ..listing import (
    fetch_href_names,
    first_matching,
    head_size_and_version,
    parse_sha256_checksums,
    resolve_min_disk,
    versioned_aliases,
)
from ..models import SUPPORTED_ARCHITECTURES

STREAMS = (
    {
        "release": "2023",
        "latest_url": "https://cdn.amazonlinux.com/al2023/os-images/latest/",
        "kvm_dirs": {"x86_64": "kvm/", "arm64": "kvm-arm64/"},
        "image_pattern": re.compile(r"al2023-kvm-.+\.qcow2$"),
    },
    {
        "release": "2",
        "latest_url": "https://cdn.amazonlinux.com/os-images/latest/",
        "kvm_dirs": {"x86_64": "kvm/", "arm64": "kvm-arm64/"},
        "image_pattern": re.compile(r"amzn2-kvm-.+\.qcow2$"),
    },
)


class AmazonLinuxScraper(BaseScraper):
    @property
    def name(self) -> str:
        return "AmazonLinux"

    async def _resolve_latest_base(
        self, session, latest_url: str
    ) -> str:
        async with session.head(
            latest_url, allow_redirects=True
        ) as resp:
            resp.raise_for_status()
            return str(resp.url).rstrip("/") + "/"

    async def _fetch_image_for_arch(
        self,
        session,
        *,
        release_base: str,
        kvm_dir: str,
        label: str,
        pattern: re.Pattern[str],
    ) -> tuple[str, dict] | None:
        images_url = release_base + kvm_dir
        self.logger.info("Fetching Amazon Linux from %s", images_url)
        try:
            files = await fetch_href_names(session, images_url)
        except Exception as exc:
            self.logger.error("Failed to list %s: %s", images_url, exc)
            return None

        candidates = [name for name in files if pattern.fullmatch(name)]
        if not candidates:
            self.logger.error("No KVM qcow2 at %s", images_url)
            return None
        qcow2 = sorted(candidates)[-1]

        sha_name = first_matching(files, r"SHA256SUMS")
        if not sha_name:
            raise RuntimeError(f"No SHA256SUMS at {images_url}")

        checksum_text = await self._fetch_text(session, images_url + sha_name)
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

        qcow2_url = images_url + qcow2
        size, image_version = await head_size_and_version(session, qcow2_url)
        build = re.search(r"(\d{8})", qcow2)
        if build and not image_version:
            image_version = build.group(1)
        return label, {
            "image_location": qcow2_url,
            "id": sha256,
            "version": image_version or "",
            "size": size,
            "min_disk": await resolve_min_disk(session, qcow2_url, self.name),
        }

    async def _fetch_stream(self, session, stream: dict) -> dict[str, dict]:
        release_base = await self._resolve_latest_base(session, stream["latest_url"])
        results = await asyncio.gather(
            *[
                self._fetch_image_for_arch(
                    session,
                    release_base=release_base,
                    kvm_dir=stream["kvm_dirs"].get(label, ""),
                    label=label,
                    pattern=stream["image_pattern"],
                )
                for label in SUPPORTED_ARCHITECTURES
                if label in stream["kvm_dirs"]
            ]
        )
        return {label: data for result in results if result for label, data in [result]}

    async def fetch(self) -> list[dict]:
        async with make_session() as session:
            products: list[dict] = []
            alias_stems = {
                "2023": (["amazonlinux", "amazon", "al2023", "amzn2023"], True),
                "2": (["amazonlinux-2", "al2", "amzn2"], False),
            }
            for stream in STREAMS:
                items = await self._fetch_stream(session, stream)
                if not items:
                    self.logger.error(
                        "Skipping Amazon Linux %s: no images", stream["release"]
                    )
                    continue
                release = stream["release"]
                stems, is_latest = alias_stems[release]
                if is_latest:
                    aliases = versioned_aliases(stems, release, latest=True)
                else:
                    aliases = ", ".join(stems + ["amazon-linux-2"])
                products.append(
                    {
                        "aliases": aliases,
                        "os": "AmazonLinux",
                        "release": release,
                        "release_codename": f"Amazon Linux {release}",
                        "release_title": release,
                        "items": items,
                    }
                )

            if not products:
                raise RuntimeError("Failed to fetch Amazon Linux images")
            return products
