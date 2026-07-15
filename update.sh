#!/usr/bin/env bash
# Updates an existing Player Pulse on-premise installation to a specific bundle version.
# Usage: ./update.sh 1.4.2
#
# Downloads that release's docker-compose.on-premise.yml (the version manifest for the bundle),
# replaces the local one, pulls new images, and restarts. Migrations run automatically
# on startup via the migrations service already defined in the compose file.
#
# Rollback: run ./update.sh with the previous bundle version.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPO="Moai-Team-LLC/player-pulse-on-premise"
COMPOSE_FILE="docker-compose.on-premise.yml"
BACKUP_FILE="docker-compose.on-premise.yml.bak"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: ./update.sh <version>" >&2
  echo "Example: ./update.sh 1.4.2" >&2
  exit 1
fi

if [ ! -f ".env" ]; then
  echo ".env not found — this doesn't look like an existing installation." >&2
  echo "Run ./install.sh first to set up a new installation." >&2
  exit 1
fi

TAG="v${VERSION}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${COMPOSE_FILE}"

echo "Fetching compose file for bundle ${VERSION}..."
TMP_FILE="$(mktemp)"

if ! curl -sfL "$DOWNLOAD_URL" -o "$TMP_FILE"; then
  echo "Failed to download ${COMPOSE_FILE} for release ${TAG}." >&2
  echo "Check that ${TAG} exists at: https://github.com/${REPO}/releases" >&2
  rm -f "$TMP_FILE"
  exit 1
fi

echo "Downloaded successfully."

if [ -f "$COMPOSE_FILE" ]; then
  cp "$COMPOSE_FILE" "$BACKUP_FILE"
  echo "Backed up current compose file to ${BACKUP_FILE}."
fi

mv "$TMP_FILE" "$COMPOSE_FILE"
echo "Replaced ${COMPOSE_FILE} with bundle ${VERSION}."
echo

# Include a private adapter override file automatically if one exists in this directory.
COMPOSE_ARGS=(-f "$COMPOSE_FILE")
OVERRIDE_FILE="$(ls ./*.override.yml 2>/dev/null | head -n1 || true)"
if [ -n "$OVERRIDE_FILE" ]; then
  echo "Found private adapter override: ${OVERRIDE_FILE}"
  COMPOSE_ARGS+=(-f "$OVERRIDE_FILE")
fi

echo "Pulling new images..."
docker compose "${COMPOSE_ARGS[@]}" pull

echo "Restarting services..."
docker compose "${COMPOSE_ARGS[@]}" up -d

# ── Health check ──────────────────────────────────────────────────────────────
echo "Waiting for API to become healthy..."
API_PORT_VALUE="$(grep '^API_PORT=' .env | cut -d= -f2)"

HEALTHY=false
for _ in $(seq 1 30); do
  if curl -sf "http://localhost:${API_PORT_VALUE}/api/v1/healthcheck" >/dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 2
done

echo
if [ "$HEALTHY" = true ]; then
  echo "Update to ${VERSION} complete. API is healthy."
else
  echo "Update to ${VERSION} finished, but API did not become healthy in time." >&2
  echo "Check logs with: docker compose ${COMPOSE_ARGS[*]} logs api" >&2
  echo "To roll back: mv ${BACKUP_FILE} ${COMPOSE_FILE} && docker compose ${COMPOSE_ARGS[*]} up -d" >&2
  exit 1
fi