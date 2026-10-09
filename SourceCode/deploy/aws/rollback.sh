#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly AURA_CONFIG=/etc/aura/deploy.env
readonly AURA_RUNTIME_ENV=/etc/aura/runtime.env
readonly AURA_COMPOSE=/srv/aura/docker-compose.aws.yml
readonly AURA_RELEASES=/etc/aura/releases

usage() {
  echo "Usage: aura-rollback <release-snapshot.env>" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
[[ -r "$AURA_CONFIG" && -r "$AURA_RUNTIME_ENV" ]] || { echo "A deployed runtime is required before rollback." >&2; exit 1; }

release_name="$(basename "$1")"
[[ "$release_name" =~ ^release-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}\.env$ ]] || {
  echo "Invalid release snapshot name." >&2
  exit 1
}
snapshot_path="${AURA_RELEASES}/${release_name}"
[[ -r "$snapshot_path" ]] || { echo "Release snapshot was not found: $release_name" >&2; exit 1; }

# shellcheck disable=SC1091
source "$AURA_CONFIG"
install -d -m 0700 "$AURA_RELEASES"
current_id="release-$(date -u +%Y%m%dT%H%M%SZ)-rollback-from.env"
cp -p "$AURA_RUNTIME_ENV" "${AURA_RELEASES}/${current_id}"
cp -p "$snapshot_path" "$AURA_RUNTIME_ENV"
chmod 0600 "$AURA_RUNTIME_ENV"

docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" pull
docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" up -d --wait --remove-orphans
curl --fail --retry 10 --retry-connrefused http://127.0.0.1:8080/healthz
echo "Rollback completed from release snapshot: $release_name"
