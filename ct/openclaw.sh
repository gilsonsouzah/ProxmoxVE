#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/gilsonsouzah/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: gilsonsouzah
# License: MIT | https://github.com/gilsonsouzah/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/gilsonsouzah/openclaw

APP="OpenClaw"
var_tags="${var_tags:-ai;automation}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/openclaw/.env ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Read image names from docker-compose.yml
  OPENCLAW_IMAGE=$(grep -B1 'container_name: openclaw$' /opt/openclaw/docker-compose.yml | grep 'image:' | awk '{print $2}')
  BROWSER_IMAGE=$(grep -B1 'container_name: openclaw-browser' /opt/openclaw/docker-compose.yml | grep 'image:' | awk '{print $2}')
  OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-ghcr.io/gilsonsouzah/openclaw:latest}"
  BROWSER_IMAGE="${BROWSER_IMAGE:-ghcr.io/gilsonsouzah/openclaw-stealth-browser:latest}"

  # Check for new openclaw image
  LOCAL_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$OPENCLAW_IMAGE" 2>/dev/null | sed 's/.*@//')
  $STD docker pull "$OPENCLAW_IMAGE"
  REMOTE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$OPENCLAW_IMAGE" 2>/dev/null | sed 's/.*@//')

  # Check for new browser image
  LOCAL_BROWSER_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$BROWSER_IMAGE" 2>/dev/null | sed 's/.*@//')
  $STD docker pull "$BROWSER_IMAGE"
  REMOTE_BROWSER_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$BROWSER_IMAGE" 2>/dev/null | sed 's/.*@//')

  if [[ "$LOCAL_DIGEST" == "$REMOTE_DIGEST" && "$LOCAL_BROWSER_DIGEST" == "$REMOTE_BROWSER_DIGEST" ]]; then
    msg_ok "Already up to date!"
    exit
  fi

  msg_info "Stopping Services"
  cd /opt/openclaw
  $STD docker compose down
  msg_ok "Stopped Services"

  msg_info "Starting Services with new images"
  $STD docker compose up -d
  msg_ok "Started Services"

  # Clean up old images
  $STD docker image prune -f
  msg_ok "Updated successfully!"
  exit
}

# =============================================================================
# ADVANCED: Custom Docker images
# =============================================================================
OCW_DEFAULT_IMAGE="ghcr.io/gilsonsouzah/openclaw:latest"
OCW_DEFAULT_BROWSER="ghcr.io/gilsonsouzah/openclaw-stealth-browser:latest"

echo ""
echo -e "  ${BL}Docker Image Configuration${CL}"
echo "  ─────────────────────────────────────────"
echo -e "  Default OpenClaw image:  ${BGN}${OCW_DEFAULT_IMAGE}${CL}"
echo -e "  Default Browser image:   ${BGN}${OCW_DEFAULT_BROWSER}${CL}"
echo ""

read -r -p "${TAB3}OpenClaw image [${OCW_DEFAULT_IMAGE}]: " OCW_IMAGE_INPUT
export OPENCLAW_IMAGE="${OCW_IMAGE_INPUT:-$OCW_DEFAULT_IMAGE}"

read -r -p "${TAB3}Browser image [${OCW_DEFAULT_BROWSER}]: " OCW_BROWSER_INPUT
export OPENCLAW_BROWSER_IMAGE="${OCW_BROWSER_INPUT:-$OCW_DEFAULT_BROWSER}"

echo ""
echo -e "  ${BL}GHCR Authentication${CL} (private registries)"
echo -e "  Press Enter to skip if images are public or you're already logged in."
echo ""

read -r -p "${TAB3}GitHub username (Enter to skip): " GHCR_USER_INPUT
if [[ -n "$GHCR_USER_INPUT" ]]; then
  read -r -s -p "${TAB3}GitHub PAT (read:packages): " GHCR_TOKEN_INPUT
  echo ""
  export OPENCLAW_GHCR_USER="$GHCR_USER_INPUT"
  export OPENCLAW_GHCR_TOKEN="$GHCR_TOKEN_INPUT"
else
  export OPENCLAW_GHCR_USER=""
  export OPENCLAW_GHCR_TOKEN=""
fi

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} Browser VNC (stealth):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/browser/${CL}"
