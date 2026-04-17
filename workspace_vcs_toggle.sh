#!/bin/bash
set -euo pipefail

# Usage:
#   ./workspace_vcs_toggle.sh vcs-to-cli output.json
#   ./workspace_vcs_toggle.sh cli-to-vcs output.json
#
# Required env vars:
#   TOKEN        = HCP Terraform / TFE token
#   HOSTNAME     = app.terraform.io (or your TFE hostname)
#   OAUTH_TOKEN  = required only for cli-to-vcs
#
# Example output.json:
# [
#   {
#     "id": "ws-abc123",
#     "workspace": "test-workspace",
#     "repo": "my-org/my-repo"
#   }
# ]

ACTION="${1:-}"
INPUT_FILE="${2:-}"

if [[ -z "$ACTION" || -z "$INPUT_FILE" ]]; then
  echo "Usage:"
  echo "  $0 vcs-to-cli output.json"
  echo "  $0 cli-to-vcs output.json"
  exit 1
fi

if [[ "$ACTION" != "vcs-to-cli" && "$ACTION" != "cli-to-vcs" ]]; then
  echo "Invalid action: $ACTION"
  echo "Allowed values: vcs-to-cli | cli-to-vcs"
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Input file not found: $INPUT_FILE"
  exit 1
fi

if [[ -z "${TOKEN:-}" || -z "${HOSTNAME:-}" ]]; then
  echo "Please set these environment variables first:"
  echo "  TOKEN"
  echo "  HOSTNAME"
  exit 1
fi

if [[ "$ACTION" == "cli-to-vcs" && -z "${OAUTH_TOKEN:-}" ]]; then
  echo "For cli-to-vcs, please also set:"
  echo "  OAUTH_TOKEN"
  exit 1
fi

WORKSPACES=$(jq -c '.[]' "$INPUT_FILE")

if [[ -z "$WORKSPACES" ]]; then
  echo "No workspaces found in $INPUT_FILE"
  exit 1
fi

for x in $WORKSPACES; do
  ID=$(echo "$x" | jq -r '.id')
  NAME=$(echo "$x" | jq -r '.workspace')
  REPO=$(echo "$x" | jq -r '.repo')

  if [[ -z "$ID" || "$ID" == "null" ]]; then
    echo "Skipping entry with missing workspace id: $x"
    echo
    continue
  fi

  if [[ "$ACTION" == "vcs-to-cli" ]]; then
    echo "Updating workspace from VCS to CLI: $NAME ($ID)"

    PAYLOAD=$(cat <<EOF
{
  "data": {
    "id": "$ID",
    "type": "workspaces",
    "attributes": {
      "vcs-repo": null
    }
  }
}
EOF
)

    RESPONSE=$(curl -s \
      --header "Authorization: Bearer $TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      --request PATCH \
      --data "$PAYLOAD" \
      "https://$HOSTNAME/api/v2/workspaces/$ID")

    PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.data.attributes."vcs-repo"')

    if [[ "$PARSED_RESPONSE" == "null" ]]; then
      echo "Success: $NAME is now CLI-driven."
    else
      echo "Something went wrong for $NAME:"
      echo "$RESPONSE"
    fi

  elif [[ "$ACTION" == "cli-to-vcs" ]]; then
    if [[ -z "$REPO" || "$REPO" == "null" ]]; then
      echo "Skipping $NAME ($ID): repo is missing in input file."
      echo
      continue
    fi

    echo "Updating workspace from CLI to VCS: $NAME ($ID)"
    echo "Setting repo: $REPO"

    PAYLOAD=$(cat <<EOF
{
  "data": {
    "id": "$ID",
    "type": "workspaces",
    "attributes": {
      "vcs-repo": {
        "identifier": "$REPO",
        "oauth-token-id": "$OAUTH_TOKEN"
      }
    }
  }
}
EOF
)

    RESPONSE=$(curl -s \
      --header "Authorization: Bearer $TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      --request PATCH \
      --data "$PAYLOAD" \
      "https://$HOSTNAME/api/v2/workspaces/$ID")

    PARSED_RESPONSE=$(echo "$RESPONSE" | jq -r '.data.attributes."vcs-repo".identifier')

    if [[ "$PARSED_RESPONSE" == "$REPO" ]]; then
      echo "Success: $NAME is now VCS-driven."
    else
      echo "Something went wrong for $NAME:"
      echo "$RESPONSE"
    fi
  fi

  echo
done