#!/bin/bash

GH_TOKEN="ur github token"
GL_TOKEN="ur gitlab token"
GH_REPO="ur repo" # e.g. example/prikol
GL_REPO="ur repo" # e.g. example/prikol
GL_URL="https://gitlab.com"

PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" \
  "$GL_URL/api/v4/projects?search=$(basename $GL_REPO)" | jq -r '.[0].id')

echo "Project ID: $PROJECT_ID"

# Clean existing releases
echo "Cleaning old releases..."
curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" \
  "$GL_URL/api/v4/projects/$PROJECT_ID/releases" | \
jq -r '.[].tag_name' | while read -r tag; do
  curl -X DELETE "$GL_URL/api/v4/projects/$PROJECT_ID/releases/$tag" \
    -H "PRIVATE-TOKEN: $GL_TOKEN" >/dev/null 2>&1
done

# Sync releases (ONLY changelogs)
echo "Syncing releases..."
curl -s -H "Authorization: token $GH_TOKEN" "https://api.github.com/repos/$GH_REPO/releases" | \
jq -c '.[]' | while IFS= read -r release_json; do
  tag=$(echo "$release_json" | jq -r .tag_name)
  name=$(echo "$release_json" | jq -r '.name // .tag_name')
  body=$(echo "$release_json" | jq -r '.body // ""')
  
  echo "Processing $tag"
  
  # Create release WITHOUT assets
  json_data=$(jq -n \
    --arg tn "$tag" --arg n "$name" --arg b "$body" \
    '{name: $n, tag_name: $tn, description: $b}')
  
  curl -s -X POST "$GL_URL/api/v4/projects/$PROJECT_ID/releases" \
    -H "PRIVATE-TOKEN: $GL_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$json_data" >/dev/null
  
  echo "  ✓ Created (changelog only)"
done

echo "GitLab sync complete! (changelogs only)"
