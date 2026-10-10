#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly AURA_CONFIG=/etc/aura/deploy.env
readonly AURA_RUNTIME_ENV=/etc/aura/runtime.env
readonly AURA_COMPOSE=/srv/aura/docker-compose.aws.yml
readonly AURA_SECRET_PARAMETERS=/etc/aura/runtime-secret-parameters
readonly AURA_RELEASES=/etc/aura/releases

require_file() {
  if [[ ! -r "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

require_file "$AURA_CONFIG"
require_file "$AURA_COMPOSE"
require_file "$AURA_SECRET_PARAMETERS"

# shellcheck disable=SC1091
source "$AURA_CONFIG"

get_parameter() {
  AWS_USE_DUALSTACK_ENDPOINT=true aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$1" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text
}

backend_image="$(get_parameter "$BACKEND_RELEASE_PARAMETER")"
proxy_image="$(get_parameter "$PROXY_RELEASE_PARAMETER")"
frontend_url="$(get_parameter "$FRONTEND_URL_PARAMETER")"

if [[ "$backend_image" == "pending" || "$proxy_image" == "pending" ]]; then
  echo "Release image parameters are not set to reviewed immutable references." >&2
  exit 1
fi

if [[ "$backend_image" != *@sha256:* || "$proxy_image" != *@sha256:* ]]; then
  echo "All release images must be immutable digest references." >&2
  exit 1
fi

backend_path="${backend_image#*/}"
proxy_path="${proxy_image#*/}"
ecr_registry="${AWS_ACCOUNT_ID}.dkr-ecr.${AWS_REGION}.on.aws"

AWS_USE_DUALSTACK_ENDPOINT=true aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ecr_registry"
trap 'docker logout "$ecr_registry" >/dev/null 2>&1 || true' EXIT

install -d -m 0700 /srv/aura/data/chroma /srv/aura/logs
install -d -m 0700 "$AURA_RELEASES"

cat > "$AURA_RUNTIME_ENV" <<EOF
AWS_REGION=$AWS_REGION
AURA_LOG_GROUP=$AURA_LOG_GROUP
AURA_BACKEND_IMAGE=$ecr_registry/$backend_path
AURA_PROXY_IMAGE=$ecr_registry/$proxy_path
FRONTEND_URL=$frontend_url
EOF
while IFS='=' read -r environment_name parameter_name; do
  [[ -z "$environment_name" || -z "$parameter_name" ]] && continue
  printf '%s=%s\n' "$environment_name" "$(get_parameter "$parameter_name")" >> "$AURA_RUNTIME_ENV"
done < "$AURA_SECRET_PARAMETERS"
chmod 0600 "$AURA_RUNTIME_ENV"
release_digest="${backend_image##*@sha256:}"
release_id="release-$(date -u +%Y%m%dT%H%M%SZ)-${release_digest:0:12}.env"
unset frontend_url

export AURA_RUNTIME_ENV
docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" pull
docker compose --project-name aura --env-file "$AURA_RUNTIME_ENV" -f "$AURA_COMPOSE" up -d --wait --remove-orphans

# A container can be healthy while the reverse proxy is still accepting its
# first connections. Retry every transient curl failure, including a reset by
# peer, before declaring this immutable release usable.
for attempt in {1..15}; do
  if curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
    http://127.0.0.1:8080/healthz >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 15 ]]; then
    echo "Final local health check failed after $attempt attempts." >&2
    exit 1
  fi
  echo "Waiting for post-deploy health: $attempt/15" >&2
  sleep 4
done

# Keep rollback snapshots only for releases that have passed the final local
# health gate. A failed candidate must never become a rollback destination.
cp -p "$AURA_RUNTIME_ENV" "${AURA_RELEASES}/${release_id}"
find "$AURA_RELEASES" -maxdepth 1 -type f -name 'release-*.env' -printf '%T@ %p\n' \
  | sort -nr | tail -n +11 | cut -d' ' -f2- | xargs -r rm -f
echo "Release snapshot retained as: $release_id"
echo "DEPLOYMENT_OK release=$release_id backend_digest=${release_digest:0:12}"
