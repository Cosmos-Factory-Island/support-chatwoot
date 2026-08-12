#!/usr/bin/env bash
# Restaura un dump local de Chatwoot en el stack de Coolify.
# Ejecutar en el VPS, dentro del directorio del recurso support-chatwoot
# (o donde tengas acceso a `docker compose` del stack).
#
# Uso:
#   ./scripts/import-production.sh backups/chatwoot-YYYYMMDD-HHMMSS.sql
#   ./scripts/import-production.sh backups/chatwoot-YYYYMMDD-HHMMSS.sql backups/storage_data-YYYYMMDD-HHMMSS.tar.gz

set -euo pipefail

SQL_DUMP="${1:?Falta ruta al .sql (pg_dump)}"
STORAGE_ARCHIVE="${2:-}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"
DB_NAME="${POSTGRES_DATABASE:-chatwoot_production}"
DB_USER="${POSTGRES_USERNAME:-postgres}"

if [[ ! -f "$SQL_DUMP" ]]; then
  echo "No existe: $SQL_DUMP" >&2
  exit 1
fi

echo "==> Parando rails y sidekiq..."
docker compose -f "$COMPOSE_FILE" stop rails sidekiq || true

echo "==> Restaurando PostgreSQL ($DB_NAME)..."
docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
  || true

cat "$SQL_DUMP" | docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1

if [[ -n "$STORAGE_ARCHIVE" && -f "$STORAGE_ARCHIVE" ]]; then
  echo "==> Restaurando storage (adjuntos/avatares)..."
  docker run --rm \
    -v "$(docker volume ls -q | grep -E 'storage_data$' | head -1):/storage" \
    -v "$(realpath "$STORAGE_ARCHIVE"):/backup/archive.tar.gz:ro" \
    alpine sh -c "rm -rf /storage/* && tar xzf /backup/archive.tar.gz -C /storage"
fi

echo "==> Arrancando servicios..."
docker compose -f "$COMPOSE_FILE" up -d

echo ""
echo "Importación completada."
echo "Comprueba https://chat.huerto.bio y el Website Token en Settings → Inboxes."
echo "Usa el mismo SECRET_KEY_BASE que en local si quieres conservar sesiones cifradas."
