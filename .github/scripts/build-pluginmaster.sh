#!/usr/bin/env bash
set -euo pipefail

manifests_file="${1:-manifests}"
output_file="${2:-pluginmaster.json}"
readme_file="${3:-README.md}"

if [[ ! -f "$manifests_file" ]]; then
  echo "Manifest list not found: $manifests_file" >&2
  exit 1
fi

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
