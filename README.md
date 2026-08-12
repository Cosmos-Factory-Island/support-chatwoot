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

> **No ejecutes** `db:chatwoot_prepare` en producción si importas el dump local: la BD ya viene migrada y con datos.

### 4. Variables que deben coincidir

| Variable | Recomendación |
| --- | --- |
| `SECRET_KEY_BASE` | **Mismo valor que en local** (cookies/sesiones) |
| `FRONTEND_URL` | `https://chat.huerto.bio` (actualizar en Coolify; el dump trae config de localhost) |
| `POSTGRES_PASSWORD` / `REDIS_PASSWORD` | Las de producción (solo afectan conexión, no el contenido del dump) |

Tras importar, revisa en Chatwoot **Settings → Account → Allowed Domains**:

`huerto.bio`, `www.huerto.bio`, `beta.huerto.bio`, `staging.huerto.bio`, `localhost`

El **Website Token** será el mismo que tenías en local si migraste la BD completa.

## Seguridad

- **No commitear `.env`**. Usar `.env.example` como plantilla.
- Si `.env` llegó al remoto, eliminarlo del historial y rotar secretos:

  ```powershell
  git rm --cached .env
  git commit -m "chore: stop tracking .env"
  git push
  ```

## Actualización de imagen

```bash
docker compose pull
docker compose up -d
```
