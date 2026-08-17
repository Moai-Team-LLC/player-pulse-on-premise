#!/usr/bin/env bash
# First-time setup for a Player Pulse on-premise installation.
# Run from inside the player-pulse-on-premise directory (alongside docker-compose.on-premise.yml).
#
# If pull/start fails partway through a first-time install, don't re-run this
# script plain — .env already exists and secrets shouldn't be regenerated.
# Instead run: ./install.sh --resume
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="docker-compose.on-premise.yml"
ENV_FILE=".env"

print_usage() {
  cat <<'USAGE'
Usage: ./install.sh [flags]

Runs interactively by default, prompting for anything not passed as a flag.
Pass all required flags to run fully non-interactively.

  --domain=...                   Domain for the main CRM
  --super-admin-domain=...       Domain for the super admin panel
  --license=...                  License key (provided at contract signing)

  --mail-provider=mailgun|smtp   Which mail provider to use

  --mailgun-domain=...           Mailgun domain
  --mailgun-api-key=...          Mailgun API key
  --mailgun-region=us|eu         Mailgun account region — check your Mailgun dashboard

  --smtp-host=...                SMTP server host
  --smtp-port=...                SMTP server port (defaults to 587 if left blank interactively)
  --smtp-username=...            SMTP username
  --smtp-password=...            SMTP password

  --mail-sender=...              Sender email, e.g. "Your Company <noreply@yourcompany.com>"
  --cors-origins=...             Optional, derived from the two domains above if omitted
  --s3-public-url=...            Optional, only needed for public file URLs
  --super-admin-email=...        Email for the initial super admin account

  --adapters=...                 Optional, comma-separated. Leave empty to run with none —
                                 you can add adapters later by editing COMPOSE_PROFILES in
                                 .env and running docker compose up -d.

  --api-port=...                 Host port for the API (defaults to 8000 if left blank interactively)
  --connector-port=...           Host port for the connector (defaults to 8001)
  --frontend-port=...            Host port for the CRM frontend (defaults to 3000)
  --superadmin-port=...          Host port for the super admin panel (defaults to 3001)
  --minio-port=...               Host port for the MinIO S3 API (defaults to 9000)
  --minio-console-port=...       Host port for the MinIO web console (defaults to 9001)
  --adapter-mailgun-port=...     Host port for the mailgun adapter (defaults to 8002)
  --adapter-voiso-port=...       Host port for the voiso adapter (defaults to 8003)
  --adapter-sms-retail-port=...  Host port for the sms-retail adapter (defaults to 8004)

  --resume                       Reuse an existing .env instead of generating a new one
                                 (use this to retry after a failed first-time install)

  --help, -h                     Show this message and exit
USAGE
}

# ── Flag parsing ──────────────────────────────────────────────────────────────
BASE_DOMAIN=""
SUPER_ADMIN_DOMAIN=""
LICENSE_KEY=""
MAIL_PROVIDER=""
MAILGUN_DOMAIN=""
MAILGUN_API_KEY=""
MAILGUN_REGION=""
SMTP_HOST=""
SMTP_PORT=""
SMTP_USERNAME=""
SMTP_PASSWORD=""
MAIL_SENDER_EMAIL=""
CORS_ORIGINS=""
S3_PUBLIC_URL=""
BOOTSTRAP_SUPER_ADMIN_EMAIL=""
ADAPTER_PROFILES=""
API_PORT=""
CONNECTOR_PORT=""
FRONTEND_PORT=""
SUPERADMIN_PORT=""
MINIO_PORT=""
MINIO_CONSOLE_PORT=""
ADAPTER_MAILGUN_PORT=""
ADAPTER_VOISO_PORT=""
ADAPTER_SMS_RETAIL_PORT=""
RESUME=false

for arg in "$@"; do
  case "$arg" in
    --domain=*) BASE_DOMAIN="${arg#*=}" ;;
    --super-admin-domain=*) SUPER_ADMIN_DOMAIN="${arg#*=}" ;;
    --license=*) LICENSE_KEY="${arg#*=}" ;;
    --mail-provider=*) MAIL_PROVIDER="${arg#*=}" ;;
    --mailgun-domain=*) MAILGUN_DOMAIN="${arg#*=}" ;;
    --mailgun-api-key=*) MAILGUN_API_KEY="${arg#*=}" ;;
    --mailgun-region=*) MAILGUN_REGION="${arg#*=}" ;;
    --smtp-host=*) SMTP_HOST="${arg#*=}" ;;
    --smtp-port=*) SMTP_PORT="${arg#*=}" ;;
    --smtp-username=*) SMTP_USERNAME="${arg#*=}" ;;
    --smtp-password=*) SMTP_PASSWORD="${arg#*=}" ;;
    --mail-sender=*) MAIL_SENDER_EMAIL="${arg#*=}" ;;
    --cors-origins=*) CORS_ORIGINS="${arg#*=}" ;;
    --s3-public-url=*) S3_PUBLIC_URL="${arg#*=}" ;;
    --super-admin-email=*) BOOTSTRAP_SUPER_ADMIN_EMAIL="${arg#*=}" ;;
    --adapters=*) ADAPTER_PROFILES="${arg#*=}" ;;
    --api-port=*) API_PORT="${arg#*=}" ;;
    --connector-port=*) CONNECTOR_PORT="${arg#*=}" ;;
    --frontend-port=*) FRONTEND_PORT="${arg#*=}" ;;
    --superadmin-port=*) SUPERADMIN_PORT="${arg#*=}" ;;
    --minio-port=*) MINIO_PORT="${arg#*=}" ;;
    --minio-console-port=*) MINIO_CONSOLE_PORT="${arg#*=}" ;;
    --adapter-mailgun-port=*) ADAPTER_MAILGUN_PORT="${arg#*=}" ;;
    --adapter-voiso-port=*) ADAPTER_VOISO_PORT="${arg#*=}" ;;
    --adapter-sms-retail-port=*) ADAPTER_SMS_RETAIL_PORT="${arg#*=}" ;;
    --resume) RESUME=true ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

# ── Prerequisites ─────────────────────────────────────────────────────────────
# Forwards whatever was already given via flags (empty is fine — preflight
# falls back to an existing .env, then documented defaults, for anything not
# passed here). On --resume this means preflight checks the real values
# already on disk, not just bare defaults.
echo "Checking prerequisites..."
echo

if ! ./preflight.sh \
  --domain="$BASE_DOMAIN" \
  --super-admin-domain="$SUPER_ADMIN_DOMAIN" \
  --adapters="$ADAPTER_PROFILES" \
  --api-port="$API_PORT" \
  --connector-port="$CONNECTOR_PORT" \
  --frontend-port="$FRONTEND_PORT" \
  --superadmin-port="$SUPERADMIN_PORT" \
  --minio-port="$MINIO_PORT" \
  --minio-console-port="$MINIO_CONSOLE_PORT" \
  --adapter-mailgun-port="$ADAPTER_MAILGUN_PORT" \
  --adapter-voiso-port="$ADAPTER_VOISO_PORT" \
  --adapter-sms-retail-port="$ADAPTER_SMS_RETAIL_PORT"
then
  echo >&2
  echo "Preflight found critical issues — fix them, then re-run ./install.sh." >&2
  exit 1
fi

echo
echo "Prerequisites OK."
echo

if [ "$RESUME" = true ]; then
  # ── Resume: reuse an existing .env, skip prompts and secret generation ──────
  if [ ! -f "$ENV_FILE" ]; then
    echo "$ENV_FILE not found — nothing to resume. Run install.sh without --resume for a first-time setup." >&2
    exit 1
  fi

  echo "Resuming with existing $ENV_FILE (no secrets regenerated)..."
  BASE_DOMAIN="$(grep '^BASE_DOMAIN=' "$ENV_FILE" | cut -d= -f2-)"
  SUPER_ADMIN_DOMAIN="$(grep '^SUPER_ADMIN_DOMAIN=' "$ENV_FILE" | cut -d= -f2-)"
  BOOTSTRAP_SUPER_ADMIN_EMAIL="$(grep '^BOOTSTRAP_SUPER_ADMIN_EMAIL=' "$ENV_FILE" | cut -d= -f2-)"
  BOOTSTRAP_SUPER_ADMIN_PASSWORD="$(grep '^BOOTSTRAP_SUPER_ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"
  echo
else
  # ── Interactive prompts (skipped if already set via flag) ────────────────────
  prompt() {
    local var_name="$1" prompt_text="$2" current_value="${!1}" input=""
    if [ -z "$current_value" ]; then
      read -r -p "$prompt_text: " input || true
      eval "$var_name=\"\$input\""
    fi
  }

  prompt_with_default() {
    local var_name="$1" prompt_text="$2" default_value="$3" current_value="${!1}" input=""
    if [ -z "$current_value" ]; then
      read -r -p "$prompt_text [$default_value]: " input || true
      eval "$var_name=\"\${input:-$default_value}\""
    fi
  }

  prompt BASE_DOMAIN "Domain for the main CRM (e.g. crm.client.com)"
  prompt SUPER_ADMIN_DOMAIN "Domain for the super admin panel (e.g. admin.client.com)"
  prompt LICENSE_KEY "License key (provided at contract signing)"

  prompt MAIL_PROVIDER "Mail provider (mailgun or smtp)"
  case "$MAIL_PROVIDER" in
    mailgun)
      prompt MAILGUN_DOMAIN "Mailgun domain"
      prompt MAILGUN_API_KEY "Mailgun API key"
      prompt MAILGUN_REGION "Mailgun region (us or eu — check your Mailgun dashboard)"
      ;;
    smtp)
      prompt SMTP_HOST "SMTP host (e.g. smtp.yourprovider.com)"
      if [ -z "$SMTP_PORT" ]; then
        read -r -p "SMTP port [587]: " input || true
        SMTP_PORT="${input:-587}"
      fi
      prompt SMTP_USERNAME "SMTP username"
      prompt SMTP_PASSWORD "SMTP password"
      ;;
    *)
      echo "MAIL_PROVIDER must be 'mailgun' or 'smtp', got: '$MAIL_PROVIDER'" >&2
      exit 1
      ;;
  esac

  prompt MAIL_SENDER_EMAIL "Sender email address for password reset emails"
  prompt BOOTSTRAP_SUPER_ADMIN_EMAIL "Email address for the initial super admin account"

  if [ -z "$ADAPTER_PROFILES" ]; then
    echo
    echo "Adapters are optional — you can skip this and add one later by editing"
    echo "COMPOSE_PROFILES in .env and running docker compose up -d."
    echo "Available: mailgun, voiso, sms-retail"
    read -r -p "Adapters to activate now (comma-separated, or blank to skip): " ADAPTER_PROFILES || true
  fi

  if [ -n "$ADAPTER_PROFILES" ]; then
    IFS=',' read -ra profiles <<< "$ADAPTER_PROFILES"
    for p in "${profiles[@]}"; do
      case "$p" in
        mailgun|voiso|sms-retail) ;;
        *)
          echo "Unknown adapter: '$p' — must be one of: mailgun, voiso, sms-retail" >&2
          exit 1
          ;;
      esac
    done
  fi

  echo
  echo "Host ports — press Enter to accept the default, or enter a different"
  echo "port if one of these is already taken on your server."
  prompt_with_default API_PORT "API port" 8000
  prompt_with_default CONNECTOR_PORT "Connector port" 8001
  prompt_with_default FRONTEND_PORT "Frontend port" 3000
  prompt_with_default SUPERADMIN_PORT "Super admin port" 3001
  prompt_with_default MINIO_PORT "MinIO S3 API port" 9000
  prompt_with_default MINIO_CONSOLE_PORT "MinIO console port" 9001
  if [[ ",$ADAPTER_PROFILES," == *",mailgun,"* ]]; then
    prompt_with_default ADAPTER_MAILGUN_PORT "Mailgun adapter port" 8002
  else
    ADAPTER_MAILGUN_PORT="${ADAPTER_MAILGUN_PORT:-8002}"
  fi
  if [[ ",$ADAPTER_PROFILES," == *",voiso,"* ]]; then
    prompt_with_default ADAPTER_VOISO_PORT "Voiso adapter port" 8003
  else
    ADAPTER_VOISO_PORT="${ADAPTER_VOISO_PORT:-8003}"
  fi
  if [[ ",$ADAPTER_PROFILES," == *",sms-retail,"* ]]; then
    prompt_with_default ADAPTER_SMS_RETAIL_PORT "SMS-RETAIL adapter port" 8004
  else
    ADAPTER_SMS_RETAIL_PORT="${ADAPTER_SMS_RETAIL_PORT:-8004}"
  fi

  # Every port must be unique, even across adapters you haven't activated yet
  # — otherwise activating one later, with a port that collides with something
  # already running, fails with a confusing Docker bind error at that point
  # instead of here, where it's easy to fix.
  port_names=(API_PORT CONNECTOR_PORT FRONTEND_PORT SUPERADMIN_PORT MINIO_PORT MINIO_CONSOLE_PORT ADAPTER_MAILGUN_PORT ADAPTER_VOISO_PORT ADAPTER_SMS_RETAIL_PORT)
  for ((i = 0; i < ${#port_names[@]}; i++)); do
    for ((j = i + 1; j < ${#port_names[@]}; j++)); do
      name_i="${port_names[i]}"
      name_j="${port_names[j]}"
      if [ "${!name_i}" = "${!name_j}" ]; then
        echo "Port conflict: $name_i and $name_j are both set to ${!name_i}." >&2
        echo "Every port must be different, even for an adapter you haven't" >&2
        echo "activated yet — pick a different value for one of them." >&2
        exit 1
      fi
    done
  done

  if [ -z "$CORS_ORIGINS" ]; then
    CORS_ORIGINS="https://${BASE_DOMAIN},https://${SUPER_ADMIN_DOMAIN}"
    echo "CORS_ORIGINS derived as: $CORS_ORIGINS"
  fi

  if [ -z "$S3_PUBLIC_URL" ]; then
    echo
    echo "S3_PUBLIC_URL is optional — only needed if you want uploaded files to be"
    echo "reachable directly from the browser (via your own reverse proxy in front"
    echo "of MinIO). Leave blank if you don't need public file URLs yet."
    read -r -p "MinIO public URL (optional, e.g. https://files.client.com): " S3_PUBLIC_URL || true
  fi

  # ── Validate required fields ────────────────────────────────────────────────
  missing=()
  [ -z "$BASE_DOMAIN" ] && missing+=("--domain (BASE_DOMAIN)")
  [ -z "$SUPER_ADMIN_DOMAIN" ] && missing+=("--super-admin-domain (SUPER_ADMIN_DOMAIN)")
  [ -z "$LICENSE_KEY" ] && missing+=("--license (LICENSE_KEY)")
  [ -z "$MAIL_PROVIDER" ] && missing+=("--mail-provider (MAIL_PROVIDER, mailgun or smtp)")
  if [ "$MAIL_PROVIDER" = "mailgun" ]; then
    [ -z "$MAILGUN_DOMAIN" ] && missing+=("--mailgun-domain (MAILGUN_DOMAIN)")
    [ -z "$MAILGUN_API_KEY" ] && missing+=("--mailgun-api-key (MAILGUN_API_KEY)")
    [ -z "$MAILGUN_REGION" ] && missing+=("--mailgun-region (MAILGUN_REGION, us or eu)")
  elif [ "$MAIL_PROVIDER" = "smtp" ]; then
    [ -z "$SMTP_HOST" ] && missing+=("--smtp-host (SMTP_HOST)")
    [ -z "$SMTP_PORT" ] && missing+=("--smtp-port (SMTP_PORT)")
    [ -z "$SMTP_USERNAME" ] && missing+=("--smtp-username (SMTP_USERNAME)")
    [ -z "$SMTP_PASSWORD" ] && missing+=("--smtp-password (SMTP_PASSWORD)")
  fi
  [ -z "$MAIL_SENDER_EMAIL" ] && missing+=("--mail-sender (MAIL_SENDER_EMAIL)")
  [ -z "$BOOTSTRAP_SUPER_ADMIN_EMAIL" ] && missing+=("--super-admin-email (BOOTSTRAP_SUPER_ADMIN_EMAIL)")

  if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing required value(s):" >&2
    for m in "${missing[@]}"; do
      echo "  - $m" >&2
    done
    exit 1
  fi

  echo
  echo "Generating secrets..."

  DB_PASSWORD="$(openssl rand -hex 32)"
  REDIS_PASSWORD="$(openssl rand -hex 32)"
  SIGNING_KEY="$(openssl rand -hex 32)"
  MAIL_SIGNING_KEY="$(openssl rand -hex 32)"
  PII_MASTER_KEY="$(openssl rand -hex 32)"
  ADAPTER_CREDENTIALS_MASTER_KEY="$(openssl rand -hex 32)"
  MINIO_ROOT_USER="$(openssl rand -hex 8)"
  MINIO_ROOT_PASSWORD="$(openssl rand -hex 32)"
  S3_ACCESS_KEY="$(openssl rand -hex 8)"
  S3_SECRET_KEY="$(openssl rand -hex 32)"
  BOOTSTRAP_SUPER_ADMIN_PASSWORD="$(openssl rand -hex 32)"

  echo "Secrets generated."
  echo

  # ── Write .env ────────────────────────────────────────────────────────────────
  if [ -f "$ENV_FILE" ]; then
    echo "$ENV_FILE already exists — refusing to overwrite." >&2
    echo "If a previous install failed after this point, run: ./install.sh --resume" >&2
    echo "Otherwise, remove $ENV_FILE first if you want to start over." >&2
    exit 1
  fi

  cat > "$ENV_FILE" <<EOF
LICENSE_KEY=${LICENSE_KEY}

API_PORT=${API_PORT}
CONNECTOR_PORT=${CONNECTOR_PORT}
FRONTEND_PORT=${FRONTEND_PORT}
SUPERADMIN_PORT=${SUPERADMIN_PORT}
MINIO_PORT=${MINIO_PORT}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT}
ADAPTER_MAILGUN_PORT=${ADAPTER_MAILGUN_PORT}
ADAPTER_VOISO_PORT=${ADAPTER_VOISO_PORT}
ADAPTER_SMS_RETAIL_PORT=${ADAPTER_SMS_RETAIL_PORT}

COMPOSE_PROFILES=${ADAPTER_PROFILES}

APP_PRODUCTION=true
LOGIN_VERIFICATION_ENABLED=true
BASE_DOMAIN=${BASE_DOMAIN}
SUPER_ADMIN_DOMAIN=${SUPER_ADMIN_DOMAIN}

CORS_ORIGINS=${CORS_ORIGINS}
CORS_HEADERS=Origin,Content-Type,Accept,Authorization
CORS_METHODS=GET,POST,PUT,PATCH,DELETE,OPTIONS

SERVER_READ_TIMEOUT=30s
SERVER_WRITE_TIMEOUT=30s
SERVER_IDLE_TIMEOUT=60s

# Set this once your reverse proxy is in place — see "Next steps" below.
TRUSTED_PROXIES=

DB_NAME=player_pulse
DB_USER=player_pulse
DB_PASSWORD=${DB_PASSWORD}
DB_MAX_CONNS=10
DB_MIN_CONNS=2
DB_MAX_CONN_LIFETIME=1h
DB_MAX_CONN_IDLE_TIME=30m

REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_USERNAME=
REDIS_MAX_MEMORY=256mb
REDIS_DB=0
REDIS_MAX_RETRIES=3
REDIS_MIN_RETRY_BACKOFF=8ms
REDIS_MAX_RETRY_BACKOFF=512ms
REDIS_DIAL_TIMEOUT=5s
REDIS_READ_TIMEOUT=3s
REDIS_WRITE_TIMEOUT=3s
REDIS_POOL_SIZE=10
REDIS_MIN_IDLE_CONNS=2
REDIS_MAX_CONN_AGE=1h
REDIS_POOL_TIMEOUT=4s
REDIS_IDLE_TIMEOUT=5m

SIGNING_KEY=${SIGNING_KEY}
ACCESS_TOKEN_EXPIRATION_DURATION=15m
REFRESH_TOKEN_EXPIRATION_DURATION=168h

BOOTSTRAP_SUPER_ADMIN_EMAIL=${BOOTSTRAP_SUPER_ADMIN_EMAIL}
BOOTSTRAP_SUPER_ADMIN_PASSWORD=${BOOTSTRAP_SUPER_ADMIN_PASSWORD}

PII_MASTER_KEY=${PII_MASTER_KEY}

ADAPTER_CREDENTIALS_MASTER_KEY=${ADAPTER_CREDENTIALS_MASTER_KEY}

S3_ENDPOINT=http://minio:9000
S3_REGION=us-east-1
S3_BUCKET=player-pulse
S3_USE_ACL=false
S3_PUBLIC_URL=${S3_PUBLIC_URL}

MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
S3_ACCESS_KEY=${S3_ACCESS_KEY}
S3_SECRET_KEY=${S3_SECRET_KEY}

MAIL_PROVIDER=${MAIL_PROVIDER}
MAIL_SENDER_EMAIL=${MAIL_SENDER_EMAIL}
MAIL_SIGNING_KEY=${MAIL_SIGNING_KEY}
MAIL_RESET_EXPIRATION_DURATION=4h

MAILGUN_DOMAIN=${MAILGUN_DOMAIN}
MAILGUN_API_KEY=${MAILGUN_API_KEY}
MAILGUN_REGION=${MAILGUN_REGION}

SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_PASSWORD=${SMTP_PASSWORD}

RATE_LIMIT_IP_MAX=10
RATE_LIMIT_IP_WINDOW=1m
RATE_LIMIT_USER_MAX=300
RATE_LIMIT_USER_WINDOW=1m
RATE_LIMIT_PROJECT_MAX=1000
RATE_LIMIT_PROJECT_WINDOW=1m
EOF

  chmod 600 "$ENV_FILE"
  echo ".env written."
  echo

  # ── PII master key warning ────────────────────────────────────────────────────
  echo "########################################################################"
  echo "# IMPORTANT: BACK UP YOUR PII_MASTER_KEY NOW                          #"
  echo "#                                                                      #"
  echo "# This key encrypts all player PII data. If it is lost, that data     #"
  echo "# cannot be recovered — not by you, not by us. Store it somewhere     #"
  echo "# safe outside this server (password manager, vault, etc).            #"
  echo "#                                                                      #"
  echo "# PII_MASTER_KEY=${PII_MASTER_KEY}"
  echo "########################################################################"
  echo
fi

# ── Pull images and start ─────────────────────────────────────────────────────
echo "Pulling images..."
docker compose -f "$COMPOSE_FILE" pull

echo "Starting services..."
docker compose -f "$COMPOSE_FILE" up -d

# ── Health check ──────────────────────────────────────────────────────────────
echo "Waiting for API to become healthy..."
API_PORT_VALUE="$(grep '^API_PORT=' "$ENV_FILE" | cut -d= -f2-)"
FRONTEND_PORT_VALUE="$(grep '^FRONTEND_PORT=' "$ENV_FILE" | cut -d= -f2-)"
SUPERADMIN_PORT_VALUE="$(grep '^SUPERADMIN_PORT=' "$ENV_FILE" | cut -d= -f2-)"
MINIO_CONSOLE_PORT_VALUE="$(grep '^MINIO_CONSOLE_PORT=' "$ENV_FILE" | cut -d= -f2-)"

HEALTHY=false
for _ in $(seq 1 30); do
  if curl -sf "http://localhost:${API_PORT_VALUE}/api/v1/healthcheck" >/dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 2
done

if [ "$HEALTHY" != true ]; then
  echo
  echo "API did not become healthy in time." >&2
  echo "Check logs with: docker compose -f ${COMPOSE_FILE} logs api" >&2
  echo "Once fixed, retry without regenerating secrets: ./install.sh --resume" >&2
  exit 1
fi

echo "API is healthy."

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "########################################################################"
echo "# Installation complete                                                #"
echo "########################################################################"
echo
echo "Local access (before reverse proxy / domain routing is set up):"
echo "  CRM:           http://localhost:${FRONTEND_PORT_VALUE:-3000}"
echo "  Super admin:   http://localhost:${SUPERADMIN_PORT_VALUE:-3001}"
echo "  API:           http://localhost:${API_PORT_VALUE}"
echo "  MinIO console: http://localhost:${MINIO_CONSOLE_PORT_VALUE:-9001}"
echo
echo "Log in with:"
echo "  Email:    ${BOOTSTRAP_SUPER_ADMIN_EMAIL}"
echo "  Password: ${BOOTSTRAP_SUPER_ADMIN_PASSWORD}"
echo "  (change this password immediately after your first login)"
echo
echo "Next steps:"
echo "  - Set up your reverse proxy and SSL for ${BASE_DOMAIN} and ${SUPER_ADMIN_DOMAIN}"
echo "  - Set TRUSTED_PROXIES in .env to your reverse proxy's IP/CIDR, then restart:"
echo "      docker compose -f ${COMPOSE_FILE} up -d --force-recreate api connector"
echo "    Without this, login/audit logs will show your proxy's IP instead of your users'."
echo "  - Back up your PII_MASTER_KEY externally if you haven't already"
echo "  - Back up your .env file — it contains all secrets"