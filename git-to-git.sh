#!/bin/bash

# git-to-git / A migration script for moving or mirroring repositories to self-hosted git service

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
    printf "${green}Checking Prerequisite: $1 is: Installed!\n"
  else
    printf "${red}Error: $1 is not installed. Please install it first.${reset}\n" >&2
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
    printf "%b found in environment, using: %s%b\n" "${cyan}${prompt_msg}" "$display_val" "${reset}" >&2
    echo "$current_val"
    return
  fi

  if [ "$is_secret" = true ]; then
    printf "%s " "$prompt_msg" >&2
    read -r -s input_val
    echo "" >&2
  else
    read -r -p "$prompt_msg " input_val
  fi
  
  input_val="$(echo "$input_val" | xargs)"

  if [ -z "$input_val" ] && [ -n "$default_value" ]; then
    input_val="$default_value"
    local display_default="$default_value"
    if [ "$is_secret" = true ]; then
      if [ ${#default_value} -gt 5 ]; then
        display_default="...${default_value: -5}"
      else
        display_default="*****"
      fi
    fi
    printf "%bNo input provided. Using default: %s%b\n" "${cyan}" "$display_default" "${reset}" >&2
  fi

  echo "$input_val"
}

SOURCE_TYPE=$(or_default "$SOURCE_TYPE" "${cyan}Source provider (github/gitlab/gitea/bitbucket/generic):${reset}" "github")
SOURCE_TYPE="$(echo "$SOURCE_TYPE" | tr '[:upper:]' '[:lower:]')"

case "$SOURCE_TYPE" in
  github|gitlab|gitea|bitbucket|generic)
    ;;
  *)
    echo -e "${red}Error: SOURCE_TYPE must be one of: github, gitlab, gitea, bitbucket, generic${reset}" >&2
    exit 1
    ;;
esac

SOURCE_USER=$(or_default "$SOURCE_USER" "${red}Source username/organization:${reset}" "")

if [ -z "$SOURCE_USER" ]; then
  echo -e "${red}Error: SOURCE_USER is required.${reset}" >&2
  exit 1
fi

if [ "$SOURCE_TYPE" != "generic" ]; then
  SOURCE_URL=$(or_default "$SOURCE_URL" "${green}Source instance URL (with https://):${reset}" "")
  if [ -z "$SOURCE_URL" ]; then
    case "$SOURCE_TYPE" in
      github)
        SOURCE_URL="https://api.github.com"
        echo -e "${yellow}Using default GitHub API URL: $SOURCE_URL${reset}"
        ;;
      gitlab)
        SOURCE_URL="https://gitlab.com"
        echo -e "${yellow}Using default GitLab URL: $SOURCE_URL${reset}"
        ;;
      gitea)
        SOURCE_URL="https://gitea.com"
        echo -e "${yellow}Using default Gitea URL: $SOURCE_URL${reset}"
        ;;
      bitbucket)
        SOURCE_URL="https://api.bitbucket.org"
        echo -e "${yellow}Using default Bitbucket API URL: $SOURCE_URL${reset}"
        ;;
    esac
  fi
  SOURCE_URL="${SOURCE_URL%/}"
fi

SOURCE_TOKEN=$(or_default "$SOURCE_TOKEN" "${red}Source access token (optional, for private repos):${reset}" "" "yes")

if [ "$SOURCE_TYPE" != "generic" ] && [ "$SOURCE_TYPE" != "bitbucket" ]; then
  if [ -z "$SOURCE_IS_ORG" ]; then
    echo -ne "${cyan}Checking account type for $SOURCE_USER...${reset}"
    
    auth_header=""
    if [ -n "$SOURCE_TOKEN" ]; then
      case "$SOURCE_TYPE" in
        github) auth_header="Authorization: token $SOURCE_TOKEN" ;;
        gitlab) auth_header="PRIVATE-TOKEN: $SOURCE_TOKEN" ;;
        gitea) auth_header="Authorization: token $SOURCE_TOKEN" ;;
      esac
    fi

    case "$SOURCE_TYPE" in
      github)
        api_response=$(curl -s -H "$auth_header" "$SOURCE_URL/users/$SOURCE_USER")
        account_type=$(echo "$api_response" | jq -r '.type')
        ;;
      gitlab)
        api_response=$(curl -s -H "$auth_header" "$SOURCE_URL/api/v4/users?username=$SOURCE_USER")
        account_type="User"
        group_response=$(curl -s -H "$auth_header" "$SOURCE_URL/api/v4/groups/$SOURCE_USER")
        if echo "$group_response" | jq -e '.id' >/dev/null 2>&1; then
          account_type="Group"
        fi
        ;;
      gitea)
        api_response=$(curl -s -H "$auth_header" "$SOURCE_URL/api/v1/users/$SOURCE_USER")
        account_type=$(echo "$api_response" | jq -r '.type // "User"')
        org_response=$(curl -s -H "$auth_header" "$SOURCE_URL/api/v1/orgs/$SOURCE_USER")
        if echo "$org_response" | jq -e '.id' >/dev/null 2>&1; then
          account_type="Organization"
        fi
        ;;
    esac

    if [[ "$account_type" == "Organization" ]] || [[ "$account_type" == "Group" ]]; then
      SOURCE_IS_ORG=true
      echo -e " ${green}Organization/Group detected.${reset}"
    else
      SOURCE_IS_ORG=false
      echo -e " ${green}User detected.${reset}"
    fi
  else
    SOURCE_IS_ORG="$(echo "$SOURCE_IS_ORG" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
    if [[ "$SOURCE_IS_ORG" =~ ^y(es)?$ ]] || [[ "$SOURCE_IS_ORG" == "true" ]]; then
      SOURCE_IS_ORG=true
    else
      SOURCE_IS_ORG=false
    fi
  fi
fi

TARGET_URL=$(or_default "$TARGET_URL" "${green}Target Forgejo/Gitea URL (with https://):${reset}" "")
TARGET_URL="${TARGET_URL%/}"
TARGET_USER=$(or_default "$TARGET_USER" "${green}Target username or organization:${reset}" "")
TARGET_TOKEN=$(or_default "$TARGET_TOKEN" "${green}Target access token:${reset}" "" "yes")

STRATEGY=$(or_default "$STRATEGY" "${cyan}Strategy (mirror/clone):${reset}" "mirror")
STRATEGY="$(echo "$STRATEGY" | tr '[:upper:]' '[:lower:]')"

if [[ "$STRATEGY" != "mirror" && "$STRATEGY" != "clone" ]]; then
  echo -e "${red}Error: Strategy must be either 'mirror' or 'clone'.${reset}" >&2
  exit 1
fi

FORCE_SYNC=$(or_default "$FORCE_SYNC" "${yellow}Should mirrored repos that don't have a source anymore be deleted? (Yes/No):${reset}" "No")
FORCE_SYNC="$(echo "$FORCE_SYNC" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
if [[ "$FORCE_SYNC" =~ ^y(es)?$ ]]; then
  FORCE_SYNC=true
else
  FORCE_SYNC=false
fi

MIGRATE_ARCHIVE_STATUS=$(or_default "$MIGRATE_ARCHIVE_STATUS" "${yellow}Should the archive status of repositories be transferred? (Yes/No):${reset}" "Yes")
MIGRATE_ARCHIVE_STATUS="$(echo "$MIGRATE_ARCHIVE_STATUS" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
if [[ "$MIGRATE_ARCHIVE_STATUS" =~ ^y(es)?$ ]]; then
  MIGRATE_ARCHIVE_STATUS=true
else
  MIGRATE_ARCHIVE_STATUS=false
fi

INCLUDE_FORKED=$(or_default "$INCLUDE_FORKED" "${yellow}Include forked repositories? (Yes/No):${reset}" "No")
INCLUDE_FORKED="$(echo "$INCLUDE_FORKED" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
if [[ "$INCLUDE_FORKED" =~ ^y(es)?$ ]]; then
  INCLUDE_FORKED=true
else
  INCLUDE_FORKED=false
fi

echo -e "${green}Force sync is set to: ${FORCE_SYNC}${reset}"
echo -e "${green}Migrate archive status is set to: ${MIGRATE_ARCHIVE_STATUS}${reset}"
echo -e "${green}Include forked repos is set to: ${INCLUDE_FORKED}${reset}"

fetch_repos() {
  local all_repos="[]"
  
  case "$SOURCE_TYPE" in
    github)
      fetch_github_repos
      ;;
    gitlab)
      fetch_gitlab_repos
      ;;
    gitea)
      fetch_gitea_repos
      ;;
    bitbucket)
      fetch_bitbucket_repos
      ;;
    generic)
      fetch_generic_repos
      ;;
  esac
  
  echo "$all_repos"
}

fetch_github_repos() {
  all_repos="[]"
  page=1
  
  local repo_base_url=""
  local auth_header=""
  
  if [ -n "$SOURCE_TOKEN" ]; then
    auth_header="Authorization: token $SOURCE_TOKEN"
  fi
  
  if $SOURCE_IS_ORG; then
    repo_base_url="$SOURCE_URL/orgs/$SOURCE_USER/repos"
  else
    if [ -n "$SOURCE_TOKEN" ]; then
      repo_base_url="$SOURCE_URL/user/repos"
    else
      repo_base_url="$SOURCE_URL/users/$SOURCE_USER/repos"
    fi
  fi
  
  while true; do
    response=$(curl -s -H "$auth_header" "$repo_base_url?per_page=100&page=$page")
    
    if echo "$response" | jq -e 'if type == "object" and .message then true else false end' >/dev/null; then
      err_msg=$(echo "$response" | jq -r '.message')
      echo -e "${red}GitHub API Error: $err_msg${reset}" >&2
      exit 1
    fi
    
    filtered=$(echo "$response" | jq --arg gu "$SOURCE_USER" 'if type == "array" then [.[] | select(.owner.login == $gu)] else [] end')
    
    if [ "$INCLUDE_FORKED" != "true" ]; then
      filtered=$(echo "$filtered" | jq '[.[] | select(.fork == false)]')
    fi
    
    count=$(echo "$filtered" | jq 'length')
    if [ "$count" -eq 0 ]; then
      break
    fi
    
    all_repos=$(echo "$all_repos" "$filtered" | jq -s 'add')
    
    if [ "$count" -lt 100 ]; then
      break
    fi
    page=$((page + 1))
  done
}

fetch_gitlab_repos() {
  all_repos="[]"
  page=1
  local auth_header=""
  
  if [ -n "$SOURCE_TOKEN" ]; then
    auth_header="PRIVATE-TOKEN: $SOURCE_TOKEN"
  fi
  
  local endpoint=""
  if $SOURCE_IS_ORG; then
    endpoint="$SOURCE_URL/api/v4/groups/$SOURCE_USER/projects"
  else
    endpoint="$SOURCE_URL/api/v4/users/$SOURCE_USER/projects"
  fi
  
  while true; do
    response=$(curl -s -H "$auth_header" "$endpoint?per_page=100&page=$page&simple=true")
    
    if echo "$response" | jq -e 'if type == "object" and .message then true else false end' >/dev/null; then
      err_msg=$(echo "$response" | jq -r '.message')
      echo -e "${red}GitLab API Error: $err_msg${reset}" >&2
      exit 1
    fi
    
    if [ "$INCLUDE_FORKED" != "true" ]; then
      filtered=$(echo "$response" | jq '[.[] | select(.forked_from_project == null)]')
    else
      filtered="$response"
    fi
    
    count=$(echo "$filtered" | jq 'length')
    if [ "$count" -eq 0 ]; then
      break
    fi
    
    transformed=$(echo "$filtered" | jq '[.[] | {
      name: .name,
      html_url: .http_url_to_repo,
      private: .visibility != "public",
      archived: .archived,
      full_name: .path_with_namespace,
      clone_url: .http_url_to_repo,
      fork: (.forked_from_project != null)
    }]')
    
    all_repos=$(echo "$all_repos" "$transformed" | jq -s 'add')
    
    if [ "$count" -lt 100 ]; then
      break
    fi
    page=$((page + 1))
  done
}

fetch_gitea_repos() {
  all_repos="[]"
  page=1
  local auth_header=""
  
  if [ -n "$SOURCE_TOKEN" ]; then
    auth_header="Authorization: token $SOURCE_TOKEN"
  fi
  
  local endpoint=""
  if $SOURCE_IS_ORG; then
    endpoint="$SOURCE_URL/api/v1/orgs/$SOURCE_USER/repos"
  else
    endpoint="$SOURCE_URL/api/v1/users/$SOURCE_USER/repos"
  fi
  
  while true; do
    response=$(curl -s -H "$auth_header" "$endpoint?limit=50&page=$page")
    
    if echo "$response" | jq -e 'if type == "object" and .message then true else false end' >/dev/null; then
      err_msg=$(echo "$response" | jq -r '.message')
      echo -e "${red}Gitea API Error: $err_msg${reset}" >&2
      exit 1
    fi
    
    if [ "$INCLUDE_FORKED" != "true" ]; then
      filtered=$(echo "$response" | jq '[.[] | select(.fork == false)]')
    else
      filtered="$response"
    fi
    
    count=$(echo "$filtered" | jq 'length')
    if [ "$count" -eq 0 ]; then
      break
    fi
    
    all_repos=$(echo "$all_repos" "$filtered" | jq -s 'add')
    
    if [ "$count" -lt 50 ]; then
      break
    fi
    page=$((page + 1))
  done
}

fetch_bitbucket_repos() {
  all_repos="[]"
  local next_url=""
  local auth=""
  
  if [ -n "$SOURCE_TOKEN" ]; then
    auth="-u $SOURCE_TOKEN:"
  fi
  
  local base_url="$SOURCE_URL/2.0/repositories/$SOURCE_USER"
  next_url="$base_url"
  
  while [ -n "$next_url" ]; do
    response=$(curl -s $auth "$next_url")
    
    if echo "$response" | jq -e '.error' >/dev/null; then
      err_msg=$(echo "$response" | jq -r '.error.message')
      echo -e "${red}Bitbucket API Error: $err_msg${reset}" >&2
      exit 1
    fi
    
    values=$(echo "$response" | jq '.values')
    
    if [ "$INCLUDE_FORKED" != "true" ]; then
      filtered=$(echo "$values" | jq '[.[] | select(.parent == null)]')
    else
      filtered="$values"
    fi
    
    transformed=$(echo "$filtered" | jq '[.[] | {
      name: .name,
      html_url: .links.html.href,
      private: .is_private,
      archived: false,
      full_name: .full_name,
      clone_url: (.links.clone[] | select(.name == "https") | .href),
      fork: (.parent != null)
    }]')
    
    all_repos=$(echo "$all_repos" "$transformed" | jq -s 'add')
    
    next_url=$(echo "$response" | jq -r '.next // empty')
  done
}

fetch_generic_repos() {
  echo -e "${yellow}Generic mode: Please provide repository URLs one per line. Enter an empty line to finish.${reset}"
  local urls=()
  
  while true; do
    read -r -p "Git repository URL (leave empty to finish): " url
    if [ -z "$url" ]; then
      break
    fi
    urls+=("$url")
  done
  
  for url in "${urls[@]}"; do
    repo_name=$(basename "$url" .git)
    all_repos=$(echo "$all_repos" | jq --arg name "$repo_name" --arg url "$url" \
      '. + [{
        name: $name,
        html_url: $url,
        private: false,
        archived: false,
        full_name: $name,
        clone_url: $url,
        fork: false
      }]')
  done
}

all_repos=$(fetch_repos)

if $FORCE_SYNC; then
  source_repo_names=$(echo "$all_repos" | jq -r '.[].name')
  
  target_response=$(curl -s -H "Authorization: token $TARGET_TOKEN" "$TARGET_URL/api/v1/user/repos")
  
  if [ -z "$SOURCE_TOKEN" ]; then
    target_mirrored=$(echo "$target_response" | jq '[.[] | select(.mirror == true and .private == false)]')
  else
    target_mirrored=$(echo "$target_response" | jq '[.[] | select(.mirror == true)]')
  fi
  
  count_target=$(echo "$target_mirrored" | jq 'length')
  if [ "$count_target" -gt 0 ]; then
    echo "$target_mirrored" | jq -c '.[]' | while read -r repo; do
      repo_name=$(echo "$repo" | jq -r '.name')
      full_name=$(echo "$repo" | jq -r '.full_name')
      
      if ! echo "$source_repo_names" | grep -Fxq "$repo_name"; then
        echo -ne "${red}Deleting ${yellow}$TARGET_URL/$full_name${red} because the mirror source doesn't exist anymore...${reset}"
        curl -s -X DELETE -H "Authorization: token $TARGET_TOKEN" "$TARGET_URL/api/v1/repos/$full_name" >/dev/null
        echo -e " ${green}Success!${reset}"
      fi
    done
  fi
fi

repo_count=$(echo "$all_repos" | jq 'length')
if [ "$repo_count" -eq 0 ]; then
  echo "No repositories found for source $SOURCE_USER."
  exit 0
fi

echo "$all_repos" | jq -c '.[]' | while read -r repo; do
  repo_name=$(echo "$repo" | jq -r '.name')
  html_url=$(echo "$repo" | jq -r '.html_url')
  private_flag=$(echo "$repo" | jq -r '.private')
  archived_flag=$(echo "$repo" | jq -r '.archived')
  clone_url=$(echo "$repo" | jq -r '.clone_url // .html_url')
  
  strategy_display="$(tr '[:lower:]' '[:upper:]' <<<"${STRATEGY:0:1}")${STRATEGY:1}"
  if [ "$private_flag" = "true" ]; then
    access_type="${red}private${reset}"
  else
    access_type="${green}public${reset}"
  fi
  
  echo -ne "${blue}${strategy_display}ing ${access_type} repository ${purple}$html_url${blue} to ${white}$TARGET_URL/$TARGET_USER/$repo_name${blue}...${reset}"
  
  if [ "$STRATEGY" = "clone" ]; then
    mirror=false
  else
    mirror=true
  fi
  
  if [ "$SOURCE_TYPE" = "generic" ]; then
    payload=$(jq -n \
      --arg addr "$clone_url" \
      --argjson mirror "$mirror" \
      --argjson private "$private_flag" \
      --arg owner "$TARGET_USER" \
      --arg repo "$repo_name" \
      '{clone_addr: $addr, mirror: $mirror, private: $private, repo_owner: $owner, repo_name: $repo}')
  else
    payload=$(jq -n \
      --arg addr "$clone_url" \
      --argjson mirror "$mirror" \
      --argjson private "$private_flag" \
      --arg owner "$TARGET_USER" \
      --arg repo "$repo_name" \
      --arg auth_token "$SOURCE_TOKEN" \
      '{clone_addr: $addr, mirror: $mirror, private: $private, repo_owner: $owner, repo_name: $repo, auth_token: (if $auth_token != "" then $auth_token else null end)}')
  fi
  
  response=$(curl -s -H "Content-Type: application/json" -H "Authorization: token $TARGET_TOKEN" -d "$payload" "$TARGET_URL/api/v1/repos/migrate")
  error_message=$(echo "$response" | jq -r '.message // empty')
  
  success=false
  if [[ "$error_message" == *"already exists"* ]]; then
    echo -e " ${yellow}Already exists!${reset}"
    success=true
  elif [ -n "$error_message" ]; then
    echo -e " ${red}Error: $error_message${reset}"
  else
    echo -e " ${green}Success!${reset}"
    success=true
  fi
  
  if [ "$success" = true ] && [ "$archived_flag" = "true" ] && [ "$MIGRATE_ARCHIVE_STATUS" = true ]; then
    if [ "$mirror" = true ]; then
      echo -e "  ${yellow}Skipping archive status transfer (not supported for mirrors).${reset}"
    else
      echo -ne "  ${yellow}Archiving repository on target...${reset}"
      patch_payload='{"archived": true}'
      patch_response=$(curl -s -X PATCH -H "Content-Type: application/json" -H "Authorization: token $TARGET_TOKEN" -d "$patch_payload" "$TARGET_URL/api/v1/repos/$TARGET_USER/$repo_name")
      patch_error=$(echo "$patch_response" | jq -r '.message // empty')
      if [ -n "$patch_error" ]; then
        echo -e " ${red}Error: $patch_error${reset}"
      else
        echo -e " ${green}Done!${reset}"
      fi
    fi
  fi
done

echo -e "${green}Migration completed!${reset}"
