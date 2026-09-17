#!/usr/bin/env python3
# Build pluginmaster.json from the manifest URL list.

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

USER_AGENT = "DalamudPlugins-pluginmaster"
HTTP_TIMEOUT_SEC = 30
RELEASES_PER_PAGE = 100


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifests", nargs="?", default="manifests")
    parser.add_argument("output", nargs="?", default="pluginmaster.json")
    return parser.parse_args()


def read_manifest_urls(path: Path) -> list[str]:
    urls: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        url = raw_line.split("#", 1)[0].strip()
        if url:
            urls.append(url)
    return urls


def http_get(url: str, headers: dict[str, str] | None = None) -> bytes:
    request_headers = {"User-Agent": USER_AGENT}
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(url, headers=request_headers)
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SEC) as response:
        return response.read()


def load_json_url(url: str) -> Any:
    print(f"Fetching: {url}", file=sys.stderr)
    return json.loads(http_get(url).decode("utf-8"))


def github_api_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def owner_repo_from_url(repo_url: str) -> str | None:
    prefix = "https://github.com/"
    if not repo_url.startswith(prefix):
        return None
    owner_repo = repo_url[len(prefix) :].removesuffix(".git").rstrip("/")
    return owner_repo or None


def fetch_download_count(repo_url: str) -> int:
    owner_repo = owner_repo_from_url(repo_url)
    if owner_repo is None:
        return 0

    total = 0
    page = 1
    headers = github_api_headers()
    while True:
        api_url = (
            f"https://api.github.com/repos/{owner_repo}/releases"
            f"?per_page={RELEASES_PER_PAGE}&page={page}"
        )
        try:
            payload = json.loads(http_get(api_url, headers).decode("utf-8"))
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError) as exc:
            print(f"Warning: failed to fetch releases for {owner_repo}: {exc}", file=sys.stderr)
            return total

        if not isinstance(payload, list):
            print(f"Warning: unexpected releases payload for {owner_repo}", file=sys.stderr)
            return total

        for release in payload:
            for asset in release.get("assets") or []:
                total += int(asset.get("download_count") or 0)

        if len(payload) < RELEASES_PER_PAGE:
            break
        page += 1

    return total


def enrich_with_download_counts(entries: list[Any]) -> list[Any]:
    enriched: list[Any] = []
    for entry in entries:
        if not isinstance(entry, dict):
            enriched.append(entry)
            continue

        plugin = dict(entry)
        repo_url = plugin.get("RepoUrl") or ""
        if repo_url:
            print(f"Fetching download count for: {repo_url}", file=sys.stderr)
            plugin["DownloadCount"] = fetch_download_count(repo_url)
        else:
            plugin["DownloadCount"] = 0
        enriched.append(plugin)
    return enriched


def write_json(path: Path, data: Any) -> None:
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    tmp_path = path.with_name(path.name + ".tmp")
    tmp_path.write_text(text, encoding="utf-8", newline="\n")
    tmp_path.replace(path)


def main() -> int:
    args = parse_args()
    manifests_path = Path(args.manifests)
    output_path = Path(args.output)

    if not manifests_path.is_file():
        print(f"Manifest list not found: {manifests_path}", file=sys.stderr)
        return 1

    urls = read_manifest_urls(manifests_path)
    entries = [load_json_url(url) for url in urls]
    if entries:
        entries = enrich_with_download_counts(entries)

    write_json(output_path, entries)
    print(f"Wrote {len(entries)} entries to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
