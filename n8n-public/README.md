# n8n Setup

## Struktur
```
n8n-public/
├── docker-compose.yml           # n8n-Basis-Service + Traefik-Labels
├── docker-compose.override.yml  # n8n Assistant Sandbox-Stack (sandbox-certs/-api/-runner)
├── .env                         # Sandbox-Secrets (chmod 600, NICHT einchecken)
├── n8n-data/                    # n8n SQLite-DB, Encryption Key (Bind-Mount, uid/gid 1000)
└── README.md
```

## Traefik-Anbindung

n8n hängt am externen Netzwerk `traefik_web` (bereitgestellt vom `traefik-revproxy`-Stack)
und ist erreichbar unter **https://n8n.wiche.eu**. TLS läuft über das bestehende
Wildcard-Zertifikat für `*.wiche.eu` (siehe `traefik-revproxy/dynamic/tls.yml`) —
keine zusätzliche Zertifikatskonfiguration nötig.

Relevante Labels in `docker-compose.yml`:
```yaml
labels:
  - traefik.enable=true
  - traefik.docker.network=traefik_web
  - traefik.http.routers.n8n.entrypoints=https
  - traefik.http.routers.n8n.rule=Host(`n8n.wiche.eu`)
  - traefik.http.routers.n8n.tls=true
  - traefik.http.services.n8n.loadbalancer.server.port=5678
```

## Deployment

```bash
cd /home/julian/docker-stacks-home/n8n-public
docker compose up -d
```

`docker-compose.yml` und `docker-compose.override.yml` werden von Compose automatisch
zusammengeführt (kein `-f`-Flag nötig) — ein `docker compose up -d` startet/aktualisiert
beides in einem Schritt.

**Erstinstallation / neuer Host:** Bind-Mount `./n8n-data` wird beim ersten Start von
Docker als `root:root` angelegt, n8n läuft im Container aber als `uid 1000`. Falls n8n
mit `EACCES: permission denied` crasht:
```bash
docker run --rm -v "$(pwd)/n8n-data:/data" alpine chown -R 1000:1000 /data
docker compose up -d
```

## n8n Assistant: Sandbox-Stack (self-hosted "n8n Sandbox")

Der AI Assistant/Agents-Feature von n8n braucht eine Sandbox, um Code auszuführen.
Wir nutzen n8ns eigenen self-hosted Sandbox-Service (nicht Daytona) — läuft komplett
lokal, nichts verlässt die Infrastruktur.

**Quelle der Wahrheit** (verifiziert, keine Vermutung): der offizielle
[`get-n8n-compose.yml`](https://github.com/n8n-io/n8n/blob/master/docker/get-n8n-compose.yml)
aus dem n8n-Repo, plus [Set up n8n Assistant](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant/).

### Komponenten (in `docker-compose.override.yml`)

| Service | Zweck |
|---|---|
| `sandbox-certs` | Läuft einmalig beim Start, erzeugt mTLS-Zertifikate für die anderen zwei, exitet danach |
| `sandbox-api` | Control-Plane, mit der n8n spricht (`http://sandbox-api:8080`) |
| `sandbox-runner-1` | **`privileged: true`** Docker-in-Docker-Container, führt den eigentlichen Code aus |

Alle drei hängen **nur** am privaten `default`-Netz (`n8n-public_default`) —
**nicht** an `traefik_web`. Sie dürfen nie öffentlich erreichbar sein
(`sandbox-runner-1` ist root-äquivalent auf dem Host).

### n8n-Konfiguration (in `docker-compose.override.yml`, Service `n8n`)

```yaml
environment:
  - N8N_INSTANCE_AI_SANDBOX_ENABLED=true
  - N8N_INSTANCE_AI_SANDBOX_PROVIDER=n8n-sandbox
  - N8N_INSTANCE_AI_SANDBOX_IMAGE=ghcr.io/n8n-io/n8n-sandbox-service-sandbox:latest
  - N8N_SANDBOX_SERVICE_URL=http://sandbox-api:8080
  - N8N_SANDBOX_SERVICE_API_KEY=${N8N_SANDBOX_SERVICE_API_KEY}
```

### Werte für den "Add a code sandbox"-Dialog im n8n-UI

- **Service URL:** `http://sandbox-api:8080`
- **API key:** Wert von `N8N_SANDBOX_SERVICE_API_KEY` in `.env`

### Secrets (`.env`)

Drei generierte Secrets (`openssl rand -hex 24`), jeweils zweimal unter unterschiedlichem
Namen (API-Seite / Runner-Seite):

| Secret | API-Seite | Runner-Seite |
|---|---|---|
| Sandbox-API-Key | `SANDBOX_API_KEYS` | `N8N_SANDBOX_SERVICE_API_KEY` (n8n) |
| Registrierungs-Token | `SANDBOX_API_RUNNER_REGISTRATION_TOKEN` | `SANDBOX_RUNNER_REGISTRATION_TOKEN` |
| Runner-API-Key | `SANDBOX_API_RUNNER_API_KEY` | `SANDBOX_RUNNER_API_KEYS` |

`sandbox-api` und `sandbox-runner-1` nutzen **kein** `env_file: .env`, sondern bekommen
im Override explizit nur ihre eigenen Variablen — n8ns eigene Secrets (Host-Config,
künftiger Model-API-Key) erreichen die Sandbox-Container dadurch nie (Empfehlung aus
n8ns eigenem Security-Checklist).

### Verifikation

```bash
# sandbox-api von n8n aus erreichbar?
docker exec n8n wget -qO- http://sandbox-api:8080/healthz
# → {"status":"ok"}

# Runner registriert?
docker logs n8n-public-sandbox-api-1 | grep -i runner

# öffentliche Erreichbarkeit unverändert?
curl -sk -o /dev/null -w "%{http_code}\n" https://n8n.wiche.eu/
```

### Troubleshooting

| Symptom | Ursache |
|---|---|
| `sandbox-api`/`sandbox-runner-1` starten nicht, Zertifikatsfehler | `sandbox-certs` nicht sauber durchgelaufen → `docker compose logs sandbox-certs` |
| `sandbox-api` wird nicht `healthy` | `docker compose logs sandbox-api` prüfen |
| `sandbox-runner-1` crash-loopt mit `... must be set` | Env-Var fehlt, meist Registrierungs-Token/API-Key aus `.env` |
| Runner registriert sich nicht | `SANDBOX_RUNNER_REGISTRATION_TOKEN`-Mismatch zwischen API und Runner |
| n8n-Sandbox-Aufrufe schlagen fehl | `N8N_SANDBOX_SERVICE_URL`/`N8N_SANDBOX_SERVICE_API_KEY` stimmen nicht mit `sandbox-api` überein |

### Einstufung laut n8n

Dieser self-hosted Sandbox-Typ (`n8n-sandbox`) ist offiziell für **lokale Entwicklung/Tests**
gedacht. Für Produktivbetrieb empfiehlt n8n den verwalteten **Daytona**-Sandbox-Provider
stattdessen (kostenpflichtig, Konfiguration über `N8N_INSTANCE_AI_SANDBOX_PROVIDER=daytona`
+ `DAYTONA_API_URL`/`DAYTONA_API_KEY`). Da `n8n.wiche.eu` öffentlich erreichbar ist, im
Hinterkopf behalten, falls der Assistant produktiv/vielgenutzt wird.

### Ressourcenbedarf

`sandbox-runner-1` (Docker-in-Docker) braucht laut n8n mind. 4 GB RAM / 2 vCPU zusätzlicher
Headroom. Host hatte beim Setup 15 GB RAM (8,6 GB frei), 6 vCPUs, 13 GB freien Diskplatz —
ausreichend, aber im Auge behalten bei weiterem Wachstum (Immich/Nextcloud laufen auf
derselben Maschine).
