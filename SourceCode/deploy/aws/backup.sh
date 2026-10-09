#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly AURA_CONFIG=/etc/aura/deploy.env
readonly AURA_RUNTIME_ENV=/etc/aura/runtime.env
readonly AURA_COMPOSE=/srv/aura/docker-compose.aws.yml
readonly BACKUP_ROOT=/srv/aura/backups

if [[ ! -r "$AURA_CONFIG" ]]; then
  echo "Missing required file: $AURA_CONFIG" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$AURA_CONFIG"

[[ -r "$AURA_RUNTIME_ENV" && -r "$AURA_COMPOSE" ]] || {
  echo "A deployed runtime is required before a consistent backup can be created." >&2
  exit 1
}

runtime_stopped=false
restart_runtime() {
  if [[ "$runtime_stopped" == true ]]; then
    docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" up -d --wait --remove-orphans
    curl --fail --retry 10 --retry-connrefused http://127.0.0.1:8080/healthz
    runtime_stopped=false
  fi
}

# Chroma is file-backed. Stop its only writer briefly so the archive is a
# consistent recovery point instead of a potentially torn live copy.
docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" stop backend
runtime_stopped=true
trap 'status=$?; restart_runtime || true; exit "$status"' EXIT

install -d -m 0700 "$BACKUP_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$BACKUP_ROOT/aura-$timestamp.tar.gz"
checksum="$archive.sha256"

tar -C /srv/aura/data -czf "$archive" chroma
sha256sum "$archive" > "$checksum"
AWS_USE_DUALSTACK_ENDPOINT=true aws s3 cp "$archive" "s3://$BACKUP_BUCKET/daily/aura-$timestamp.tar.gz" \
  --region "$AWS_REGION" \
  --sse AES256 \
  --only-show-errors
AWS_USE_DUALSTACK_ENDPOINT=true aws s3 cp "$checksum" "s3://$BACKUP_BUCKET/daily/aura-$timestamp.tar.gz.sha256" \
  --region "$AWS_REGION" \
  --sse AES256 \
  --only-show-errors
restart_runtime
rm -f "$archive" "$checksum"
