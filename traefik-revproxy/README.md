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

## Offene Punkte, die du noch prüfen solltest

- DNS-Eintrag für `traefik.wiche.eu` muss auf deinen Server zeigen
- Basic-Auth hat kein Rate-Limiting/2FA — für ein rein internes Netz ok,
  bei öffentlicher Erreichbarkeit würde ich zusätzlich absichern
