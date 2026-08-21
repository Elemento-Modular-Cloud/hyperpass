import argparse
import asyncio
import json
import pathlib
import sys
import logging
from importlib.metadata import entry_points
from pydantic import ValidationError
from scraper.base import BaseScraper
from scraper.listing import catalog_key
from scraper.models import ScraperResult


logger = logging.getLogger(__name__)


def configure_logging() -> None:
    """
    Configure root logger for CLI usage.
    """
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stdout,
    )


def load_scrapers() -> list[BaseScraper]:
    """
    Load all scraper classes from registered entry points.
    """
    scrapers = []

    eps = entry_points(group="dist_scraper.scrapers")
    for ep in eps:
        logger.info("Loading scraper plugin: %s", ep.name)
        scraper_class = ep.load()
        if isinstance(scraper_class, type) and issubclass(scraper_class, BaseScraper):
            scrapers.append(scraper_class())
        else:
            logger.warning(
                "Entry point %s did not provide a valid scraper class", ep.name
            )

    return scrapers


def write_output_file(
    output: dict, path: pathlib.Path, replaced_oses: set[str] | None = None
) -> None:
    """
    Attempt to merge output with existing data at the given path.

    If the file exists, load it and merge with new data. Products whose ``os``
    is in ``replaced_oses`` are dropped so a multi-release scrape replaces the
    previous entries for that distro. Other distributions are preserved.

    If the file does not exist or is invalid, it will be created anew.
    """
    existing_data = {}
    if path.exists():
        try:
            raw_data = json.loads(path.read_text())
            for dist_name, dist_data in raw_data.items():
                try:
                    validated = ScraperResult(**dist_data)
                    existing_data[dist_name] = validated.model_dump()
                except ValidationError as e:
                    logger.warning(
                        "Existing data for '%s' is invalid and will be discarded: %s",
                        dist_name,
                        e,
                    )
            logger.info(
                "Loaded existing data from %s (%d valid distribution(s))",
                path,
                len(existing_data),
            )
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("Could not load existing output file: %s", e)

    if replaced_oses:
        existing_data = {
            key: value
            for key, value in existing_data.items()
            if value.get("os") not in replaced_oses
        }

    for dist_name, dist_data in output.items():
        if dist_name in existing_data:
            merged_items = existing_data[dist_name].get("items", {})
            merged_items.update(dist_data.get("items", {}))
            existing_data[dist_name] = {**dist_data, "items": merged_items}
        else:
            existing_data[dist_name] = dist_data

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        json.dump(existing_data, f, indent=4, sort_keys=True)
        f.write("\n")

    logger.info("Output written to %s", path)


def _validate_products(name: str, result: list | dict) -> list[dict]:
    products = result if isinstance(result, list) else [result]
    validated: list[dict] = []
    for product in products:
        try:
            validated.append(ScraperResult(**product).model_dump())
        except ValidationError as e:
            logger.error("Scraper '%s' returned invalid structure:\n%s", name, e)
        except Exception as e:
            logger.exception("Unexpected error validating scraper '%s': %s", name, e)
    return validated


async def run_scraper(scraper_instance: BaseScraper) -> tuple[str, list[dict] | None]:
    """
    Run a single scraper.fetch and capture exceptions.
    """
    name = scraper_instance.name

    try:
        result = await scraper_instance.fetch()
    except Exception as e:
        logger.exception("Scraper '%s' failed: %s", name, e)
        return name, None

    validated = _validate_products(name, result)
    if not validated:
        return name, None

    logger.info("Scraper '%s' succeeded (%d release(s))", name, len(validated))
    return name, validated


async def run_all_scrapers(output_file: pathlib.Path) -> None:
    """
    Run all registered scrapers concurrently and write output.
    """
    scrapers = load_scrapers()
    output = {}
    replaced_oses: set[str] = set()

    tasks = [run_scraper(s) for s in scrapers]
    completed = await asyncio.gather(*tasks)

    failed_scrapers = []
    for name, products in completed:
        if products:
            for product in products:
                output[catalog_key(product["os"], product["release_title"])] = product
                replaced_oses.add(product["os"])
        else:
            failed_scrapers.append(name)

    write_output_file(output, output_file, replaced_oses)
    if not failed_scrapers:
        logger.info("All scrapers succeeded.")
    else:
        logger.warning("Some scrapers failed: %s", ", ".join(failed_scrapers))

def main():
    parser = argparse.ArgumentParser(
        description="Scrape distribution information from various Linux distributions"
    )
    parser.add_argument(
        "output_file", type=pathlib.Path, help="Path to the output JSON file"
    )
    args = parser.parse_args()

    configure_logging()

    try:
        asyncio.run(run_all_scrapers(args.output_file))
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        exit(130)
