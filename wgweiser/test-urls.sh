#!/usr/bin/env bash
# test-urls.sh — Testet alle URLs aus assets/config.yml

CONFIG="${1:-assets/config.yml}"
TIMEOUT=5

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [[ ! -f "$CONFIG" ]]; then
  echo "Datei nicht gefunden: $CONFIG"
  exit 1
fi

# URLs aus config.yml extrahieren (nur url: Zeilen, keine javascript:/ftp:/#-only)
mapfile -t URLS < <(
  grep -E '^\s+url:' "$CONFIG" \
    | sed 's/.*url:\s*["'"'"']\?\(.*\)["'"'"']\?\s*$/\1/' \
    | sed 's/["'"'"']//g' \
    | grep -v '^javascript:' \
    | grep -v '^ftp:' \
    | grep -v '^#' \
    | grep -v '^\.' \
    | sort -u
)

# Namen für jede URL ermitteln (zum Anzeigen)
declare -A URL_NAMES
while IFS= read -r line; do
  name=$(echo "$line" | grep -oP "(?<=name: \").*(?=\")" | head -1)
  url=$(echo "$line"  | grep -oP "(?<=url: ).*" | tr -d '"'"'" | head -1)
  if [[ -n "$url" && -n "$name" ]]; then
    URL_NAMES["$url"]="$name"
  fi
done < <(grep -E '(name:|url:)' "$CONFIG")

ok=0
fail=0
skip=0

echo ""
echo "Teste ${#URLS[@]} URLs aus $CONFIG (Timeout: ${TIMEOUT}s)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for url in "${URLS[@]}"; do
  # Status per curl ermitteln, SSL-Fehler ignorieren (-k), folge Redirects (-L)
  http_code=$(curl -o /dev/null -s -k -L \
    --max-time "$TIMEOUT" \
    --connect-timeout "$TIMEOUT" \
    -w "%{http_code}" \
    "$url" 2>/dev/null)

  exit_code=$?
  name="${URL_NAMES[$url]:-}"
  label="${name:+$name — }$url"

  if [[ $exit_code -ne 0 ]]; then
    printf "${RED}✗ FEHLER${NC}  (curl exit %s) %s\n" "$exit_code" "$label"
    ((fail++))
  elif [[ "$http_code" =~ ^[23] ]]; then
    printf "${GREEN}✓ OK${NC}      (HTTP %s) %s\n" "$http_code" "$label"
    ((ok++))
  elif [[ "$http_code" == "000" ]]; then
    printf "${RED}✗ TIMEOUT${NC} (keine Antwort) %s\n" "$label"
    ((fail++))
  else
    printf "${YELLOW}~ WARN${NC}     (HTTP %s) %s\n" "$http_code" "$label"
    ((skip++))
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "${GREEN}✓ OK: %d${NC}   ${YELLOW}~ WARN: %d${NC}   ${RED}✗ FEHLER/TIMEOUT: %d${NC}\n" \
  "$ok" "$skip" "$fail"
echo ""
