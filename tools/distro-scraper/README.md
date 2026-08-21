# Distributions Scraper

A Python package for scraping cloud distribution image information for Multipass.

## Overview

This tool fetches metadata about cloud images from various Linux distributions (including multiple
supported majors per distro) and outputs a JSON file for use by Multipass. Each release is stored
under a unique catalog key such as ``AlmaLinux 10``, with versioned aliases (``almalinux-10``) so
lookups stay unambiguous.

The scraper will:
1. Load all registered scraper plugins
2. Fetch image metadata from each distribution concurrently
3. Validate the output against the expected schema
4. Write the combined results to the specified JSON file

## Installation

Create a virtual environment:

```bash
python -m venv .venv
source .venv/bin/activate
```

Install the package in development mode:

```bash
pip install -e .
```

## Usage

After installation, run the scraper by providing an output file path:

### Using the installed command:
```bash
distro-scraper <output_file>
```

### Running as a Python module:
```bash
python -m scraper <output_file>
```

## Architecture

### Plugin System

The scraper uses Python entry points for extensibility. Each distribution scraper is registered as a plugin in `pyproject.toml`:

```toml
[project.entry-points."dist_scraper.scrapers"]
debian = "scraper.scrapers.debian:DebianScraper"
fedora = "scraper.scrapers.fedora:FedoraScraper"
almalinux = "scraper.scrapers.almalinux:AlmaLinuxScraper"
rocky = "scraper.scrapers.rocky:RockyScraper"
```

### Adding a New Scraper

1. Create a new module in `scraper/scrapers/` (e.g., `scraper/scrapers/ubuntu.py`)
2. Implement the `BaseScraper` abstract class:

```python
from ..base import BaseScraper

class UbuntuScraper(BaseScraper):
    def __init__(self):
        super().__init__()

    @property
    def name(self) -> str:
        return "Ubuntu"

    async def fetch(self) -> list[dict]:
        # Fetch and return one product dict per release
        return [
            {
                "aliases": "ubuntu, ubuntu-24.04",
                "os": "Ubuntu",
                "release": "24.04",
                "release_codename": "Noble Numbat",
                "release_title": "24.04",
                "items": {
                    "x86_64": {...},
                    "arm64": {...}
                }
            }
        ]
```

3. Register the scraper in `pyproject.toml`:

```toml
[project.entry-points."dist_scraper.scrapers"]
ubuntu = "scraper.scrapers.ubuntu:UbuntuScraper"
```

4. Reinstall the package: `pip install -e .`
