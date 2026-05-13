# git-to-git

A simple script to move/mirror repositories from GitHub, GitLab, Gitea, or Bitbucket to Forgejo/Gitea.

## Requirements

- bash
- curl
- jq

Install dependencies:

```bash
# Ubuntu/Debian
sudo apt install curl jq

# macOS
brew install curl jq

# RHEL/CentOS
sudo yum install curl jq

# Arch
sudo pacman -Sy curl jq