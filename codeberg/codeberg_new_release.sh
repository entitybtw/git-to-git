#!/bin/bash
# Sync ONLY latest GitHub release to Codeberg (no cleanup)

GH_TOKEN="ur github token"
CB_TOKEN="ur codeberg token"
GH_REPO="ur repo"  # e.g. example/prikol
CB_REPO="ur repo"  # e.g. example/prikol
CB_URL="https://codeberg.org"

GH_TOKEN="$GH_TOKEN"
CB_TOKEN="$CB_TOKEN" 
GH_REPO="$GH_REPO"
CB_REPO="$CB_REPO"
CB_URL="https://codeberg.org"

# Get ONLY latest GitHub release
echo "Getting latest release..."
latest_release=$(curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/$GH_REPO/releases/latest")

tag=$(echo "$latest_release" | jq -r .tag_name)
name=$(echo "$latest_release" | jq -r '.name // .tag_name')
body=$(echo "$latest_release" | jq -r '.body // ""')
draft=$(echo "$latest_release" | jq -r '.draft // false')

echo "Processing latest: $tag"

# Check if already exists on Codeberg
cb_release=$(curl -s -H "Authorization: token $CB_TOKEN" \
  "$CB_URL/api/v1/repos/$CB_REPO/releases/tags/$tag")

if echo "$cb_release" | jq -e '.id // empty' >/dev/null 2>&1; then
  echo "Release $tag already exists, skipping..."
  exit 0
fi

# Create release
echo "Creating release $tag..."
json_data=$(jq -n \
  --arg tn "$tag" --arg n "$name" --arg b "$body" --argjson d "$draft" \
  '{tag_name: $tn, name: $n, body: $b, draft: $d}')

curl -s -X POST "$CB_URL/api/v1/repos/$CB_REPO/releases" \
  -H "Authorization: token $CB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$json_data" >/dev/null

# Get new release ID
release_id=$(curl -s -H "Authorization: token $CB_TOKEN" \
  "$CB_URL/api/v1/repos/$CB_REPO/releases/tags/$tag" | jq -r .id)

# Sync assets
echo "$latest_release" | jq -c '.assets[] // empty' | while IFS= read -r asset_json; do
  [ "$asset_json" = "null" ] && continue
  
  asset_name=$(echo "$asset_json" | jq -r .name)
  asset_url=$(echo "$asset_json" | jq -r .url)
  
  echo "  Uploading $asset_name"
  
  temp_file=$(mktemp)
  curl -s -L -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/octet-stream" "$asset_url" -o "$temp_file"
  
  curl -s -X POST "$CB_URL/api/v1/repos/$CB_REPO/releases/$release_id/assets?name=$asset_name" \
    -H "Authorization: token $CB_TOKEN" \
    --data-binary "@$temp_file" \
    -H "Content-Type: application/octet-stream" >/dev/null
  
  rm "$temp_file"
  echo "  ✓ Uploaded"
done

echo "Latest release $tag synced!"
