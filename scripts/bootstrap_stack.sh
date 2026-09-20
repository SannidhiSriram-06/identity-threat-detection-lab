#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting Identity Threat Detection Lab stack bootstrap..."

# Locate environment file
ENV_FILE="/opt/identity-lab/lab.env"
if [ ! -f "$ENV_FILE" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  if [ -f "$REPO_DIR/lab.env" ]; then
    ENV_FILE="$REPO_DIR/lab.env"
  fi
fi

if [ -f "$ENV_FILE" ]; then
  log "Loading environment configuration from $ENV_FILE"
  # shellcheck source=/dev/null
  source "$ENV_FILE"
else
  log "ERROR: lab.env configuration file not found at $ENV_FILE" >&2
  exit 1
fi

: "${CLOUDTRAIL_BUCKET:?Environment variable CLOUDTRAIL_BUCKET must be set in lab.env}"
: "${AWS_REGION:?Environment variable AWS_REGION must be set in lab.env}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR/docker"

# Ensure Wazuh Indexer TLS certificates exist
if [ ! -d "config/wazuh_indexer_ssl_certs" ] || [ -z "$(ls -A config/wazuh_indexer_ssl_certs 2>/dev/null)" ]; then
  log "Generating Wazuh Indexer SSL certificates..."
  docker compose -f generate-indexer-certs.yml run --rm generator
else
  log "Wazuh Indexer SSL certificates exist, skipping generation."
fi

# Render wazuh_manager.conf from template
log "Rendering wazuh_manager.conf from template with CLOUDTRAIL_BUCKET=${CLOUDTRAIL_BUCKET}..."
sed "s/__CLOUDTRAIL_BUCKET__/${CLOUDTRAIL_BUCKET}/g" config/wazuh_cluster/wazuh_manager.conf.tpl > config/wazuh_cluster/wazuh_manager.conf

# Start stack
log "Starting services via Docker Compose..."
docker compose up -d

# Wait up to 8 minutes for Indexer and Dashboard to become responsive
log "Polling stack readiness (up to 8 minutes)..."
MAX_WAIT=480
INTERVAL=10
ELAPSED=0
INDEXER_READY=false
DASHBOARD_READY=false

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  if [ "$INDEXER_READY" = false ]; then
    if curl -sk -u admin:SecretPassword https://localhost:9200 2>/dev/null | grep -q "cluster_name"; then
      log "Wazuh Indexer is healthy and responding with cluster metadata."
      INDEXER_READY=true
    fi
  fi

  if [ "$DASHBOARD_READY" = false ]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" https://localhost:443 2>/dev/null || true)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
      log "Wazuh Dashboard is responding on https://localhost:443 (HTTP ${HTTP_CODE})."
      DASHBOARD_READY=true
    fi
  fi

  if [ "$INDEXER_READY" = true ] && [ "$DASHBOARD_READY" = true ]; then
    log "All Wazuh services are ready."
    break
  fi

  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
  log "Awaiting services... ${ELAPSED}s / ${MAX_WAIT}s elapsed (Indexer: $INDEXER_READY, Dashboard: $DASHBOARD_READY)"
done

if [ "$INDEXER_READY" = false ] || [ "$DASHBOARD_READY" = false ]; then
  log "WARNING: Readiness timeout reached (${MAX_WAIT}s). Some services may still be initializing."
fi

log "Docker Compose container status:"
docker compose ps
