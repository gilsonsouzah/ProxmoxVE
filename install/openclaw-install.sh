#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: gilsonsouzah
# License: MIT | https://github.com/gilsonsouzah/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/gilsonsouzah/openclaw

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# =============================================================================
# INSTALL DOCKER
# =============================================================================

msg_info "Installing Docker"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p "$(dirname "$DOCKER_CONFIG_PATH")"
echo -e '{\n  "log-driver": "journald"\n}' >"$DOCKER_CONFIG_PATH"
$STD sh <(curl -fsSL https://get.docker.com)
msg_ok "Installed Docker"

# =============================================================================
# GHCR AUTHENTICATION (optional — skip if images are public)
# =============================================================================

OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-ghcr.io/gilsonsouzah/openclaw:latest}"
BROWSER_IMAGE="${OPENCLAW_BROWSER_IMAGE:-ghcr.io/gilsonsouzah/openclaw-stealth-browser:latest}"

if [[ -n "${OPENCLAW_GHCR_USER:-}" && -n "${OPENCLAW_GHCR_TOKEN:-}" ]]; then
  msg_info "Authenticating with GHCR"
  if echo "${OPENCLAW_GHCR_TOKEN}" | docker login ghcr.io -u "${OPENCLAW_GHCR_USER}" --password-stdin >/dev/null 2>&1; then
    msg_ok "Authenticated with GHCR"
  else
    msg_error "GHCR authentication failed. Check your username and token."
    exit 1
  fi
else
  msg_info "Skipping GHCR authentication (no credentials provided)"
  msg_ok "Skipped GHCR authentication"
fi

# =============================================================================
# OPENCLAW CONFIGURATION
# =============================================================================

echo ""
echo -e "  ${BL}OpenClaw Configuration${CL}"
echo "  ─────────────────────────────────────────"
echo ""

# Gateway token
GATEWAY_TOKEN=$(openssl rand -hex 32)

# Auth password
AUTH_PASSWORD=""
read -r -p "${TAB3}HTTP Basic Auth password (leave empty to disable): " AUTH_PASSWORD
AUTH_USERNAME="admin"
if [[ -n "$AUTH_PASSWORD" ]]; then
  read -r -p "${TAB3}HTTP Basic Auth username [admin]: " AUTH_USERNAME_INPUT
  AUTH_USERNAME="${AUTH_USERNAME_INPUT:-admin}"
fi

# AI Provider
echo ""
echo -e "  ${BL}AI Provider Configuration${CL} (at least one required)"
echo "  You can add more providers later in /opt/openclaw/.env"
echo ""

ANTHROPIC_API_KEY=""
read -r -p "${TAB3}Anthropic API key (recommended, or press Enter to skip): " ANTHROPIC_API_KEY

OPENROUTER_API_KEY=""
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  read -r -p "${TAB3}OpenRouter API key (or press Enter to skip): " OPENROUTER_API_KEY
fi

OPENAI_API_KEY=""
if [[ -z "$ANTHROPIC_API_KEY" && -z "$OPENROUTER_API_KEY" ]]; then
  read -r -p "${TAB3}OpenAI API key (at least one provider is required): " OPENAI_API_KEY
fi

if [[ -z "$ANTHROPIC_API_KEY" && -z "$OPENROUTER_API_KEY" && -z "$OPENAI_API_KEY" ]]; then
  msg_error "At least one AI provider API key is required!"
  exit 1
fi

# VNC password for the stealth browser
VNC_PW=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c16)
echo ""
read -r -p "${TAB3}Browser VNC password [auto-generated]: " VNC_PW_INPUT
VNC_PW="${VNC_PW_INPUT:-$VNC_PW}"

msg_info "Pulling OpenClaw images"
$STD docker pull "${OPENCLAW_IMAGE}"
$STD docker pull "${BROWSER_IMAGE}"
msg_ok "Pulled OpenClaw images"

# =============================================================================
# CREATE .ENV FILE
# =============================================================================

msg_info "Configuring OpenClaw"

mkdir -p /opt/openclaw
get_lxc_ip

cat <<EOF >/opt/openclaw/.env
# ── OpenClaw LXC Configuration ───────────────────────────────────────────────
# Auto-generated during installation. Edit as needed.

# AI Providers (at least one required)
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}

# HTTP Basic Auth
AUTH_USERNAME=${AUTH_USERNAME}
AUTH_PASSWORD=${AUTH_PASSWORD}

# Gateway
OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_GATEWAY_PORT=18789

# Storage
OPENCLAW_STATE_DIR=/data/.openclaw
OPENCLAW_WORKSPACE_DIR=/data/workspace

# Browser sidecar (stealth browser, same network namespace)
BROWSER_CDP_URL=http://127.0.0.1:9222
BROWSER_EVALUATE_ENABLED=true
BROWSER_REMOTE_HANDSHAKE_TIMEOUT_MS=5000
BROWSER_REMOTE_TIMEOUT_MS=3000

# Browser VNC
VNC_PW=${VNC_PW}

# Port
PORT=8080

# ── Add more providers below as needed ────────────────────────────────────────
# GEMINI_API_KEY=
# XAI_API_KEY=
# GROQ_API_KEY=
# DEEPGRAM_API_KEY=
# OLLAMA_BASE_URL=http://host-ip:11434

# ── Channels (optional) ──────────────────────────────────────────────────────
# TELEGRAM_BOT_TOKEN=
# DISCORD_BOT_TOKEN=
# WHATSAPP_ENABLED=true
# WHATSAPP_DM_POLICY=pairing
# WHATSAPP_ALLOW_FROM=+1234567890

# ── Hooks (optional) ─────────────────────────────────────────────────────────
# HOOKS_ENABLED=true
# HOOKS_TOKEN=$(openssl rand -hex 32)
# HOOKS_PATH=/hooks
EOF
chmod 600 /opt/openclaw/.env

msg_ok "Configured OpenClaw"

# =============================================================================
# CREATE DOCKER COMPOSE
# =============================================================================

msg_info "Creating Docker Compose configuration"

mkdir -p /opt/openclaw/data /opt/openclaw/config /opt/openclaw/browser
chown -R 1000:1000 /opt/openclaw/browser

cat <<COMPOSE >/opt/openclaw/docker-compose.yml
name: openclaw
services:
  openclaw:
    image: ${OPENCLAW_IMAGE}
    container_name: openclaw
    env_file: .env
    network_mode: host
    volumes:
      - /opt/openclaw/data:/data
      - /opt/openclaw/config:/app/config
    depends_on:
      openclaw-browser:
        condition: service_started
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 2g
        reservations:
          memory: 512m

  openclaw-browser:
    image: ${BROWSER_IMAGE}
    container_name: openclaw-browser
    init: true
    environment:
      - VNC_PW=\${VNC_PW:-changeme}
      - CDP_PORT=9222
    network_mode: host
    shm_size: 512m
    volumes:
      - /opt/openclaw/browser:/home/kasm-user
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9222/json/version || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 90s
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 1g
        reservations:
          memory: 256m
COMPOSE

msg_ok "Created Docker Compose configuration"

# =============================================================================
# START SERVICES
# =============================================================================

msg_info "Starting OpenClaw services"
cd /opt/openclaw
$STD docker compose up -d

# Wait for browser CDP to be ready (up to 90s)
BROWSER_READY=false
for i in $(seq 1 18); do
  if docker exec openclaw-browser wget --no-verbose --tries=1 --spider http://localhost:9222/json/version >/dev/null 2>&1; then
    BROWSER_READY=true
    break
  fi
  sleep 5
done

if [[ "$BROWSER_READY" == true ]]; then
  msg_ok "Started OpenClaw services (browser CDP ready)"
else
  msg_ok "Started OpenClaw services (browser may still be initializing)"
fi

# =============================================================================
# UPDATE CLI
# =============================================================================
# Creates /usr/local/bin/openclawupdate — a manual CLI to check for new
# image digests and redeploy if needed.
# =============================================================================

msg_info "Installing openclawupdate CLI"

cat <<'UPDATER' >/usr/local/bin/openclawupdate
#!/usr/bin/env bash
# openclawupdate — check for new OpenClaw Docker images and redeploy.
# Usage:
#   openclawupdate            pull + redeploy if new images exist
#   openclawupdate --dry-run  only show what would happen, don't apply
set -euo pipefail

COMPOSE_DIR="/opt/openclaw"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      echo "Usage: openclawupdate [--dry-run]"
      echo ""
      echo "  --dry-run   Check for updates without applying them"
      echo "  -h, --help  Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: openclawupdate [--dry-run]"
      exit 1
      ;;
  esac
done

# Read image names from docker-compose.yml
OPENCLAW_IMAGE=$(grep -B1 'container_name: openclaw$' "$COMPOSE_DIR/docker-compose.yml" | grep 'image:' | awk '{print $2}')
BROWSER_IMAGE=$(grep -B1 'container_name: openclaw-browser' "$COMPOSE_DIR/docker-compose.yml" | grep 'image:' | awk '{print $2}')

if [[ -z "$OPENCLAW_IMAGE" || -z "$BROWSER_IMAGE" ]]; then
  echo "ERROR: Could not read image names from docker-compose.yml"
  exit 1
fi

echo "Images:"
echo "  openclaw:         $OPENCLAW_IMAGE"
echo "  stealth-browser:  $BROWSER_IMAGE"
echo ""

# Get current local digests
LOCAL_OCW=$(docker inspect --format='{{index .RepoDigests 0}}' "$OPENCLAW_IMAGE" 2>/dev/null || echo "none")
LOCAL_BRW=$(docker inspect --format='{{index .RepoDigests 0}}' "$BROWSER_IMAGE" 2>/dev/null || echo "none")

echo "Pulling latest images..."
docker pull "$OPENCLAW_IMAGE"
docker pull "$BROWSER_IMAGE"
echo ""

# Get new digests
REMOTE_OCW=$(docker inspect --format='{{index .RepoDigests 0}}' "$OPENCLAW_IMAGE" 2>/dev/null || echo "none")
REMOTE_BRW=$(docker inspect --format='{{index .RepoDigests 0}}' "$BROWSER_IMAGE" 2>/dev/null || echo "none")

OCW_CHANGED=false
BRW_CHANGED=false
[[ "$LOCAL_OCW" != "$REMOTE_OCW" ]] && OCW_CHANGED=true
[[ "$LOCAL_BRW" != "$REMOTE_BRW" ]] && BRW_CHANGED=true

if [[ "$OCW_CHANGED" == false && "$BRW_CHANGED" == false ]]; then
  echo "Already up to date. Nothing to do."
  exit 0
fi

echo "Updates available:"
$OCW_CHANGED && echo "  openclaw:         new digest"
$BRW_CHANGED && echo "  stealth-browser:  new digest"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Would redeploy containers and prune old images."
  echo "[dry-run] Run without --dry-run to apply."
  exit 0
fi

echo "Redeploying..."
cd "$COMPOSE_DIR"
docker compose down
docker compose up -d
docker image prune -f >/dev/null 2>&1

echo ""
echo "Update complete."
UPDATER
chmod +x /usr/local/bin/openclawupdate

msg_ok "Installed openclawupdate CLI"

# =============================================================================
# MOTD / UPDATE SCRIPT
# =============================================================================

# Create /usr/bin/update for the ProxmoxVE helper update mechanism
cat <<'UPDATE_SCRIPT' >/usr/bin/update
#!/usr/bin/env bash
/usr/local/bin/openclawupdate "$@"
UPDATE_SCRIPT
chmod +x /usr/bin/update

motd_ssh
customize
cleanup_lxc
