#!/usr/bin/env bash
set -euo pipefail

manifests_file="${1:-manifests}"
output_file="${2:-pluginmaster.json}"

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
