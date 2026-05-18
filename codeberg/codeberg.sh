#!/bin/bash

GH_TOKEN="ur github token"
CB_TOKEN="ur codeberg token"
GH_REPO="ur repo"  # e.g. example/prikol
CB_REPO="ur repo"  # e.g. example/prikol
CB_URL="https://codeberg.org"

# Clean existing releases
echo "Cleaning old releases..."
curl -s -H "Authorization: token $CB_TOKEN" "$CB_URL/api/v1/repos/$CB_REPO/releases" | \
jq -r '.[].id' | while read -r id; do
  curl -X DELETE "$CB_URL/api/v1/repos/$CB_REPO/releases/$id" \
    -H "Authorization: token $CB_TOKEN" >/dev/null 2>&1
done

# Sync releases
echo "Syncing releases..."
curl -s -H "Authorization: token $GH_TOKEN" "https://api.github.com/repos/$GH_REPO/releases" | \
jq -c '.[]' | while IFS= read -r release_json; do
  tag=$(echo "$release_json" | jq -r .tag_name)
  name=$(echo "$release_json" | jq -r '.name // .tag_name')
  body=$(echo "$release_json" | jq -r '.body // ""')
  draft=$(echo "$release_json" | jq -r '.draft // false')
  
  echo "Processing $tag"
  
  # Create release
  json_data=$(jq -n \
    --arg tn "$tag" --arg n "$name" --arg b "$body" --argjson d "$draft" \
    '{tag_name: $tn, name: $n, body: $b, draft: $d}')
  
  curl -s -X POST "$CB_URL/api/v1/repos/$CB_REPO/releases" \
    -H "Authorization: token $CB_TOKEN" -H "Content-Type: application/json" -d "$json_data" >/dev/null
  
  # Get release ID
  release_id=$(curl -s -H "Authorization: token $CB_TOKEN" \
    "$CB_URL/api/v1/repos/$CB_REPO/releases/tags/$tag" | jq -r .id)
  
  # Sync assets
  echo "$release_json" | jq -c '.assets[] // empty' | while IFS= read -r asset_json; do
    [ "$asset_json" = "null" ] && continue
    
    asset_name=$(echo "$asset_json" | jq -r .name)
    asset_url=$(echo "$asset_json" | jq -r .url)
    
    echo "  Uploading $asset_name"
    
    temp_file=$(mktemp)
    curl -s -L -H "Authorization: token $GH_TOKEN" \
      -H "Accept: application/octet-stream" "$asset_url" -o "$temp_file"
    
    curl -s -X POST "$CB_URL/api/v1/repos/$CB_REPO/releases/$release_id/assets?name=$asset_name" \
      -H "Authorization: token $CB_TOKEN" --data-binary "@$temp_file" \
      -H "Content-Type: application/octet-stream" >/dev/null
    
    rm "$temp_file"
  done
done

echo "Codeberg sync complete!"
