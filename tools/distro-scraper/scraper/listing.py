import asyncio
import re

import aiohttp
from bs4 import BeautifulSoup
from dateutil import parser

from .base import DEFAULT_TIMEOUT

ARCH_MAP = {
    "arm64": "aarch64",
    "power64le": "ppc64le",
}


def distro_arch(label: str) -> str:
    return ARCH_MAP.get(label, label)


def parse_sha256_checksums(text: str) -> dict[str, str]:
    """
    Parse checksum files into filename -> sha256 mappings.

    Supports Fedora/Rocky ``SHA256 (name) = hash`` lines and coreutils
    ``hash  name`` lines used by AlmaLinux.
    """
    checksums: dict[str, str] = {
        m.group(1): m.group(2)
        for m in re.finditer(
            r"SHA256\s*\(([^)]+)\)\s*=\s*([0-9a-f]+)", text, re.IGNORECASE
        )
    }
    for m in re.finditer(r"^([0-9a-f]{64})\s+(\S+)\s*$", text, re.MULTILINE | re.IGNORECASE):
        checksums[m.group(2)] = m.group(1)
    return checksums


async def fetch_href_names(session: aiohttp.ClientSession, url: str) -> list[str]:
    """
    Return linked names from an HTML directory listing.
    """
    async with session.get(url, timeout=aiohttp.ClientTimeout(total=DEFAULT_TIMEOUT)) as resp:
        resp.raise_for_status()
        text = await resp.text()

    names: list[str] = []
    soup = BeautifulSoup(text, "html.parser")
    for link in soup.find_all("a", href=True):
        href = link["href"]
        if href in (".", "./", "..", "../") or href.startswith("?"):
            continue
        name = href.rstrip("/").rsplit("/", 1)[-1]
        if name:
            names.append(name)
    return names


async def head_size_and_version(
    session: aiohttp.ClientSession, url: str
) -> tuple[int, str]:
    """
    HEAD an image URL and return (Content-Length, YYYYMMDD from Last-Modified).

    Returns (0, "") if the server does not support HEAD.
    """
    try:
        async with session.head(
            url,
            allow_redirects=True,
            timeout=aiohttp.ClientTimeout(total=DEFAULT_TIMEOUT),
        ) as resp:
            resp.raise_for_status()
            size = int(resp.headers.get("Content-Length", 0))
            last_mod_str = resp.headers.get("Last-Modified")
    except (aiohttp.ClientError, asyncio.TimeoutError, ValueError):
        return 0, ""

    version = ""
    if last_mod_str:
        try:
            version = parser.parse(last_mod_str).strftime("%Y%m%d")
        except (ValueError, TypeError):
            version = ""
    return size, version


QCOW2_MAGIC = b"QFI\xfb"
GIB = 1024**3
FAMILY_MIN_DISK = {
    "AlmaLinux": 10 * GIB,
    "Rocky": 10 * GIB,
    "Fedora": 5 * GIB,
    "Debian": 2 * GIB,
}


async def fetch_qcow2_virtual_size(session: aiohttp.ClientSession, url: str) -> int | None:
    """
    Read the qcow2 virtual size from the image header via an HTTP range request.
    """
    try:
        async with session.get(
            url,
            headers={"Range": "bytes=0-71"},
            allow_redirects=True,
            timeout=aiohttp.ClientTimeout(total=DEFAULT_TIMEOUT),
        ) as resp:
            resp.raise_for_status()
            data = await resp.content.read(72)
    except (aiohttp.ClientError, asyncio.TimeoutError):
        return None

    if len(data) < 32 or data[:4] != QCOW2_MAGIC:
        return None
    version = int.from_bytes(data[4:8], "big")
    if version not in (2, 3):
        return None
    return int.from_bytes(data[24:32], "big")


async def resolve_min_disk(
    session: aiohttp.ClientSession, url: str, os_name: str
) -> int:
    """
    Return the image virtual size, falling back to a per-family default.
    """
    virtual = await fetch_qcow2_virtual_size(session, url)
    if virtual and virtual > 0:
        return virtual
    return FAMILY_MIN_DISK.get(os_name, 5 * GIB)


def parse_checksum_sizes(text: str) -> dict[str, int]:
    """
    Parse '# filename: N bytes' comments from checksum files.
    """
    return {
        m.group(1): int(m.group(2))
        for m in re.finditer(r"^#\s*(.+):\s*(\d+)\s+bytes", text, re.MULTILINE)
    }


def first_matching(names: list[str], pattern: str) -> str | None:
    compiled = re.compile(pattern)
    for name in names:
        if compiled.fullmatch(name):
            return name
    return None


def catalog_key(os_name: str, release_title: str) -> str:
    """Top-level key used in distribution-info.json."""
    return f"{os_name} {release_title}".strip()


def versioned_aliases(
    stems: list[str],
    version: str,
    *,
    latest: bool,
    extra: list[str] | None = None,
) -> str:
    """
    Build unique aliases for a distro release.

    Latest releases keep the generic stems (e.g. ``almalinux, alma``) plus
    versioned forms (``almalinux-10``). Older releases only get versioned
    (and optional extra) aliases so lookups stay unambiguous.
    """
    names: list[str] = []
    if latest:
        names.extend(stems)
    if extra:
        names.extend(extra)
    names.extend(f"{stem}-{version}" for stem in stems)

    seen: set[str] = set()
    unique: list[str] = []
    for name in names:
        if name and name not in seen:
            seen.add(name)
            unique.append(name)
    return ", ".join(unique)
