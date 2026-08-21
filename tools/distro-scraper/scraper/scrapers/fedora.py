import re
import aiohttp
import asyncio
from urllib.parse import urljoin
from bs4 import BeautifulSoup
from dateutil import parser
from ..base import BaseScraper, DEFAULT_TIMEOUT, make_session
from ..listing import versioned_aliases
from ..models import SUPPORTED_ARCHITECTURES


PRIMARY_RELEASES_URL = "https://dl.fedoraproject.org/pub/fedora/linux/releases/"
SECONDARY_RELEASES_URL = "https://dl.fedoraproject.org/pub/fedora-secondary/releases/"

ARCH_MAP = {
    "arm64": "aarch64",
    "power64le": "ppc64le",
}

# Arches that are hosted on the secondary mirror
SECONDARY_ARCHES = {"power64le", "s390x"}


class FedoraScraper(BaseScraper):
    def __init__(self):
        super().__init__()

    @property
    def name(self) -> str:
        return "Fedora"

    async def _fetch_versions(self, session: aiohttp.ClientSession) -> list[str]:
        """
        Fetch the primary releases directory listing and return numeric versions,
        newest first.
        """
        entries = await self._fetch_dir_listing(session, PRIMARY_RELEASES_URL)
        versions = [e.rstrip("/") for e in entries if re.fullmatch(r"\d+/", e)]
        if not versions:
            raise RuntimeError("No numeric release versions found in directory listing")
        ordered = sorted((str(int(v)) for v in versions), key=int, reverse=True)
        self.logger.info("Fedora versions: %s", ", ".join(ordered))
        return ordered

    async def _fetch_items_for_version(
        self, session: aiohttp.ClientSession, version: str
    ) -> dict[str, dict]:
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
                self.logger.error(
                    "Failed to fetch Fedora %s arch %s: %s", version, label, result
                )
            else:
                _, data = result
                items[label] = data
        return items

    async def fetch(self) -> list[dict]:
        """
        Fetch Fedora Cloud Base Generic images for the current and previous release.
        """
        async with make_session() as session:
            versions = await self._fetch_versions(session)
            wanted = versions[:2]
            latest = wanted[0]

            products: list[dict] = []
            for version in wanted:
                items = await self._fetch_items_for_version(session, version)
                if not items:
                    self.logger.error("Skipping Fedora %s: no images", version)
                    continue
                products.append(
                    {
                        "aliases": versioned_aliases(
                            ["fedora"], version, latest=(version == latest)
                        ),
                        "os": "Fedora",
                        "release": version,
                        "release_codename": version,
                        "release_title": version,
                        "items": items,
                    }
                )

            if not products:
                raise RuntimeError("Failed to fetch images for all architectures")

            return products

    async def _fetch_dir_listing(
        self, session: aiohttp.ClientSession, url: str
    ) -> list[str]:
        """
        Fetch an Apache-style HTML directory listing and return the linked filenames.
        """
        text = await self._fetch_text(session, url)
        soup = BeautifulSoup(text)
        entries = (soup.find("pre").find(string="Parent Directory").parent
                      .find_next_siblings("a"))
        return [i.text for i in entries]

    async def _fetch_checksum_file(
        self, session: aiohttp.ClientSession, url: str
    ) -> dict[str, str]:
        """
        Fetch a Fedora CHECKSUM file and return a mapping of filename -> sha256.
        """
        text = await self._fetch_text(session, url)
        return {
            m.group(1): m.group(2)
            for m in re.finditer(
                r"SHA256\s*\(([^)]+)\)\s*=\s*([0-9a-f]+)", text, re.IGNORECASE
            )
        }

    async def _fetch_image_for_arch(
        self, session: aiohttp.ClientSession, version: str, label: str
    ) -> tuple[str, dict]:
        """
        Locate, verify, and return image metadata for a single architecture.
        """
        fedora_arch = ARCH_MAP.get(label, label)
        base = SECONDARY_RELEASES_URL if label in SECONDARY_ARCHES else PRIMARY_RELEASES_URL
        images_url = urljoin(base, f"{version}/Cloud/{fedora_arch}/images/")

        self.logger.info("Fetching image listing for %s from %s", fedora_arch, images_url)
        files = await self._fetch_dir_listing(session, images_url)

        qcow2_files = [
            f for f in files if re.match(r"Fedora-Cloud-Base-Generic-.*\.qcow2$", f)
        ]
        if not qcow2_files:
            raise RuntimeError(
                f"No Generic qcow2 found for arch={fedora_arch} version={version}"
            )
        qcow2_filename = qcow2_files[0]
        qcow2_url = images_url + qcow2_filename

        checksum_files = [f for f in files if "CHECKSUM" in f]
        if not checksum_files:
            raise RuntimeError(
                f"No CHECKSUM file found for arch={fedora_arch} version={version}"
            )
        checksums = await self._fetch_checksum_file(session, images_url + checksum_files[0])

        sha256 = checksums.get(qcow2_filename)
        if not sha256:
            raise RuntimeError(f"SHA256 not found for {qcow2_filename}")

        self.logger.info("Sending HEAD request to %s", qcow2_url)
        async with session.head(
            qcow2_url,
            timeout=aiohttp.ClientTimeout(total=DEFAULT_TIMEOUT),
            allow_redirects=True,
        ) as resp:
            resp.raise_for_status()
            size = int(resp.headers.get("Content-Length", 0))
            last_mod_str = resp.headers.get("Last-Modified")

        last_mod = None
        if last_mod_str:
            try:
                last_mod = parser.parse(last_mod_str)
            except (ValueError, TypeError) as exc:
                self.logger.debug(
                    "Failed to parse Last-Modified '%s': %s", last_mod_str, exc
                )

        return label, {
            "image_location": qcow2_url,
            "id": sha256,
            "version": last_mod.strftime("%Y%m%d") if last_mod else "",
            "size": size
        }
