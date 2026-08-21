import base64
import aiohttp
import asyncio
from email.parser import Parser
from ..base import BaseScraper, make_session
from ..listing import versioned_aliases, resolve_min_disk
from ..models import SUPPORTED_ARCHITECTURES

STABLE_RELEASE_FILE_URL = "https://deb.debian.org/debian/dists/stable/Release"
OLDSTABLE_RELEASE_FILE_URL = "https://deb.debian.org/debian/dists/oldstable/Release"
MANIFEST_URL_TEMPLATE = "https://cloud.debian.org/images/cloud/{codename}/latest/debian-{version}-generic-{arch}.json"
IMAGE_BASE_URL = "https://cloud.debian.org/images/cloud/"


class DebianScraper(BaseScraper):
    def __init__(self):
        super().__init__()

    @property
    def name(self) -> str:
        return "Debian"

    @staticmethod
    def _find_qcow2_upload(manifest: dict) -> dict | None:
        """
        Search a manifest for the first Upload entry with qcow2 image-format.

        Returns the matching item dict or None if not found.
        """
        for item in manifest.get("items", []):
            kind = item.get("kind")
            metadata = item.get("metadata", {})
            labels = metadata.get("labels", {})
            if (
                kind == "Upload"
                and labels.get("upload.cloud.debian.org/image-format") == "qcow2"
            ):
                return item
        return None

    def _parse_release_file(self, content: str) -> tuple[str, str]:
        """
        Parse RFC822-style Release file and return important fields.

        Returns a tuple with (Version, Codename)
        """
        parser = Parser()
        parsed = parser.parsestr(content)
        version = parsed.get("Version")
        codename = parsed.get("Codename")
        self.logger.info(
            "Parsed Release file: Version=%s, Codename=%s", version, codename
        )
        return version, codename

    def _decode_sha512_b64_to_hex(self, digest_annotation: str | None) -> str | None:
        """
        Convert a digest annotation like 'sha512:BASE64' to 'sha512:<hex>' or return None.

        Handles missing padding in base64 and logs errors instead of crashing.
        """
        if not digest_annotation:
            return None

        prefix = "sha512:"
        if not digest_annotation.startswith(prefix):
            self.logger.info("Unexpected digest format: %s", digest_annotation)
            return None

        b64 = digest_annotation[len(prefix) :]
        # Add missing padding if necessary
        missing_padding = len(b64) % 4
        if missing_padding:
            b64 += "=" * (4 - missing_padding)

        try:
            decoded = base64.b64decode(b64)
            return f"{prefix}{decoded.hex()}"
        except TypeError as exc:
            self.logger.warning(
                "Failed to decode base64 digest: %s (%s)", digest_annotation, exc
            )
            return None

    async def _fetch_items(
        self, session: aiohttp.ClientSession, codename: str, version: str
    ) -> dict[str, dict]:
        """
        Fetch image manifests for known arches and build the items mapping.

        Iterates over SUPPORTED_ARCHITECTURES, maps through arch_map for scraping,
        but returns data under original SUPPORTED_ARCHITECTURES keys.
        """
        # Map SUPPORTED_ARCHITECTURES to Debian-specific architecture names
        arch_map = {
            "x86_64": "amd64",
            "power64le": "ppc64el",
        }

        # Build list of (original_arch, mapped_arch) tuples for SUPPORTED_ARCHITECTURES
        arch_pairs = [
            (arch, arch_map.get(arch, arch))
            for arch in SUPPORTED_ARCHITECTURES
        ]

        # Fetch all manifests concurrently
        manifest_urls = [
            MANIFEST_URL_TEMPLATE.format(codename=codename, version=version, arch=mapped_arch)
            for _, mapped_arch in arch_pairs
        ]
        manifests = await asyncio.gather(
            *[self._fetch_json(session, url) for url in manifest_urls]
        )

        items: dict[str, dict] = {}
        for (original_arch, mapped_arch), manifest in zip(arch_pairs, manifests):
            if manifest is None:
                self.logger.info("Skipping %s: manifest not available", mapped_arch)
                continue

            upload_item = self._find_qcow2_upload(manifest)
            if not upload_item:
                self.logger.info("No qcow2 upload found for %s %s", codename, mapped_arch)
                continue

            metadata = upload_item.get("metadata", {})
            labels = metadata.get("labels", {})
            annotations = metadata.get("annotations", {})
            data = upload_item.get("data", {})

            image_ref = data.get("ref")
            if not image_ref:
                self.logger.warning(
                    "Upload item missing data.ref for %s %s", codename, mapped_arch
                )
                continue

            image_url = IMAGE_BASE_URL + image_ref
            size = await self._head_content_length(session, image_url)
            sha512_hex = self._decode_sha512_b64_to_hex(
                annotations.get("cloud.debian.org/digest")
            )

            # Take the version label as in the original implementation (split on '-')
            raw_version_label = labels.get("cloud.debian.org/version")
            short_version = None
            if raw_version_label:
                short_version = raw_version_label.split("-")[0]

            # Store under original SUPPORTED_ARCHITECTURES key
            items[original_arch] = {
                "image_location": image_url,
                "id": sha512_hex,
                "version": short_version,
                "size": size,
                "min_disk": await resolve_min_disk(session, image_url, self.name),
            }

        return items

    async def _fetch_suite(
        self, session: aiohttp.ClientSession, release_url: str
    ) -> tuple[str, str] | None:
        """
        Parse a Debian Release file and return (major_version, codename).
        """
        try:
            release_text = await self._fetch_text(session, release_url)
        except Exception as exc:
            self.logger.error("Failed to fetch %s: %s", release_url, exc)
            return None

        raw_version, codename = self._parse_release_file(release_text)
        if not codename:
            self.logger.error("Could not determine Debian codename from %s", release_url)
            return None

        version = raw_version.split(".")[0] if raw_version else None
        if not version:
            self.logger.error("Could not determine Debian version from %s", release_url)
            return None
        return version, codename

    async def fetch(self) -> list[dict]:
        """
        Fetch Debian Cloud images for stable and oldstable.
        """
        async with make_session() as session:
            suites = await asyncio.gather(
                self._fetch_suite(session, STABLE_RELEASE_FILE_URL),
                self._fetch_suite(session, OLDSTABLE_RELEASE_FILE_URL),
            )

            unique: dict[str, str] = {}
            for suite in suites:
                if suite is None:
                    continue
                version, codename = suite
                unique[version] = codename

            if not unique:
                raise RuntimeError("Could not determine Debian stable or oldstable release")

            latest = max(unique, key=int)
            products: list[dict] = []
            for version, codename in unique.items():
                items = await self._fetch_items(session, codename, version)
                if not items:
                    self.logger.error("Skipping Debian %s (%s): no images", version, codename)
                    continue
                products.append(
                    {
                        "aliases": versioned_aliases(
                            ["debian"],
                            version,
                            latest=(version == latest),
                            extra=[codename],
                        ),
                        "os": "Debian",
                        "release": codename,
                        "release_codename": codename.capitalize(),
                        "release_title": version,
                        "items": items,
                    }
                )

            if not products:
                raise RuntimeError("Failed to fetch Debian images for all architectures")

            return products
