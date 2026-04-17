#!/bin/bash

INPUT_FILE=$1
if [[ -z "$INPUT_FILE" ]]; then
  echo "Usage: $0 file-to-read"
  exit 1
fi

if [[ -z "$TOKEN" || -z "$HOSTNAME" || -z "$ORG_NAME" || -z "$OAUTH_TOKEN" ]]; then
  echo "Please set TOKEN, HOSTNAME, ORG_NAME, OAUTH_TOKEN"
  exit 1
fi

WORKSPACES=$(jq -c '.[]' "$INPUT_FILE")

for x in $WORKSPACES; do
  ID=$(echo "$x" | jq -r '.id')
  NAME=$(echo "$x" | jq -r '.workspace')
  REPO=$(echo "$x" | jq -r '.repo')

  echo "Processing: $NAME ($ID)"

  # Skip if repo is null
  if [[ "$REPO" == "null" || -z "$REPO" ]]; then
    echo "Skipping (no VCS repo attached)"
    echo ""
    continue
  fi

  echo "Rebinding VCS → $REPO"

  PAYLOAD=$(jq -n \
    --arg id "$ID" \
    --arg repo "$REPO" \
    --arg oauth "$OAUTH_TOKEN" '
{
  data: {
    id: $id,
    type: "workspaces",
    attributes: {
      "vcs-repo": {
        identifier: $repo,
        "oauth-token-id": $oauth,
        branch: "main",
        "ingress-submodules": false
      }
    }
  }
}')

  RESPONSE=$(curl -s \
    --header "Authorization: Bearer $TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    --request PATCH \
    --data "$PAYLOAD" \
    "https://$HOSTNAME/api/v2/workspaces/$ID")

  PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.data.attributes."vcs-repo".identifier')

  if [[ "$PARSED_RESPONSE" == "$REPO" ]]; then
    echo "✅ Success"
  else
    echo "❌ Failed:"
    echo "$RESPONSE"
  fi

  echo ""
done