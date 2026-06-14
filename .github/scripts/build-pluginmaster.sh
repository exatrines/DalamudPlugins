#!/usr/bin/env bash
set -euo pipefail

manifests_file="${1:-manifests}"
output_file="${2:-pluginmaster.json}"
readme_file="${3:-README.md}"

if [[ ! -f "$manifests_file" ]]; then
  echo "Manifest list not found: $manifests_file" >&2
  exit 1
fi

fetch_download_count() {
  local repo_url="$1"

  if [[ "$repo_url" != https://github.com/* ]]; then
    echo "0"
    return 0
  fi

  local owner_repo="${repo_url#https://github.com/}"
  owner_repo="${owner_repo%.git}"
  owner_repo="${owner_repo%/}"

  local curl_args=(
    -fsSL
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
  )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  local total=0
  local page=1

  while true; do
    local releases page_total release_count
    if ! releases="$(
      curl "${curl_args[@]}" \
        "https://api.github.com/repos/${owner_repo}/releases?per_page=100&page=${page}"
    )"; then
      echo "Warning: failed to fetch releases for ${owner_repo}" >&2
      echo "$total"
      return 0
    fi

    page_total="$(echo "$releases" | jq '[.[].assets[].download_count] | add // 0')"
    release_count="$(echo "$releases" | jq 'length')"
    total=$((total + page_total))

    if [[ "$release_count" -lt 100 ]]; then
      break
    fi
    page=$((page + 1))
  done

  echo "$total"
}

enrich_with_download_counts() {
  local file="$1"
  local tmp_enriched
  tmp_enriched="$(mktemp)"

  jq -c '.[]' "$file" | while IFS= read -r entry; do
    repo_url="$(echo "$entry" | jq -r '.RepoUrl // empty')"
    if [[ -n "$repo_url" ]]; then
      echo "Fetching download count for: $repo_url" >&2
      download_count="$(fetch_download_count "$repo_url")"
      echo "$entry" | jq --argjson downloadCount "$download_count" '. + {DownloadCount: $downloadCount}'
    else
      echo "$entry" | jq '. + {DownloadCount: 0}'
    fi
  done | jq -s '.' > "$tmp_enriched"

  mv "$tmp_enriched" "$file"
}

jsons=()
while IFS= read -r line || [[ -n "$line" ]]; do
  url="${line%%#*}"
  url="$(echo "$url" | xargs)"
  [[ -z "$url" ]] && continue

  echo "Fetching: $url"
  jsons+=("$(curl -fsSL "$url")")
done < "$manifests_file"

if [[ ${#jsons[@]} -eq 0 ]]; then
  echo "[]" > "$output_file"
else
  printf '%s\n' "${jsons[@]}" | jq -s '.' > "$output_file"
fi

if [[ -s "$output_file" ]] && [[ "$(jq 'length' "$output_file")" -gt 0 ]]; then
  enrich_with_download_counts "$output_file"
fi

echo "Wrote ${#jsons[@]} entries to $output_file"

escape_md_cell() {
  local value="$1"
  value="${value//|/\\|}"
  value="${value//$'\n'/ }"
  printf '%s' "$value"
}

tmp_table="$(mktemp)"
{
  echo "<!-- PLUGINS_TABLE_START -->"
  echo "| Icon | Name | Description |"
  echo "| ---- | ---- | ---- |"

  while IFS=$'\t' read -r name repo icon punchline description; do
    icon_cell=""
    name_cell="$(escape_md_cell "$name")"
    desc_cell="$(escape_md_cell "${punchline:-$description}")"

    if [[ -n "$icon" ]]; then
      icon_cell="<div align=\"center\"><img src=\"$icon\" width=\"50px\"></div>"
    fi
    if [[ -n "$repo" ]]; then
      name_cell="[$(escape_md_cell "$name")]($repo)"
    fi

    echo "| $icon_cell | $name_cell | $desc_cell |"
  done < <(jq -r '.[] | [.Name // "", .RepoUrl // "", .IconUrl // "", .Punchline // "", .Description // ""] | @tsv' "$output_file")

  echo "<!-- PLUGINS_TABLE_END -->"
} > "$tmp_table"

if [[ ! -f "$readme_file" ]]; then
  echo "README not found: $readme_file" >&2
  rm -f "$tmp_table"
  exit 1
fi

if ! grep -q "<!-- PLUGINS_TABLE_START -->" "$readme_file"; then
  echo "README is missing PLUGINS_TABLE markers" >&2
  rm -f "$tmp_table"
  exit 1
fi

tmp_readme="$(mktemp)"
awk -v table_file="$tmp_table" '
  BEGIN {
    in_block = 0
    while ((getline line < table_file) > 0) table = table line ORS
    close(table_file)
  }
  /<!-- PLUGINS_TABLE_START -->/ {
    printf "%s", table
    in_block = 1
    next
  }
  /<!-- PLUGINS_TABLE_END -->/ {
    in_block = 0
    next
  }
  !in_block { print }
' "$readme_file" > "$tmp_readme"

mv "$tmp_readme" "$readme_file"
rm -f "$tmp_table"
echo "Updated plugins table in $readme_file"
