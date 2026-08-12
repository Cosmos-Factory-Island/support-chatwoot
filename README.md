# support-chatwoot

Stack Docker independiente de [Chatwoot](https://www.chatwoot.com/) para soporte humano en [Huerto.Bio](https://huerto.bio).

- **Repositorio**: `Cosmos-Factory-Island/support-chatwoot`
- **Integración frontend**: monorepo `edge-huertobio` (`/mi-espacio`)
- **Issue**: [THE-6](https://linear.app/the-klift/issue/THE-6)

## Estructura

| Archivo | Uso |
| --- | --- |
| `docker-compose.yaml` | Producción / **Coolify** |
| `docker-compose.local.yaml` | Solo desarrollo local (Caddy + Mailpit) |
| `Caddyfile` | HTTPS local (`chatwoot.localhost`) |
| `.env.example` | Plantilla de variables (copiar a `.env`) |
| `scripts/export-local.ps1` | Exportar BD + storage desde local |
| `scripts/import-production.sh` | Restaurar en Coolify/VPS |

> **Coolify** despliega únicamente `docker-compose.yaml`. El overlay local no interfiere porque no usamos `docker-compose.override.yaml` (auto-cargado por Compose).

## Desarrollo local

```powershell
cd D:\Work\Proyectos\HuertoBio\tools\support-chatwoot

copy .env.example .env
# Editar .env: descomentar bloque "Desarrollo local" (FRONTEND_URL, mailpit, etc.)

docker compose -f docker-compose.yaml -f docker-compose.local.yaml up -d

# Migración inicial (solo la primera vez)
docker compose -f docker-compose.yaml -f docker-compose.local.yaml run --rm rails bundle exec rails db:chatwoot_prepare
```

- Panel: https://chatwoot.localhost
- Mailpit: https://mail.chatwoot.localhost

## Despliegue en Coolify

Dentro del **mismo proyecto Coolify** de Huerto.Bio, añadir un recurso Docker Compose adicional:

```
Proyecto Coolify: Huerto.Bio
├── edge-huertobio        → docker-compose.prod.yaml
└── support-chatwoot      → docker-compose.yaml (este repo)
```

### Pasos

1. DNS `A`/`AAAA` → `chat.huerto.bio`
2. Coolify → proyecto **Huerto.Bio** → **+ New Resource** → **Docker Compose**
3. Repo: `Cosmos-Factory-Island/support-chatwoot`, rama `main`
4. Compose file: `/docker-compose.yaml`
5. En **Domains for rails** introducir exactamente
   `https://chat.huerto.bio:3000`.
   - `:3000` especifica el puerto HTTP interno de Puma; no se expone como
     puerto público.
   - Coolify/Traefik termina TLS y solicita el certificado para
     `chat.huerto.bio`; Puma recibe HTTP plano.
   - Deja vacíos los dominios de `sidekiq` y cualquier otro servicio interno.
   - Mantener `FORCE_SSL=true`: el healthcheck declara
     `X-Forwarded-Proto: https` para no seguir un redirect TLS contra Puma.
6. Variables de entorno (desde `.env.example`, valores de producción)
   - `FRONTEND_URL=https://chat.huerto.bio` (sin `:3000`)
7. Deploy → migración (una vez):

   ```bash
   docker compose run --rm rails bundle exec rails db:chatwoot_prepare
   ```

8. Crear super-admin → **Settings → Inboxes → Website** → copiar **Website Token**
9. **Allowed Domains**: `huerto.bio`, `www.huerto.bio`, `beta.huerto.bio`, `staging.huerto.bio`, `localhost`
10. Configurar en `edge-huertobio`:
    - `PUBLIC_CHATWOOT_BASE_URL=https://chat.huerto.bio`
    - `PUBLIC_CHATWOOT_WEBSITE_TOKEN=<token>`

### Variables críticas (producción)

Configurar en Coolify → **Environment Variables** (no hace falta subir un `.env` al servidor):

| Variable | Valor |
| --- | --- |
| `FRONTEND_URL` | `https://chat.huerto.bio` |
| `SECRET_KEY_BASE` | `openssl rand -hex 64` |
| `POSTGRES_PASSWORD` | contraseña fuerte |
| `POSTGRES_USERNAME` | `postgres` (opcional, default) |
| `POSTGRES_DATABASE` | `chatwoot_production` (opcional, default) |
| `REDIS_PASSWORD` | contraseña fuerte |
| `ENABLE_ACCOUNT_SIGNUP` | `false` |
| `CHATWOOT_IMAGE_TAG` | `v4.16.2` (opcional; default en compose) |

> Si el deploy falla con `502 Bad Gateway` al hacer pull de Docker Hub, **reintenta** o en el VPS: `docker pull chatwoot/chatwoot:v4.16.2` y vuelve a desplegar.

> `POSTGRES_HOST=postgres` y `REDIS_URL` ya van **fijados en `docker-compose.yaml`**. Si Rails muestra `pg_isready -h -p 5432`, era porque faltaban esas variables en el contenedor (Coolify no lee `.env` del repo como archivo montado).

### Primera migración (obligatoria una vez)

Tras el primer deploy exitoso de postgres/redis, ejecutar en el terminal de Coolify o SSH:

```bash
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
```

### Recursos recomendados

| Servicio | CPU | RAM |
| --- | --- | --- |
| `rails` | 1.0 | 1.5G |
| `sidekiq` | 0.5 | 512M |
| `postgres` | 0.5 | 1G |
| `redis` | 0.25 | 256M |

## Migrar configuración local → producción

Si ya configuraste Chatwoot en local (cuenta, inbox, agentes), migra la BD **`chatwoot_production`** y el volumen de adjuntos.

### 1. Exportar en tu PC (Windows)

```powershell
cd D:\Work\Proyectos\HuertoBio\tools\support-chatwoot
.\scripts\export-local.ps1
```

Genera en `backups/`:
- `chatwoot-YYYYMMDD-HHMMSS.sql` — dump PostgreSQL
- `storage_data-YYYYMMDD-HHMMSS.tar.gz` — avatares/adjuntos (opcional pero recomendado)

### 2. Subir al VPS (SCP desde PowerShell)

Windows incluye **OpenSSH** (`scp`). Sustituye `usuario`, `tu-vps` y la ruta remota:

```powershell
cd D:\Work\Proyectos\HuertoBio\tools\support-chatwoot\backups

# Copiar dump SQL + storage al VPS
scp chatwoot-*.sql storage_data-*.tar.gz usuario@tu-vps:/tmp/chatwoot-migrate/
```

Alternativa con **PuTTY**: `pscp.exe chatwoot-*.sql usuario@tu-vps:/tmp/chatwoot-migrate/`

En el VPS, mueve los archivos al directorio del stack si hace falta (p. ej. `/data/coolify/.../support-chatwoot/backups/`).

### 3. Importar en Coolify

En el terminal del recurso **support-chatwoot** (con variables de entorno ya configuradas):

```bash
chmod +x scripts/import-production.sh
./scripts/import-production.sh backups/chatwoot-YYYYMMDD-HHMMSS.sql backups/storage_data-YYYYMMDD-HHMMSS.tar.gz
```

> **No ejecutes** `db:chatwoot_prepare` en producción si importas el dump local: la BD ya viene con datos. **Sí debes** ejecutar `db:migrate` si la imagen de producción es más nueva que tu instalación local (ver [Migraciones tras importar dump](#4-migraciones-tras-importar-dump-local--imagen-prod)).

### 4. Migraciones tras importar dump (local ≠ imagen prod)

El dump local puede traer un esquema **anterior** al de la imagen desplegada en Coolify (`CHATWOOT_IMAGE_TAG`, p. ej. `v4.16.2`). Si no migras, Sidekiq fallará con errores como:

- `PG::UndefinedColumn: column email_templates.inbox_id does not exist`
- `StandardError: Channel email domain not present` (inbox Website sin canal email; ver [Emails](#emails-y-notificaciones))

**Obligatorio tras importar** (o tras subir `CHATWOOT_IMAGE_TAG`):

```bash
# Desde SSH en el VPS — sustituye nombres de contenedor (ver sección Operaciones)
docker exec -it <CONTENEDOR_RAILS> bundle exec rails db:migrate:status | tail -30
docker exec -it <CONTENEDOR_RAILS> bundle exec rails db:migrate
docker restart <CONTENEDOR_SIDEKIQ>
```

Verificar que la migración `AddInboxScopeToEmailTemplates` quedó en `up` y que existe `email_templates.inbox_id`:

```bash
docker exec -it <CONTENEDOR_POSTGRES> \
  psql -U postgres -d chatwoot_production -c "\d email_templates"
```

Debe aparecer la columna `inbox_id` y los índices `index_email_templates_on_inbox_*`.

> `scripts/import-production.sh` ejecuta `db:migrate` y reinicia Sidekiq automáticamente tras restaurar el dump.

### 5. Variables que deben coincidir

| Variable | Recomendación |
| --- | --- |
| `SECRET_KEY_BASE` | **Mismo valor que en local** (cookies/sesiones) |
| `FRONTEND_URL` | `https://chat.huerto.bio` (actualizar en Coolify; el dump trae config de localhost) |
| `POSTGRES_PASSWORD` / `REDIS_PASSWORD` | Las de producción (solo afectan conexión, no el contenido del dump) |

Tras importar, revisa en Chatwoot **Settings → Account → Allowed Domains**:

`huerto.bio`, `www.huerto.bio`, `beta.huerto.bio`, `staging.huerto.bio`, `localhost`

El **Website Token** será el mismo que tenías en local si migraste la BD completa.

## Operaciones en Coolify (VPS)

Coolify nombra los contenedores con un sufijo único. Desde SSH en el VPS (`root@srv-edge`), **`docker compose` desde `~` no funciona** (`no configuration file provided`). Usa el **terminal del recurso support-chatwoot** en Coolify (tiene el compose en contexto) **o** `docker exec` con el nombre exacto del contenedor.

### Identificar contenedores

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "rails|sidekiq|postgres|redis"
```

Ejemplo de salida:

```
rails-g14e4wip3560eolomx6i5t16-143936982889       Up (healthy)
sidekiq-g14e4wip3560eolomx6i5t16-143937047475     Up
postgres-g14e4wip3560eolomx6i5t16-143937102690    Up (healthy)
```

En los comandos siguientes sustituye `<CONTENEDOR_RAILS>`, `<CONTENEDOR_SIDEKIQ>` y `<CONTENEDOR_POSTGRES>` por esos nombres.

> **Postgres** vive en su propio contenedor. No ejecutes `psql` dentro del contenedor `rails` (fallará con `connection to server on socket ... failed`).

### Migraciones de base de datos

| Situación | Comando |
| --- | --- |
| Instalación **nueva** (BD vacía) | `docker compose run --rm rails bundle exec rails db:chatwoot_prepare` |
| **Importaste dump local** o subiste `CHATWOOT_IMAGE_TAG` | `docker exec -it <CONTENEDOR_RAILS> bundle exec rails db:migrate` |
| Comprobar pendientes | `docker exec -it <CONTENEDOR_RAILS> bundle exec rails db:migrate:status \| tail -30` |

Flujo recomendado tras cada actualización de imagen:

```bash
docker exec -it <CONTENEDOR_RAILS> bundle exec rails db:migrate
docker restart <CONTENEDOR_SIDEKIQ>
```

### Sidekiq y Redis

Comprobar conexión Redis desde Sidekiq:

```bash
docker exec -it <CONTENEDOR_SIDEKIQ> bundle exec rails runner "puts Sidekiq.redis { |r| r.ping }"
# Esperado: PONG
```

Estadísticas de colas:

```bash
docker exec -it <CONTENEDOR_SIDEKIQ> bundle exec rails runner "
  require 'sidekiq/api'
  puts 'Enqueued: ' + Sidekiq::Stats.new.enqueued.to_s
  puts 'Retries: ' + Sidekiq::RetrySet.new.size.to_s
  puts 'Dead:    ' + Sidekiq::DeadSet.new.size.to_s
"
```

Valores sanos tras migrar: `Enqueued: 0`, `Retries: 0`. Jobs en `Dead` son fallos **históricos** (p. ej. emails antes de migrar); **reiniciar Sidekiq no los borra**.

Limpiar dead jobs obsoletos (solo tras corregir la causa — migraciones, SMTP, etc.):

```bash
docker exec -it <CONTENEDOR_SIDEKIQ> bundle exec rails runner "
  require 'sidekiq/api'
  Sidekiq::DeadSet.new.clear
  puts 'Dead jobs cleared'
"
```

### Emails y notificaciones

| Error en Sidekiq | Causa | Acción |
| --- | --- | --- |
| `Channel email domain not present` | Inbox **Website** sin canal email; Chatwoot intenta enviar resumen por correo | Desactivar emails de agente en **Settings → Notifications**, o configurar SMTP + inbox Email |
| `email_templates.inbox_id does not exist` | BD desactualizada respecto a la imagen | Ejecutar `db:migrate` (sección anterior) |

Variables SMTP en Coolify (ejemplo Resend): ver `.env.example` (`SMTP_ADDRESS`, `SMTP_PASSWORD`, etc.).

### Inbox web (widget Huerto.Bio)

Tras migrar, revisa en el panel:

1. **Settings → Inboxes → Huerto.Bio Soporte → Collaborators** — agentes humanos asignados al inbox
2. **Auto assignment** activo en la configuración del inbox
3. **Sin Agent Bot** conectado si no tienes webhook configurado (un bot sin URL deja el widget “pensando”)
4. Conversaciones reabiertas tras CSAT reutilizan el mismo hilo (no crean conversación nueva)

## Seguridad

- **No commitear `.env`**. Usar `.env.example` como plantilla.
- Si `.env` llegó al remoto, eliminarlo del historial y rotar secretos:

  ```powershell
  git rm --cached .env
  git commit -m "chore: stop tracking .env"
  git push
  ```

## Actualización de imagen

En el terminal del recurso Coolify (o con `docker exec`):

```bash
# 1. Pull de la nueva imagen (Coolify redeploy, o manualmente)
docker compose pull   # solo si estás en el directorio del compose
docker compose up -d

# 2. Migraciones obligatorias si la etiqueta sube de versión
docker exec -it <CONTENEDOR_RAILS> bundle exec rails db:migrate

# 3. Reiniciar Sidekiq para procesar colas limpias
docker restart <CONTENEDOR_SIDEKIQ>

# 4. Verificar Sidekiq (opcional)
docker exec -it <CONTENEDOR_SIDEKIQ> bundle exec rails runner "
  require 'sidekiq/api'
  puts 'Enqueued: ' + Sidekiq::Stats.new.enqueued.to_s
  puts 'Dead:    ' + Sidekiq::DeadSet.new.size.to_s
"
```

Si cambias `CHATWOOT_IMAGE_TAG` en Coolify → **Environment Variables**, redeploy y repite los pasos 2–4.
