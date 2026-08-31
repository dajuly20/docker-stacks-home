# Traefik Reverse Proxy Setup

## Struktur
```
traefik-revproxy/
├── docker-compose.yml          # Container-Definition
├── dynamic/
│   ├── dashboard.yml            # Dashboard-Router (HTTPS) + Basic-Auth
│   └── tls.yml                  # TLS-Zertifikate für wiche.eu
└── README.md
```

## Vor dem Start: Passwort-Hash erzeugen

```bash
sudo apt install apache2-utils   # falls htpasswd fehlt
htpasswd -nBC 12 julian
```

Ausgabe (z.B. `julian:$2y$12$abc...`) in `dynamic/dashboard.yml`
bei `users:` einsetzen — den Platzhalter `CHANGE_ME_REPLACE_WITH_YOUR_HTPASSWD_HASH`
ersetzen. In dieser Datei (kein docker-compose.yml) brauchst du
KEIN doppeltes `$$` — normales `$` reicht.

## Deployment

```bash
mkdir -p /home/julian/docker-stacks-home/traefik-revproxy/dynamic
# Dateien an den Zielort kopieren
cd /home/julian/docker-stacks-home/traefik-revproxy
docker compose up -d
```

## Änderungen an der dynamic-Config

Dank `providers.file.watch=true` liest Traefik `dynamic/dashboard.yml`
automatisch neu ein, sobald du sie speicherst — kein Container-Neustart nötig.

## Dashboard-Zugriff

Das Dashboard läuft nicht mehr über einen eigenen `:8080`-Port auf der
internen IP, sondern über den normalen HTTPS-Entrypoint (443), genau wie
alle anderen Services. Erreichbar unter `https://traefik.wiche.eu`,
abgesichert mit Basic-Auth (`dashboard-auth`-Middleware). HTTP-Anfragen auf
Port 80 werden automatisch auf HTTPS umgeleitet. Ein separater Port muss
dafür nicht mehr freigegeben werden.

## Neue Services über Traefik anbinden

Jeder neue Container, der über `https://<name>.wiche.eu` erreichbar sein
soll, braucht in seiner eigenen `docker-compose.yml` drei Dinge:

1. **Netzwerk** — muss im selben Docker-Netzwerk hängen wie Traefik
   (`traefik_web`, extern definiert)
2. **Labels** — Router-Regel, Entrypoint, TLS, Ziel-Port
3. **`traefik.enable=true`** — Pflicht, weil `exposedByDefault=false`
   gesetzt ist. Ohne dieses Label sieht Traefik den Container gar nicht.

### Minimalbeispiel

```yaml
services:
  myapp:
    image: myapp:latest
    restart: unless-stopped
    networks:
      - web
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.wiche.eu`)"
      - "traefik.http.routers.myapp.entrypoints=https"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"

networks:
  web:
    name: traefik_web
    external: true
```

**Hinweise zu den Labels:**

| Label | Bedeutung |
|---|---|
| `traefik.enable=true` | Container wird von Traefik überhaupt beachtet |
| `routers.myapp.rule` | `myapp` ist frei wählbar, muss nur pro Router eindeutig sein — sollte aber nicht zwingend dem Containernamen entsprechen |
| `routers.myapp.entrypoints=https` | Service läuft über Port 443 (`http`→`https`-Redirect passiert automatisch, siehe `docker-compose.yml` der Traefik-Instanz) |
| `routers.myapp.tls=true` | nutzt den Default-Zertifikatsspeicher aus `dynamic/tls.yml` |
| `services.myapp.loadbalancer.server.port` | **interner** Container-Port, auf dem die App lauscht — kein `ports:`-Mapping nötig, Traefik erreicht den Container direkt über `traefik_web` |

Da das Zertifikat ein Wildcard für `*.wiche.eu` ist, funktioniert jeder
neue Subdomain-Name sofort ohne zusätzliche Zertifikatskonfiguration.

### Optional: zusätzlich intern über `*.htz.ip` erreichbar

Analog zum Dashboard (`dynamic/dashboard.yml`) lässt sich ein zweiter
Hostname per `||` ergänzen — dafür muss der Name in eurer internen
DNS/Router-Konfiguration auf die Server-IP zeigen:

```yaml
- "traefik.http.routers.myapp.rule=Host(`myapp.wiche.eu`) || Host(`myapp.htz.ip`)"
```

### Optional: Basic-Auth wiederverwenden

Die vorhandene `dashboard-auth`-Middleware aus `dynamic/dashboard.yml`
kann auch für andere Services genutzt werden:

```yaml
- "traefik.http.routers.myapp.middlewares=dashboard-auth@file"
```

(`@file` ist nötig, weil die Middleware im File-Provider definiert ist,
der neue Service selbst aber über den Docker-Provider läuft.)

## Offene Punkte, die du noch prüfen solltest

- DNS-Eintrag für `traefik.wiche.eu` muss auf deinen Server zeigen
- Basic-Auth hat kein Rate-Limiting/2FA — für ein rein internes Netz ok,
  bei öffentlicher Erreichbarkeit würde ich zusätzlich absichern
