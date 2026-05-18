#!/bin/bash
GH_TOKEN="ur github token"
FORGEJO_TOKEN="ur forgejo token"
GH_REPO="ur repo" # e.g. example/prikol
FORGEJO_REPO="ur repo" # e.g. example/prikol
FORGEJO_URL="ur forgejo instance url"

# Clean existing releases
echo "Cleaning old releases..."
curl -s -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/releases" | \
jq -r '.[].id' | while read -r id; do
  curl -X DELETE "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/releases/$id" \
    -H "Authorization: token $FORGEJO_TOKEN" >/dev/null 2>&1
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
  
  curl -s -X POST "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/releases" \
    -H "Authorization: token $FORGEJO_TOKEN" -H "Content-Type: application/json" -d "$json_data" >/dev/null
  
  # Get release ID
  release_id=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
    "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/releases/tags/$tag" | jq -r .id)
  
  echo "  Release ID: $release_id"
  
  # Sync assets (ИСПРАВЛЕННЫЙ БЛОК)
  echo "$release_json" | jq -c '.assets[] // empty' | while IFS= read -r asset_json; do
    [ "$asset_json" = "null" ] && continue
    
    asset_name=$(echo "$asset_json" | jq -r .name)
    asset_url=$(echo "$asset_json" | jq -r .url)
    
    echo "  Uploading $asset_name"
    
    # Создать temp файл ПЕРЕД скачиванием
    temp_file=$(mktemp)
    echo "    DEBUG: Downloading to $temp_file"
    
    # Скачать файл с проверкой
    if ! curl -s -L -H "Authorization: token $GH_TOKEN" \
      -H "Accept: application/octet-stream" "$asset_url" -o "$temp_file"; then
      echo "    ✗ Download failed"
      rm -f "$temp_file"
      continue
    fi
    
    # Проверить размер
    file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo "0")
    echo "    DEBUG: Downloaded $file_size bytes"
    
    if [ "$file_size" = "0" ]; then
      echo "    ✗ Empty file"
      rm -f "$temp_file"
      continue
    fi
    
    # Аплоад с проверкой ответа
    echo "    → Uploading..."
    response=$(curl -w "\nHTTP: %{http_code}" -s -X POST \
      "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/releases/$release_id/assets?name=$asset_name" \
      -H "Authorization: token $FORGEJO_TOKEN" \
      --data-binary "@$temp_file" \
      -H "Content-Type: application/octet-stream")
    
    echo "    RESPONSE: $response"
    rm -f "$temp_file"
    echo "    ✓ Done"
  done
done

echo "Forgejo sync complete!"
