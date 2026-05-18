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
