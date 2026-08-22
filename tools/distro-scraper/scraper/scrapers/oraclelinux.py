import re

from bs4 import BeautifulSoup

from ..base import BaseScraper, make_session
from ..listing import head_size_and_version, resolve_min_disk, versioned_aliases
from ..models import SUPPORTED_ARCHITECTURES

TEMPLATES_URL = "https://yum.oracle.com/oracle-linux-templates.html"
MAJOR_RELEASES = ("8", "9", "10")


class OracleLinuxScraper(BaseScraper):
    @property
    def name(self) -> str:
        return "OracleLinux"

    def _parse_template_page(self, html: str) -> dict[tuple[str, str], dict]:
        """
        Return {(major, arch_label): image meta} from the templates HTML page.

        Prefers kvm-cloud images when present (cloud-init), otherwise kvm.
        """
        soup = BeautifulSoup(html, "html.parser")
        found: dict[tuple[str, str], dict] = {}

        for row in soup.find_all("tr"):
            checksums = {
                " ".join(tt.get("class", [])): tt.get_text(strip=True)
                for tt in row.find_all("tt", class_=True)
            }
            ranked: list[tuple[int, str, str, str, str, str]] = []
            for link in row.find_all("a", class_=True, href=True):
                classes = set(link.get("class", []))
                href = link["href"]
                if not href.endswith(".qcow2"):
                    continue
                if "kvm-cloud-image" in classes:
                    priority = 0
                    sha_key = "kvm-cloud-sha256"
                elif "kvm-image" in classes:
                    priority = 1
                    sha_key = "kvm-sha256"
                else:
                    continue
                match = re.search(
                    r"/OL(?P<major>\d+)/u(?P<update>\d+)/(?P<arch>x86_64|aarch64)/",
                    href,
                )
                if not match:
                    continue
                sha = checksums.get(sha_key, "")
                if not re.fullmatch(r"[0-9a-f]{64}", sha, re.IGNORECASE):
                    continue
                ranked.append(
                    (
                        priority,
                        match.group("major"),
                        match.group("arch"),
                        href,
                        sha,
                        match.group("update"),
                    )
                )

            for priority, major, arch, href, sha, update in sorted(ranked):
                if major not in MAJOR_RELEASES:
                    continue
                label = "arm64" if arch == "aarch64" else arch
                key = (major, label)
                existing = found.get(key)
                if existing and existing.get("_priority", 99) <= priority:
                    continue
                found[key] = {
                    "image_location": href,
                    "id": sha.lower(),
                    "version": f"{major}u{update}",
                    "_priority": priority,
                }

        return found

    async def fetch(self) -> list[dict]:
        async with make_session() as session:
            html = await self._fetch_text(session, TEMPLATES_URL)
            parsed = self._parse_template_page(html)
            if not parsed:
                raise RuntimeError(f"No Oracle Linux kvm images found at {TEMPLATES_URL}")

            by_major: dict[str, dict[str, dict]] = {}
            for (major, label), meta in parsed.items():
                if label not in SUPPORTED_ARCHITECTURES:
                    continue
                by_major.setdefault(major, {})[label] = {
                    "image_location": meta["image_location"],
                    "id": meta["id"],
                    "version": meta["version"],
                    "size": 0,
                    "min_disk": 0,
                }

            products: list[dict] = []
            latest = max(by_major.keys(), key=int)
            for major in sorted(by_major.keys(), key=int):
                items = by_major[major]
                for entry in items.values():
                    url = entry["image_location"]
                    size, image_version = await head_size_and_version(session, url)
                    if size:
                        entry["size"] = size
                    if image_version:
                        entry["version"] = image_version
                    entry["min_disk"] = await resolve_min_disk(session, url, self.name)

                products.append(
                    {
                        "aliases": versioned_aliases(
                            ["oracle", "oraclelinux", "ol"],
                            major,
                            latest=(major == latest),
                        ),
                        "os": "OracleLinux",
                        "release": major,
                        "release_codename": f"Oracle Linux {major}",
                        "release_title": major,
                        "items": items,
                    }
                )

            if not products:
                raise RuntimeError("Failed to fetch Oracle Linux images")
            return products
