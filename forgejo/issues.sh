#!/bin/bash

# Configuration
GH_TOKEN="ur github token"
FORGEJO_TOKEN="ur forgejo token"
GH_REPO="ur repo" # e.g. example/prikol
FORGEJO_REPO="ur repo" # e.g. example/prikol
FORGEJO_URL="ur forgejo instance url"

# Files for storing mappings
MAPPING_FILE="/tmp/issue_mapping.json"
COMMENT_MAPPING_FILE="/tmp/comment_mapping.json"

# Logging functions
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_success() {
    echo "[SUCCESS] $1"
}

log_warning() {
    echo "[WARNING] $1"
}

# Initialize mapping files
init_mappings() {
    if [ ! -f "$MAPPING_FILE" ]; then
        echo '{}' > "$MAPPING_FILE"
    fi
    if [ ! -f "$COMMENT_MAPPING_FILE" ]; then
        echo '{}' > "$COMMENT_MAPPING_FILE"
    fi
}

# Save mappings
save_mapping() {
    echo "$1" > "$MAPPING_FILE"
}

save_comment_mapping() {
    echo "$1" > "$COMMENT_MAPPING_FILE"
}

# Format author note
format_author_note() {
    local author=$1
    local author_url=$2
    echo "*Originally posted by [@$author]($author_url) on GitHub*"
}

# Clean all issues in Forgejo
clean_issues() {
    log_info "Cleaning all issues in Forgejo..."
    
    read -p "Are you sure you want to delete ALL issues in Forgejo? (yes/no): " confirmation
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled"
        return
    fi
    
    local page=1
    local deleted=0
    
    while true; do
        issues=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
            "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/issues?page=$page&limit=100")
        
        count=$(echo "$issues" | jq 'length')
        if [ "$count" -eq 0 ]; then
            break
        fi
        
        echo "$issues" | jq -r '.[].number' | while read -r number; do
            log_info "  Deleting issue #$number"
            response=$(curl -s -X DELETE "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/issues/$number" \
                -H "Authorization: token $FORGEJO_TOKEN")
            
            if [ -z "$response" ]; then
                log_success "    Deleted issue #$number"
                deleted=$((deleted + 1))
            else
                log_error "    Failed to delete issue #$number"
            fi
            sleep 0.2
        done
        
        page=$((page + 1))
    done
    
    # Reset mappings
    echo '{}' > "$MAPPING_FILE"
    echo '{}' > "$COMMENT_MAPPING_FILE"
    log_success "All issues and comments cleaned (deleted: $deleted)"
}

# Sync issues from GitHub to Forgejo
sync_issues() {
    log_info "Syncing issues from GitHub to Forgejo..."
    
    local page=1
    local total_created=0
    local mapping=$(cat "$MAPPING_FILE")
    
    while true; do
        issues=$(curl -s -H "Authorization: token $GH_TOKEN" \
            "https://api.github.com/repos/$GH_REPO/issues?state=all&page=$page&per_page=100&filter=all")
        
        count=$(echo "$issues" | jq 'length')
        if [ "$count" -eq 0 ]; then
            break
        fi
        
        echo "$issues" | jq -c '.[] | select(.pull_request == null)' | while IFS= read -r issue_json; do
            gh_number=$(echo "$issue_json" | jq -r .number)
            title=$(echo "$issue_json" | jq -r .title)
            body=$(echo "$issue_json" | jq -r '.body // ""')
            state=$(echo "$issue_json" | jq -r .state)
            author=$(echo "$issue_json" | jq -r .user.login)
            author_url=$(echo "$issue_json" | jq -r .user.html_url)
            created_at=$(echo "$issue_json" | jq -r .created_at)
            updated_at=$(echo "$issue_json" | jq -r .updated_at)
            labels=$(echo "$issue_json" | jq -c '[.labels[].name]')
            
            existing=$(echo "$mapping" | jq -r ".\"$gh_number\"")
            
            if [ "$existing" = "null" ] || [ -z "$existing" ]; then
                log_info "Creating new issue #$gh_number: $title (state: $state, author: $author)"
                
                author_note=$(format_author_note "$author" "$author_url")
                formatted_body=$(cat <<EOF
**GitHub Issue:** https://github.com/$GH_REPO/issues/$gh_number

$author_note
**Created:** $created_at
**Updated:** $updated_at
**GitHub State:** $state

---
$body
EOF
)
                
                json_data=$(jq -n \
                    --arg t "$title" \
                    --arg b "$formatted_body" \
                    --arg st "$state" \
                    '{title: $t, body: $b, state: $st}')
                
                response=$(curl -s -X POST "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/issues" \
                    -H "Authorization: token $FORGEJO_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "$json_data")
                
                forgejo_number=$(echo "$response" | jq -r .number)
                
                if [ "$forgejo_number" != "null" ] && [ -n "$forgejo_number" ]; then
                    log_success "  Created issue #$forgejo_number (GitHub #$gh_number) with state: $state"
                    
                    if [ "$labels" != "[]" ] && [ "$labels" != "null" ]; then
                        curl -s -X PUT "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/issues/$forgejo_number/labels" \
                            -H "Authorization: token $FORGEJO_TOKEN" \
                            -H "Content-Type: application/json" \
                            -d "{\"labels\": $labels}" >/dev/null
                        log_info "    Added labels"
                    fi
                    
                    mapping=$(echo "$mapping" | jq ". + {\"$gh_number\": \"$forgejo_number\"}")
                    save_mapping "$mapping"
                    total_created=$((total_created + 1))
                else
                    log_error "  Failed to create issue #$gh_number"
                fi
            fi
            
            sleep 0.3
        done
        
        page=$((page + 1))
    done
    
    log_success "Created $total_created new issues"
}

# Sync comments
sync_comments() {
    log_info "Syncing comments from GitHub to Forgejo..."
    
    local mapping=$(cat "$MAPPING_FILE")
    local comment_mapping=$(cat "$COMMENT_MAPPING_FILE")
    local total_comments=0
    
    echo "$mapping" | jq -r 'to_entries[] | "\(.key):\(.value)"' | while IFS=':' read -r gh_issue_num forgejo_issue_num; do
        log_info "Processing comments for GitHub issue #$gh_issue_num -> Forgejo #$forgejo_issue_num"
        
        page=1
        while true; do
            comments=$(curl -s -H "Authorization: token $GH_TOKEN" \
                "https://api.github.com/repos/$GH_REPO/issues/$gh_issue_num/comments?page=$page&per_page=100")
            
            count=$(echo "$comments" | jq 'length')
            if [ "$count" -eq 0 ]; then
                break
            fi
            
            echo "$comments" | jq -c '.[]' | while IFS= read -r comment_json; do
                comment_id=$(echo "$comment_json" | jq -r .id)
                comment_body=$(echo "$comment_json" | jq -r '.body // ""')
                comment_author=$(echo "$comment_json" | jq -r .user.login)
                comment_author_url=$(echo "$comment_json" | jq -r .user.html_url)
                comment_created=$(echo "$comment_json" | jq -r .created_at)
                
                existing_comment=$(echo "$comment_mapping" | jq -r ".\"$comment_id\"")
                
                if [ "$existing_comment" = "null" ] || [ -z "$existing_comment" ]; then
                    log_info "  Syncing comment from @$comment_author"
                    
                    author_note=$(format_author_note "$comment_author" "$comment_author_url")
                    formatted_comment=$(cat <<EOF
$author_note
**Posted:** $comment_created

$comment_body

---
*[Original comment on GitHub](https://github.com/$GH_REPO/issues/$gh_issue_num#issuecomment-$comment_id)*
EOF
)
                    
                    response=$(curl -s -X POST "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/issues/$forgejo_issue_num/comments" \
                        -H "Authorization: token $FORGEJO_TOKEN" \
                        -H "Content-Type: application/json" \
                        -d "{\"body\": $(echo "$formatted_comment" | jq -Rs .)}")
                    
                    forgejo_comment_id=$(echo "$response" | jq -r .id)
                    
                    if [ "$forgejo_comment_id" != "null" ] && [ -n "$forgejo_comment_id" ]; then
                        log_success "    Comment synced"
                        comment_mapping=$(echo "$comment_mapping" | jq ". + {\"$comment_id\": \"$forgejo_comment_id\"}")
                        save_comment_mapping "$comment_mapping"
                        total_comments=$((total_comments + 1))
                    else
                        log_error "    Failed to sync comment"
                    fi
                fi
                
                sleep 0.2
            done
            
            page=$((page + 1))
        done
    done
    
    log_success "Synced $total_comments comments"
}

# Sync issue states
sync_issue_states() {
    log_info "Syncing issue states..."
    
    local mapping=$(cat "$MAPPING_FILE")
    local updated=0
    
    echo "$mapping" | jq -r 'to_entries[] | "\(.key):\(.value)"' | while IFS=':' read -r gh_number forgejo_number; do
        log_info "Checking issue GitHub #$gh_number -> Forgejo #$forgejo_number"
        
        gh_state=$(curl -s -H "Authorization: token $GH_TOKEN" \
            "https://api.github.com/repos/$GH_REPO/issues/$gh_number" | jq -r .state)
        
        fg_state=$(curl -s -H "Authorization: token $FORGEJO_TOKEN" \
            "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/issues/$forgejo_number" | jq -r .state)
        
        if [ "$gh_state" != "$fg_state" ]; then
            log_warning "  State mismatch! Updating to $gh_state"
            curl -s -X PATCH "$FORGEJO_URL/api/v1/repos/$FORGEJO_REPO/issues/$forgejo_number" \
                -H "Authorization: token $FORGEJO_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"state\": \"$gh_state\"}" >/dev/null
            updated=$((updated + 1))
            log_success "  Updated"
        fi
        
        sleep 0.2
    done
    
    log_success "Updated $updated issue states"
}

# Full sync
full_sync() {
    log_info "Starting full sync (issues + comments + states)..."
    sync_issues
    sync_comments
    sync_issue_states
    log_success "Full sync completed!"
}

# Incremental sync
incremental_sync() {
    log_info "Starting incremental sync (new comments + status updates)..."
    sync_comments
    sync_issue_states
    log_success "Incremental sync completed!"
}

# Watch mode
watch_sync() {
    log_info "Starting watch mode (syncs every 5 minutes)..."
    
    while true; do
        log_info "=== Sync cycle started at $(date) ==="
        incremental_sync
        log_info "=== Sync cycle completed, waiting 5 minutes ==="
        sleep 300
    done
}

# Main menu
main() {
    init_mappings
    
    echo "========================================="
    echo "GitHub -> Forgejo Issues Mirror"
    echo "========================================="
    echo "1. Full sync (issues + comments + states)"
    echo "2. Incremental sync (new comments + states)"
    echo "3. Sync only issue states"
    echo "4. Sync only new comments"
    echo "5. Clean all issues in Forgejo"
    echo "6. Watch mode (auto-sync every 5 min)"
    echo "7. Exit"
    echo "========================================="
    
    read -p "Choose option [1-7]: " option
    
    case $option in
        1)
            full_sync
            ;;
        2)
            incremental_sync
            ;;
        3)
            sync_issue_states
            ;;
        4)
            sync_comments
            ;;
        5)
            clean_issues
            ;;
        6)
            watch_sync
            ;;
        7)
            log_info "Exiting"
            exit 0
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac
}

# Run main
main
