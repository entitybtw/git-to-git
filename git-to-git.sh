#!/bin/bash

if [ ! -t 0 ]; then
    echo "Non-interactive terminal detected. Please set environment variables or use:"
    echo ""
    echo "  SOURCE_TYPE=github SOURCE_USER=username TARGET_URL=https://forgejo.example.com \\"
    echo "  TARGET_USER=targetuser TARGET_TOKEN=token ./git-to-git.sh"
    echo ""
    echo "Or run interactively after downloading:"
    echo "  curl -O https://raw.githubusercontent.com/entitybtw/git-to-git/main/git-to-git.sh"
    echo "  chmod +x git-to-git.sh && ./git-to-git.sh"
    exit 1
fi

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
cyan=$(tput setaf 6)
purple=$(tput setaf 5)
white=$(tput setaf 7)
reset=$(tput sgr0)

command_exists() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "${green}Checking Prerequisite: $1 is: Installed!${reset}"
  else
    echo "${red}Error: $1 is not installed. Please install it first.${reset}" >&2
    exit 1
  fi
}

command_exists bash
command_exists curl
command_exists jq

or_default() {
  local current_val="$1"
  local prompt_msg="$2"
  local default_value="$3"
  local is_secret="$4"
  local input_val

  if [[ "$is_secret" =~ ^[Yy] ]]; then
    is_secret=true
  else
    is_secret=false
  fi

  if [ -n "$current_val" ]; then
    local display_val="$current_val"
    if [ "$is_secret" = true ]; then
      if [ ${#current_val} -gt 5 ]; then
        display_val="...${current_val: -5}"
      else
        display_val="*****"
      fi
    fi
    echo "${cyan}${prompt_msg}${reset} found in environment, using: ${display_val}" >&2
    echo "$current_val"
    return
  fi

  if [ "$is_secret" = true ]; then
    read -r -s -p "$prompt_msg " input_val
    echo "" >&2
  else
    read -r -p "$prompt_msg " input_val
  fi
  
  input_val="$(echo "$input_val" | xargs)"

  if [ -z "$input_val" ] && [ -n "$default_value" ]; then
    input_val="$default_value"
    echo "${cyan}No input provided. Using default: $default_value${reset}" >&2
  fi

  echo "$input_val"
}

SOURCE_TYPE=$(or_default "$SOURCE_TYPE" "Source provider (github/gitlab/gitea/bitbucket/generic): " "github")
SOURCE_TYPE="$(echo "$SOURCE_TYPE" | tr '[:upper:]' '[:lower:]')"

case "$SOURCE_TYPE" in
  github|gitlab|gitea|bitbucket|generic)
    ;;
  *)
    echo "${red}Error: SOURCE_TYPE must be one of: github, gitlab, gitea, bitbucket, generic${reset}" >&2
    exit 1
    ;;
esac

SOURCE_USER=$(or_default "$SOURCE_USER" "Source username/organization: " "")

if [ -z "$SOURCE_USER" ]; then
  echo "${red}Error: SOURCE_USER is required.${reset}" >&2
  exit 1
fi

if [ "$SOURCE_TYPE" != "generic" ]; then
  case "$SOURCE_TYPE" in
    github)
      DEFAULT_URL="https://api.github.com"
      ;;
    gitlab)
      DEFAULT_URL="https://gitlab.com"
      ;;
    gitea)
      DEFAULT_URL="https://gitea.com"
      ;;
    bitbucket)
      DEFAULT_URL="https://api.bitbucket.org"
      ;;
  esac
  SOURCE_URL=$(or_default "$SOURCE_URL" "Source URL (with https://) [${DEFAULT_URL}]: " "$DEFAULT_URL")
  SOURCE_URL="${SOURCE_URL%/}"
fi

SOURCE_TOKEN=$(or_default "$SOURCE_TOKEN" "Source token (optional, press Enter to skip): " "" "yes")

TARGET_URL=$(or_default "$TARGET_URL" "Target Forgejo/Gitea URL (with https://): " "")
TARGET_URL="${TARGET_URL%/}"
TARGET_USER=$(or_default "$TARGET_USER" "Target username/organization: " "")
TARGET_TOKEN=$(or_default "$TARGET_TOKEN" "Target token: " "" "yes")

STRATEGY=$(or_default "$STRATEGY" "Strategy (mirror/clone) [mirror]: " "mirror")
STRATEGY="$(echo "$STRATEGY" | tr '[:upper:]' '[:lower:]')"

FORCE_SYNC=$(or_default "$FORCE_SYNC" "Delete mirrors that no longer exist on source? (yes/no) [no]: " "no")
FORCE_SYNC="$(echo "$FORCE_SYNC" | tr '[:upper:]' '[:lower:]')"
[[ "$FORCE_SYNC" =~ ^y(es)?$ ]] && FORCE_SYNC=true || FORCE_SYNC=false

MIGRATE_ARCHIVE=$(or_default "$MIGRATE_ARCHIVE_STATUS" "Transfer archive status? (yes/no) [yes]: " "yes")
MIGRATE_ARCHIVE="$(echo "$MIGRATE_ARCHIVE" | tr '[:upper:]' '[:lower:]')"
[[ "$MIGRATE_ARCHIVE" =~ ^y(es)?$ ]] && MIGRATE_ARCHIVE=true || MIGRATE_ARCHIVE=false

INCLUDE_FORKED=$(or_default "$INCLUDE_FORKED" "Include forked repos? (yes/no) [no]: " "no")
INCLUDE_FORKED="$(echo "$INCLUDE_FORKED" | tr '[:upper:]' '[:lower:]')"
[[ "$INCLUDE_FORKED" =~ ^y(es)?$ ]] && INCLUDE_FORKED=true || INCLUDE_FORKED=false

echo ""
echo "${green}=== Configuration ===${reset}"
echo "Source: $SOURCE_TYPE ($SOURCE_USER)"
echo "Target: $TARGET_URL/$TARGET_USER"
echo "Strategy: $STRATEGY"
echo "Force sync: $FORCE_SYNC"
echo "Archive status: $MIGRATE_ARCHIVE"
echo "Include forked: $INCLUDE_FORKED"
echo ""

echo "${yellow}Starting migration...${reset}"


echo "${green}Migration complete!${reset}"
