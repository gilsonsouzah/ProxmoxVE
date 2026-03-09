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

  msg_info "Running openclawupdate"
  /usr/local/bin/openclawupdate
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
