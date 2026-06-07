# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Stack

Authentik identity provider running via Docker Compose. Three services:
- `postgresql` — Postgres 16 backend, internal only
- `server` — Authentik HTTP server on port 9000, exposed via Traefik at `https://auth.wiche.eu`
- `worker` — background task processor, runs as root (needs Docker socket)

Active compose file: **`compose.yml`** (ignore `docher-compose.yml`, `docker-compose-old.xaml`, `compose.bak.1` — legacy).

## Common Commands

```bash
# Start / restart stack
docker compose up -d

# Stop stack
docker compose down

# View logs
docker compose logs -f server
docker compose logs -f worker

# Upgrade version — edit AUTHENTIK_TAG in compose.yml, then:
docker compose pull && docker compose up -d
```

## Networking

- Traefik reverse proxy lives at `../traefik-revproxy/` and manages the `traefik_web` external Docker network.
- Only the `server` service joins `traefik_web`; worker and postgresql are internal.
- TLS cert for `auth.wiche.eu` is issued automatically by Traefik's Let's Encrypt resolver (`le`).

## Key Files

| Path | Purpose |
|------|---------|
| `compose.yml` | Active stack definition |
| `.env` | Secrets: `PG_PASS`, `AUTHENTIK_SECRET_KEY`, SMTP credentials |
| `./data/` | Authentik runtime data (bind-mounted into server + worker) |
| `./certs/` | Certificates accessible by the worker |
| `./custom-templates/` | Override Authentik HTML templates |

## Environment Variables

All secrets live in `.env`. Required vars: `PG_PASS`, `AUTHENTIK_SECRET_KEY`. Optional overrides: `PG_DB`, `PG_USER`, `AUTHENTIK_IMAGE`, `AUTHENTIK_TAG`, `COMPOSE_PORT_HTTP`, `COMPOSE_PORT_HTTPS` (port vars unused now that Traefik handles ingress).
