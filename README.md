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
5. **Dominio del servicio `rails`**: `https://chat.huerto.bio:3000`
   - En Coolify **no hay un campo aparte de puerto**. El `:3000` va en la URL del dominio.
   - Ese puerto es el **interno del contenedor**; Traefik/Coolify sirve la web en HTTPS (443) hacia fuera.
   - Deja vacíos los dominios de `sidekiq` y cualquier otro servicio interno.
6. Variables de entorno (desde `.env.example`, valores de producción)
   - `FRONTEND_URL=https://chat.huerto.bio` (sin `:3000`)
7. Deploy → migración (una vez):

   ```bash
   docker compose run --rm rails bundle exec rails db:chatwoot_prepare
   ```

8. Crear super-admin → **Settings → Inboxes → Website** → copiar **Website Token**
9. **Allowed Domains**: `huerto.bio`, `www.huerto.bio`, `staging.huerto.bio`, `localhost`
10. Configurar en `edge-huertobio`:
    - `PUBLIC_CHATWOOT_BASE_URL=https://chat.huerto.bio`
    - `PUBLIC_CHATWOOT_WEBSITE_TOKEN=<token>`

### Variables críticas (producción)

| Variable | Valor |
| --- | --- |
| `FRONTEND_URL` | `https://chat.huerto.bio` |
| `SECRET_KEY_BASE` | `openssl rand -hex 64` |
| `POSTGRES_PASSWORD` | contraseña fuerte |
| `REDIS_PASSWORD` | contraseña fuerte |
| `REDIS_URL` | `redis://:<password>@redis:6379` |
| `ENABLE_ACCOUNT_SIGNUP` | `false` |

### Recursos recomendados

| Servicio | CPU | RAM |
| --- | --- | --- |
| `rails` | 1.0 | 1.5G |
| `sidekiq` | 0.5 | 512M |
| `postgres` | 0.5 | 1G |
| `redis` | 0.25 | 256M |

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
