#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly AURA_CONFIG=/etc/aura/deploy.env
readonly BACKUP_ROOT=/srv/aura/backups

if [[ ! -r "$AURA_CONFIG" ]]; then
  echo "Missing required file: $AURA_CONFIG" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$AURA_CONFIG"

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
rm -f "$archive" "$checksum"
