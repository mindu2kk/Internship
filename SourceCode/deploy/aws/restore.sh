#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly AURA_CONFIG=/etc/aura/deploy.env
readonly AURA_RUNTIME_ENV=/etc/aura/runtime.env
readonly AURA_COMPOSE=/srv/aura/docker-compose.aws.yml
readonly AURA_DATA_ROOT=/srv/aura/data

usage() {
  echo "Usage: aura-restore s3://<configured-backup-bucket>/daily/aura-<timestamp>.tar.gz" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
[[ -r "$AURA_CONFIG" ]] || { echo "Missing required file: $AURA_CONFIG" >&2; exit 1; }
[[ -r "$AURA_RUNTIME_ENV" && -r "$AURA_COMPOSE" ]] || {
  echo "A deployed runtime is required before restore." >&2
  exit 1
}

# shellcheck disable=SC1091
source "$AURA_CONFIG"
archive_uri="$1"
expected_prefix="s3://${BACKUP_BUCKET}/daily/aura-"
if [[ "$archive_uri" != "$expected_prefix"*.tar.gz ]]; then
  echo "Restore source must be a daily backup from the configured bucket." >&2
  exit 1
fi

restore_tmp="$(mktemp -d /srv/aura/restore.XXXXXX)"
cleanup() { rm -rf "$restore_tmp"; }
trap cleanup EXIT

archive_path="$restore_tmp/backup.tar.gz"
checksum_path="$archive_path.sha256"
AWS_USE_DUALSTACK_ENDPOINT=true aws s3 cp "$archive_uri" "$archive_path" --region "$AWS_REGION" --only-show-errors
AWS_USE_DUALSTACK_ENDPOINT=true aws s3 cp "${archive_uri}.sha256" "$checksum_path" --region "$AWS_REGION" --only-show-errors
sha256sum -c "$checksum_path"
tar -tzf "$archive_path" >/dev/null
tar -C "$restore_tmp" -xzf "$archive_path"
[[ -d "$restore_tmp/chroma" ]] || { echo "Backup does not contain the expected chroma directory." >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
previous_path="${AURA_DATA_ROOT}/chroma.pre-restore-${timestamp}"
had_previous=false
if [[ -d "${AURA_DATA_ROOT}/chroma" ]]; then
  had_previous=true
fi

# Do not replace a mounted Chroma directory while its writer is running.
docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" stop backend
if [[ "$had_previous" == true ]]; then
  mv "${AURA_DATA_ROOT}/chroma" "$previous_path"
fi
mv "$restore_tmp/chroma" "${AURA_DATA_ROOT}/chroma"

if docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" up -d --wait --remove-orphans \
  && curl --fail --retry 10 --retry-connrefused http://127.0.0.1:8080/healthz; then
  echo "Restore completed. Previous data, if present, is retained at: $previous_path"
  exit 0
fi

echo "Restore health check failed; restoring the previous Chroma data automatically." >&2
docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" stop backend || true
rm -rf "${AURA_DATA_ROOT}/chroma"
if [[ "$had_previous" == true ]]; then
  mv "$previous_path" "${AURA_DATA_ROOT}/chroma"
fi
docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" up -d --wait --remove-orphans
curl --fail --retry 10 --retry-connrefused http://127.0.0.1:8080/healthz
echo "Restore was reverted because the restored data did not become healthy." >&2
exit 1
