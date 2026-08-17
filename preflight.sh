#!/usr/bin/env bash
# Checks whether this server is ready to run Player Pulse on-premise.
#
# Every check always runs, regardless of earlier results — you always see the
# full picture in one pass, not just the first thing that's wrong. Read-only,
# no side effects, safe to run repeatedly, and does not require Docker to
# already be working (that's one of the things it checks). Run this standalone,
# any time — days before you actually install, or right before.
#
# Usage:
#   ./preflight.sh
#   ./preflight.sh --adapters=mailgun,voiso
#   ./preflight.sh --domain=crm.client.com --super-admin-domain=admin.client.com
#
# Port values: flag (if given) > existing .env (if one exists) > documented
# default. Adapter ports are only checked if you pass --adapters=... or an
# existing .env already has COMPOSE_PROFILES set — otherwise they're skipped
# and it says so, rather than checking ports for adapters nobody's using yet.
#
# Exit code: 0 if no critical issues were found, 1 if any were. Warnings never
# affect the exit code.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

ENV_FILE=".env"
COMPOSE_FILE="docker-compose.on-premise.yml"

print_usage() {
  cat <<'USAGE'
Usage: ./preflight.sh [flags]

  --adapters=...                 Comma-separated, check these adapters' ports too
                                 (mailgun, voiso, sms-retail)
  --domain=...                   Check DNS for the main CRM domain
  --super-admin-domain=...       Check DNS for the super admin domain

  --api-port=...                 Host port to check for the API (defaults to 8000)
  --connector-port=...           Host port to check for the connector (defaults to 8001)
  --frontend-port=...            Host port to check for the frontend (defaults to 3000)
  --superadmin-port=...          Host port to check for the super admin panel (defaults to 3001)
  --minio-port=...               Host port to check for the MinIO S3 API (defaults to 9000)
  --minio-console-port=...       Host port to check for the MinIO console (defaults to 9001)
  --adapter-mailgun-port=...     Host port to check for the mailgun adapter (defaults to 8002)
  --adapter-voiso-port=...       Host port to check for the voiso adapter (defaults to 8003)
  --adapter-sms-retail-port=...  Host port to check for the sms-retail adapter (defaults to 8004)

  --help, -h                     Show this message and exit
USAGE
}

ADAPTER_PROFILES=""
DOMAIN=""
SUPER_ADMIN_DOMAIN=""
API_PORT="" CONNECTOR_PORT="" FRONTEND_PORT="" SUPERADMIN_PORT=""
MINIO_PORT="" MINIO_CONSOLE_PORT=""
ADAPTER_MAILGUN_PORT="" ADAPTER_VOISO_PORT="" ADAPTER_SMS_RETAIL_PORT=""

# shellcheck disable=SC2034  # the port vars set below are dereferenced indirectly via "${!name}" in the port-checking loops further down
for arg in "$@"; do
  case "$arg" in
    --adapters=*) ADAPTER_PROFILES="${arg#*=}" ;;
    --domain=*) DOMAIN="${arg#*=}" ;;
    --super-admin-domain=*) SUPER_ADMIN_DOMAIN="${arg#*=}" ;;
    --api-port=*) API_PORT="${arg#*=}" ;;
    --connector-port=*) CONNECTOR_PORT="${arg#*=}" ;;
    --frontend-port=*) FRONTEND_PORT="${arg#*=}" ;;
    --superadmin-port=*) SUPERADMIN_PORT="${arg#*=}" ;;
    --minio-port=*) MINIO_PORT="${arg#*=}" ;;
    --minio-console-port=*) MINIO_CONSOLE_PORT="${arg#*=}" ;;
    --adapter-mailgun-port=*) ADAPTER_MAILGUN_PORT="${arg#*=}" ;;
    --adapter-voiso-port=*) ADAPTER_VOISO_PORT="${arg#*=}" ;;
    --adapter-sms-retail-port=*) ADAPTER_SMS_RETAIL_PORT="${arg#*=}" ;;
    --help|-h) print_usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ── Resolve values: flag > existing .env > documented default ──────────────
env_value() {
  [ -f "$ENV_FILE" ] && grep "^$1=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-
}

resolve() {
  local var_name="$1" default_value="$2" current="${!1}" from_env
  if [ -n "$current" ]; then return; fi
  # shellcheck disable=SC2034  # from_env is referenced inside the eval string below, which shellcheck can't trace
  from_env="$(env_value "$var_name")"
  eval "$var_name=\"\${from_env:-$default_value}\""
}

resolve API_PORT 8000
resolve CONNECTOR_PORT 8001
resolve FRONTEND_PORT 3000
resolve SUPERADMIN_PORT 3001
resolve MINIO_PORT 9000
resolve MINIO_CONSOLE_PORT 9001
resolve ADAPTER_MAILGUN_PORT 8002
resolve ADAPTER_VOISO_PORT 8003
resolve ADAPTER_SMS_RETAIL_PORT 8004

if [ -z "$ADAPTER_PROFILES" ]; then
  ADAPTER_PROFILES="$(env_value COMPOSE_PROFILES)"
fi
if [ -z "$DOMAIN" ]; then DOMAIN="$(env_value BASE_DOMAIN)"; fi
if [ -z "$SUPER_ADMIN_DOMAIN" ]; then SUPER_ADMIN_DOMAIN="$(env_value SUPER_ADMIN_DOMAIN)"; fi

# ── Result tracking — every check runs no matter what came before ──────────
CRITICAL_FAILS=()
WARNINGS=()

pass() { echo "  ✅ $1"; }
warn() { echo "  ⚠️  $1"; WARNINGS+=("$1"); }
fail() { echo "  ❌ $1"; CRITICAL_FAILS+=("$1"); }

echo "Player Pulse — preflight check"
echo "==============================="

# ── Docker ───────────────────────────────────────────────────────────────────
echo
echo "Docker"
DOCKER_INSTALLED=false
if command -v docker >/dev/null 2>&1; then
  DOCKER_INSTALLED=true
  pass "Docker is installed"
else
  fail "Docker is not installed — see https://docs.docker.com/engine/install/"
fi

DOCKER_UP=false
if [ "$DOCKER_INSTALLED" = true ] && docker info >/dev/null 2>&1; then
  DOCKER_UP=true
  pass "Docker daemon is running and reachable"
elif [ "$DOCKER_INSTALLED" = true ]; then
  if getent group docker >/dev/null 2>&1 && ! id -nG "$(id -un)" 2>/dev/null | grep -qw docker; then
    fail "Docker daemon not reachable — your user isn't in the 'docker' group. Run: sudo usermod -aG docker \$USER, then log out and back in"
  else
    fail "Docker daemon not reachable — is it running? Try: sudo systemctl start docker"
  fi
else
  fail "Docker daemon check skipped — Docker isn't installed"
fi

if [ "$DOCKER_UP" = true ] && docker compose version >/dev/null 2>&1; then
  pass "Docker Compose v2 is available"
else
  fail "Docker Compose v2 plugin not found (the legacy standalone docker-compose doesn't count) — see https://docs.docker.com/compose/install/"
fi

# ── Tools ────────────────────────────────────────────────────────────────────
echo
echo "Tools"
if command -v openssl >/dev/null 2>&1; then pass "openssl is installed"; else fail "openssl is not installed"; fi
if command -v curl >/dev/null 2>&1; then pass "curl is installed"; else fail "curl is not installed"; fi

# ── Architecture ─────────────────────────────────────────────────────────────
echo
echo "Architecture"
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) pass "Architecture is amd64 ($arch)" ;;
  *) fail "Architecture is $arch — Player Pulse images are currently published for amd64 only; this server cannot run them" ;;
esac

# ── Registry connectivity ───────────────────────────────────────────────────
echo
echo "Registry connectivity"
if command -v curl >/dev/null 2>&1; then
  status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 https://ghcr.io/v2/ 2>/dev/null || echo "000")"
  if [ "$status" != "000" ]; then
    pass "ghcr.io is reachable (HTTP $status)"
  else
    fail "ghcr.io is not reachable — image pulls will fail. Check outbound firewall rules (port 443 to ghcr.io)"
  fi
else
  fail "Registry connectivity check skipped — curl isn't installed"
fi

# ── Disk space ───────────────────────────────────────────────────────────────
echo
echo "Disk space"
avail_kb="$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${avail_kb:-}" ]; then
  avail_gb=$(( avail_kb / 1024 / 1024 ))
  if [ "$avail_gb" -lt 10 ]; then
    warn "Only ${avail_gb}GB free disk space — Postgres, Redis, MinIO, and pulled images add up quickly. 10GB+ recommended"
  else
    pass "Disk space: ${avail_gb}GB free"
  fi
else
  warn "Could not determine free disk space"
fi

# ── Memory ───────────────────────────────────────────────────────────────────
echo
echo "Memory"
if [ -r /proc/meminfo ]; then
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  mem_gb=$(( mem_kb / 1024 / 1024 ))
  if [ "$mem_gb" -lt 2 ]; then
    warn "Only ${mem_gb}GB total memory — 2GB+ recommended for the full stack plus any adapters you activate"
  else
    pass "Memory: ${mem_gb}GB total"
  fi
else
  warn "Could not determine total memory (not on Linux, or /proc/meminfo unavailable)"
fi

# ── DNS ──────────────────────────────────────────────────────────────────────
echo
echo "DNS"
check_dns() {
  local domain="$1" label="$2"
  [ -z "$domain" ] && return
  if command -v getent >/dev/null 2>&1 && getent hosts "$domain" >/dev/null 2>&1; then
    pass "$label ($domain) resolves"
  elif command -v host >/dev/null 2>&1 && host "$domain" >/dev/null 2>&1; then
    pass "$label ($domain) resolves"
  else
    warn "$label ($domain) does not resolve yet — fine if you haven't pointed DNS at this server yet"
  fi
}
if [ -n "$DOMAIN" ] || [ -n "$SUPER_ADMIN_DOMAIN" ]; then
  check_dns "$DOMAIN" "Main CRM domain"
  check_dns "$SUPER_ADMIN_DOMAIN" "Super admin domain"
else
  echo "  (skipped — no domain known; pass --domain=... to check)"
fi

# ── Previous install artifacts ──────────────────────────────────────────────
echo
echo "Previous install attempts"
if [ "$DOCKER_UP" = true ] && [ -f "$COMPOSE_FILE" ]; then
  existing="$(docker compose -f "$COMPOSE_FILE" ps -a --format '{{.Name}}' 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    warn "Found containers from a previous attempt: $(echo "$existing" | tr '\n' ' ')— docker compose up -d will reuse/recreate these, fine for a legitimate retry, but worth knowing if this should be a fresh install"
  else
    pass "No leftover containers from a previous attempt"
  fi
else
  echo "  (skipped — Docker not reachable, or $COMPOSE_FILE not found here)"
fi

# ── Ports ────────────────────────────────────────────────────────────────────
echo
echo "Ports"

port_names=(API_PORT CONNECTOR_PORT FRONTEND_PORT SUPERADMIN_PORT MINIO_PORT MINIO_CONSOLE_PORT)
port_labels=("API" "Connector" "Frontend" "Super admin" "MinIO S3 API" "MinIO console")

if [ -n "$ADAPTER_PROFILES" ]; then
  if [[ ",$ADAPTER_PROFILES," == *",mailgun,"* ]]; then
    port_names+=(ADAPTER_MAILGUN_PORT); port_labels+=("Mailgun adapter")
  fi
  if [[ ",$ADAPTER_PROFILES," == *",voiso,"* ]]; then
    port_names+=(ADAPTER_VOISO_PORT); port_labels+=("Voiso adapter")
  fi
  if [[ ",$ADAPTER_PROFILES," == *",sms-retail,"* ]]; then
    port_names+=(ADAPTER_SMS_RETAIL_PORT); port_labels+=("SMS-RETAIL adapter")
  fi
else
  echo "  (adapter ports not checked — no --adapters=... given and no COMPOSE_PROFILES in an existing .env)"
fi

# Validity + uniqueness — critical: these are deterministic config bugs, not
# time-sensitive external state, so they're worth failing hard on.
invalid_found=false
for name in "${port_names[@]}"; do
  value="${!name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    fail "$name is not a valid port number: '$value'"
    invalid_found=true
  fi
done

conflict_found=false
for ((i = 0; i < ${#port_names[@]}; i++)); do
  for ((j = i + 1; j < ${#port_names[@]}; j++)); do
    name_i="${port_names[i]}"; name_j="${port_names[j]}"
    if [ "${!name_i}" = "${!name_j}" ]; then
      fail "${port_labels[i]} and ${port_labels[j]} are both set to ${!name_i} — every port must be different"
      conflict_found=true
    fi
  done
done
if [ "$invalid_found" = false ] && [ "$conflict_found" = false ]; then
  pass "No port conflicts among ${#port_names[@]} checked ports"
fi

# Freeness — warning only: this is a point-in-time snapshot of the host, not
# a property of the configuration itself, so it can't be a hard blocker.
TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout 1"
for i in "${!port_names[@]}"; do
  name="${port_names[i]}"; label="${port_labels[i]}"; port="${!name}"
  [[ "$port" =~ ^[0-9]+$ ]] || continue
  if $TIMEOUT_BIN bash -c "(exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null"; then
    warn "$label port $port appears to already be in use on this host"
  else
    pass "$label port $port is free"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo
echo "==============================="
if [ ${#CRITICAL_FAILS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
  echo "All checks passed. This server is ready."
elif [ ${#CRITICAL_FAILS[@]} -eq 0 ]; then
  echo "No critical issues. ${#WARNINGS[@]} warning(s) above — worth a look, but you can proceed."
else
  echo "${#CRITICAL_FAILS[@]} critical issue(s) — fix these before running install.sh:"
  for f in "${CRITICAL_FAILS[@]}"; do
    echo "  ❌ $f"
  done
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo
    echo "${#WARNINGS[@]} warning(s) also found — see above."
  fi
fi
echo

[ ${#CRITICAL_FAILS[@]} -eq 0 ]