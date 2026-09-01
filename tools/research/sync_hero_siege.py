#!/usr/bin/env python3
"""Synchronize public Hero Siege reference material for private local research."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import os
import re
import subprocess
import time
import urllib.parse
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = REPOSITORY_ROOT / "research" / "hero-siege" / "sources.json"
DEFAULT_OUTPUT = REPOSITORY_ROOT / ".research" / "hero-siege"
BUILD_PAYLOAD_KEYS = {"build", "talents", "tree"}
SPECIAL_VALUES = {
    -1: None,
    -2: math.nan,
    -3: math.inf,
    -4: -math.inf,
    -5: -0.0,
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def decode_sveltekit_payload(payload: Dict[str, Any]) -> Any:
    """Hydrate the flattened devalue payload returned by SvelteKit __data.json."""

    page_data = next(
        (
            node["data"]
            for node in payload.get("nodes", [])
            if isinstance(node, dict) and isinstance(node.get("data"), list)
        ),
        None,
    )
    if page_data is None:
        raise ValueError("SvelteKit payload does not contain page data")

    cache: Dict[int, Any] = {}

    def hydrate(reference: Any) -> Any:
        if isinstance(reference, bool) or not isinstance(reference, int):
            return reference
        if reference < 0:
            return SPECIAL_VALUES.get(reference)
        if reference >= len(page_data):
            raise ValueError(f"SvelteKit reference {reference} is out of bounds")
        if reference in cache:
            return cache[reference]

        value = page_data[reference]
        if isinstance(value, dict):
            result: Dict[str, Any] = {}
            cache[reference] = result
            result.update({key: hydrate(child) for key, child in value.items()})
            return result
        if isinstance(value, list):
            if value and value[0] == "Date":
                return value[1]
            if value and value[0] == "Set":
                return [hydrate(child) for child in value[1:]]
            if value and value[0] == "Map":
                pairs = zip(value[1::2], value[2::2])
                return {str(hydrate(key)): hydrate(child) for key, child in pairs}
            if value and value[0] == "BigInt":
                return int(value[1])
            if value and value[0] == "RegExp":
                return {"pattern": value[1], "flags": value[2] if len(value) > 2 else ""}

            result_list: List[Any] = []
            cache[reference] = result_list
            result_list.extend(hydrate(child) for child in value)
            return result_list
        return value

    return hydrate(0)


def _decode_base64_json(value: str) -> Optional[Any]:
    try:
        padding = "=" * (-len(value) % 4)
        decoded = base64.b64decode(value + padding, validate=True)
        parsed = json.loads(decoded.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    return parsed if isinstance(parsed, (dict, list)) else None


def normalize_build_payloads(value: Any) -> Any:
    """Preserve encoded build fields and attach decoded JSON beside them."""

    if isinstance(value, list):
        return [normalize_build_payloads(child) for child in value]
    if not isinstance(value, dict):
        return value

    result = {key: normalize_build_payloads(child) for key, child in value.items()}
    for key in BUILD_PAYLOAD_KEYS:
        encoded = value.get(key)
        if isinstance(encoded, str):
            decoded = _decode_base64_json(encoded)
            if decoded is not None:
                result[f"{key}_decoded"] = decoded
    return result


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class ArtifactManifest:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.artifacts: List[Dict[str, Any]] = []

    def add(
        self,
        *,
        source_id: str,
        kind: str,
        source_url: str,
        path: Path,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        resolved = path.resolve()
        artifact = {
            "source_id": source_id,
            "kind": kind,
            "source_url": source_url,
            "path": resolved.relative_to(self.root).as_posix(),
            "bytes": resolved.stat().st_size,
            "sha256": sha256_path(resolved),
            "observed_at": datetime.fromtimestamp(
                resolved.stat().st_mtime, tz=timezone.utc
            ).isoformat().replace("+00:00", "Z"),
        }
        if metadata:
            artifact["metadata"] = metadata
        self.artifacts.append(artifact)

    def add_git(
        self,
        *,
        source_id: str,
        source_url: str,
        path: Path,
        revision: str,
        tree: str,
    ) -> None:
        self.artifacts.append(
            {
                "source_id": source_id,
                "kind": "git-repository",
                "source_url": source_url,
                "path": path.resolve().relative_to(self.root).as_posix(),
                "revision": revision,
                "tree": tree,
                "observed_at": utc_now(),
            }
        )


class Fetcher:
    def __init__(
        self, user_agent: str, delay_seconds: float, reuse_existing: bool = False
    ) -> None:
        self.user_agent = user_agent
        self.delay_seconds = delay_seconds
        self.reuse_existing = reuse_existing
        self._last_request_at = 0.0

    def fetch(self, url: str, destination: Path) -> Path:
        if self.reuse_existing and destination.is_file():
            return destination
        elapsed = time.monotonic() - self._last_request_at
        if elapsed < self.delay_seconds:
            time.sleep(self.delay_seconds - elapsed)

        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/json,text/html,application/xml,text/plain,*/*;q=0.1",
                "User-Agent": self.user_agent,
            },
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            content = response.read()
        self._last_request_at = time.monotonic()

        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(f".{destination.name}.tmp")
        temporary.write_bytes(content)
        os.replace(temporary, destination)
        return destination


def write_json(path: Path, value: Any) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)
    return path


def run_git(arguments: List[str], working_directory: Optional[Path] = None) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=working_directory,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def sync_git_source(
    source: Dict[str, Any], output: Path, manifest: ArtifactManifest
) -> Dict[str, Any]:
    repository = output / "raw" / "upstreams" / source["id"]
    if repository.exists():
        if not (repository / ".git").is_dir():
            raise RuntimeError(f"Refusing to replace non-Git path: {repository}")
        if run_git(["status", "--porcelain"], repository):
            raise RuntimeError(f"Refusing to update dirty research mirror: {repository}")
        run_git(["pull", "--ff-only"], repository)
    else:
        repository.parent.mkdir(parents=True, exist_ok=True)
        run_git(["clone", "--depth=1", source["repository_url"], str(repository)])

    revision = run_git(["rev-parse", "HEAD"], repository)
    tree = run_git(["rev-parse", "HEAD^{tree}"], repository)
    manifest.add_git(
        source_id=source["id"],
        source_url=source["repository_url"],
        path=repository,
        revision=revision,
        tree=tree,
    )

    map_path = repository / "public" / "data" / "map.json"
    codex_path = repository / "public" / "data" / "codex.json"
    for kind, path in (("map-data", map_path), ("codex-data", codex_path)):
        manifest.add(
            source_id=source["id"],
            kind=kind,
            source_url=f"{source['repository_url']}/tree/{revision}/public/data",
            path=path,
            metadata={"revision": revision},
        )

    map_data = json.loads(map_path.read_text(encoding="utf-8"))
    codex_data = json.loads(codex_path.read_text(encoding="utf-8"))
    summary = {
        "revision": revision,
        "map_items": len(map_data.get("items", {})),
        "map_places": len(map_data.get("places", [])),
        "map_bosses": len(map_data.get("bosses", [])),
        "codex_items": len(codex_data.get("items", [])),
        "codex_stats": len(codex_data.get("stats", [])),
        "codex_sets": len(codex_data.get("sets", [])),
    }
    summary_path = write_json(output / "normalized" / "hs-map-summary.json", summary)
    manifest.add(
        source_id=source["id"],
        kind="normalized-summary",
        source_url=source["repository_url"],
        path=summary_path,
        metadata={"revision": revision},
    )
    return summary


def sitemap_urls(path: Path) -> List[str]:
    root = ET.fromstring(path.read_bytes())
    return [element.text.strip() for element in root.findall("{*}url/{*}loc") if element.text]


def slug_from_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    candidate = parsed.path.strip("/") or "index"
    candidate = re.sub(r"[^A-Za-z0-9._/-]+", "-", candidate)
    return candidate.replace("/", "__")


def count_decoded_builds(value: Any) -> int:
    if isinstance(value, list):
        return sum(count_decoded_builds(child) for child in value)
    if isinstance(value, dict):
        return sum(key.endswith("_decoded") for key in value) + sum(
            count_decoded_builds(child) for child in value.values()
        )
    return 0


def sync_mistersleepycat(
    source: Dict[str, Any],
    output: Path,
    fetcher: Fetcher,
    manifest: ArtifactManifest,
) -> Dict[str, Any]:
    raw_root = output / "raw" / source["id"]
    for name, url in (
        ("robots.txt", source["robots_url"]),
        ("sitemap.xml", source["sitemap_url"]),
    ):
        path = fetcher.fetch(url, raw_root / name)
        manifest.add(
            source_id=source["id"], kind=name, source_url=url, path=path
        )

    for page_url in source.get("page_urls", []):
        path = fetcher.fetch(page_url, raw_root / "pages" / f"{slug_from_url(page_url)}.html")
        manifest.add(
            source_id=source["id"], kind="html", source_url=page_url, path=path
        )

    guide_urls = [
        url for url in sitemap_urls(raw_root / "sitemap.xml") if "/guides/" in url
    ]
    build_count = 0
    normalized_guides: List[Dict[str, Any]] = []
    for guide_url in sorted(set(guide_urls)):
        slug = slug_from_url(guide_url).removeprefix("guides__")
        data_url = f"{guide_url.rstrip('/')}/__data.json"
        raw_path = fetcher.fetch(data_url, raw_root / "guides" / f"{slug}.json")
        manifest.add(
            source_id=source["id"],
            kind="sveltekit-guide-data",
            source_url=data_url,
            path=raw_path,
        )

        payload = json.loads(raw_path.read_text(encoding="utf-8"))
        normalized = normalize_build_payloads(decode_sveltekit_payload(payload))
        normalized_path = write_json(
            output / "normalized" / "guides" / f"{slug}.json", normalized
        )
        decoded_builds = count_decoded_builds(normalized)
        build_count += decoded_builds
        guide = normalized.get("guide", {}) if isinstance(normalized, dict) else {}
        normalized_guides.append(
            {
                "slug": guide.get("slug", slug),
                "title": guide.get("title"),
                "updated_at": guide.get("updatedAt"),
                "decoded_build_payloads": decoded_builds,
                "source_url": guide_url,
            }
        )
        manifest.add(
            source_id=source["id"],
            kind="normalized-guide",
            source_url=data_url,
            path=normalized_path,
        )

    index_path = write_json(
        output / "normalized" / "guides-index.json", normalized_guides
    )
    manifest.add(
        source_id=source["id"],
        kind="normalized-guide-index",
        source_url=source["sitemap_url"],
        path=index_path,
    )
    return {"guides": len(normalized_guides), "decoded_build_payloads": build_count}


def _unique_urls(values: Iterable[str]) -> List[str]:
    seen: Set[str] = set()
    result: List[str] = []
    for value in values:
        if value not in seen:
            seen.add(value)
            result.append(value)
    return result


def sync_helper(
    source: Dict[str, Any],
    output: Path,
    fetcher: Fetcher,
    manifest: ArtifactManifest,
) -> Dict[str, Any]:
    raw_root = output / "raw" / source["id"]
    robots_path = fetcher.fetch(source["robots_url"], raw_root / "robots.txt")
    sitemap_path = fetcher.fetch(source["sitemap_url"], raw_root / "sitemap.xml")
    for kind, url, path in (
        ("robots.txt", source["robots_url"], robots_path),
        ("sitemap.xml", source["sitemap_url"], sitemap_path),
    ):
        manifest.add(source_id=source["id"], kind=kind, source_url=url, path=path)

    configured = [urllib.parse.urljoin(source["base_url"], path) for path in source["page_paths"]]
    pages = _unique_urls([*sitemap_urls(sitemap_path), *configured])
    page_index: List[Dict[str, Any]] = []
    missing_pages: List[Dict[str, Any]] = []
    for page_url in pages:
        try:
            page_path = fetcher.fetch(
                page_url, raw_root / "pages" / f"{slug_from_url(page_url)}.html"
            )
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            missing_pages.append({"source_url": page_url, "http_status": 404})
            continue
        manifest.add(
            source_id=source["id"], kind="html", source_url=page_url, path=page_path
        )
        title_match = re.search(
            rb"<title>(.*?)</title>", page_path.read_bytes(), flags=re.IGNORECASE | re.DOTALL
        )
        page_index.append(
            {
                "source_url": page_url,
                "path": page_path.relative_to(output).as_posix(),
                "bytes": page_path.stat().st_size,
                "title": title_match.group(1).decode("utf-8", errors="replace")
                if title_match
                else None,
            }
        )

    index_path = write_json(output / "normalized" / "helper-pages-index.json", page_index)
    manifest.add(
        source_id=source["id"],
        kind="normalized-page-index",
        source_url=source["sitemap_url"],
        path=index_path,
    )
    return {"pages": len(page_index), "missing_pages": missing_pages}


def sync_wiki(
    source: Dict[str, Any],
    output: Path,
    fetcher: Fetcher,
    manifest: ArtifactManifest,
) -> Dict[str, Any]:
    counts: Dict[str, int] = {}
    for endpoint in source["cargo_endpoints"]:
        path = fetcher.fetch(
            endpoint["url"], output / "raw" / source["id"] / f"{endpoint['id']}.json"
        )
        manifest.add(
            source_id=source["id"],
            kind="cargo-json",
            source_url=endpoint["url"],
            path=path,
        )
        payload = json.loads(path.read_text(encoding="utf-8"))
        counts[endpoint["id"]] = len(payload) if isinstance(payload, list) else 0
    return counts


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--delay", type=float, default=None)
    parser.add_argument(
        "--reuse-existing",
        action="store_true",
        help="Reuse an existing partial snapshot while resuming a failed sync.",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    config = json.loads(arguments.config.read_text(encoding="utf-8"))
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    delay = arguments.delay
    if delay is None:
        delay = float(config.get("request_delay_seconds", 0.2))
    fetcher = Fetcher(config["user_agent"], delay, arguments.reuse_existing)
    manifest = ArtifactManifest(output)
    summaries: Dict[str, Any] = {}

    summaries["hs_map"] = sync_git_source(config["hs_map"], output, manifest)
    summaries["mistersleepycat"] = sync_mistersleepycat(
        config["mistersleepycat"], output, fetcher, manifest
    )
    summaries["hero_siege_helper"] = sync_helper(
        config["hero_siege_helper"], output, fetcher, manifest
    )
    summaries["hero_siege_wiki"] = sync_wiki(
        config["hero_siege_wiki"], output, fetcher, manifest
    )

    manifest_path = write_json(
        output / "manifest.json",
        {
            "schema_version": 1,
            "generated_at": utc_now(),
            "config": arguments.config.resolve().relative_to(REPOSITORY_ROOT).as_posix(),
            "source_policies": {
                source["id"]: source["license_status"]
                for source in (
                    config["hs_map"],
                    config["mistersleepycat"],
                    config["hero_siege_helper"],
                    config["hero_siege_wiki"],
                )
            },
            "summaries": summaries,
            "artifacts": sorted(manifest.artifacts, key=lambda item: item["path"]),
        },
    )
    print(f"Synchronized {len(manifest.artifacts)} artifacts")
    print(f"Manifest: {manifest_path}")
    print(json.dumps(summaries, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
