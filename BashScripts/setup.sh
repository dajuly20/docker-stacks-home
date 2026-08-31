#!/usr/bin/env bash
#
# setup.sh - Interaktives Setup-Menü fuer diesen Host.
set -uo pipefail

# --------------------------------------------------------------------------
# Hilfsfunktionen
# --------------------------------------------------------------------------

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Fehler: '$1' ist nicht installiert."
    return 1
  }
}

pause() {
  read -rp "Weiter mit [Enter]..." _
}

# --------------------------------------------------------------------------
# USB over IP (usbip)
# --------------------------------------------------------------------------

usbip_install_pkg() {
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    if ! sudo apt-get install -y usbip; then
      sudo apt-get install -y linux-tools-generic "linux-tools-$(uname -r)" || true
    fi
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y usbip
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y usbip
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm usbip
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y usbip
  else
    echo "Kein unterstuetzter Paketmanager gefunden. Bitte 'usbip' manuell installieren."
    return 1
  fi
}

usbip_persist_module() {
  local mod="$1"
  local file="/etc/modules-load.d/usbip.conf"
  sudo touch "$file"
  if ! grep -qxF "$mod" "$file" 2>/dev/null; then
    echo "$mod" | sudo tee -a "$file" >/dev/null
  fi
}

usbip_install_server() {
  echo "==> Installiere USB/IP Server-Komponenten ..."
  usbip_install_pkg || return 1

  sudo modprobe usbip-host || { echo "Fehler: Kernelmodul usbip-host konnte nicht geladen werden."; return 1; }
  usbip_persist_module "usbip-host"

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files | grep -q '^usbipd\.service'; then
      sudo systemctl enable --now usbipd.service
    else
      local usbipd_bin
      usbipd_bin="$(command -v usbipd || echo /usr/sbin/usbipd)"
      sudo tee /etc/systemd/system/usbipd.service >/dev/null <<EOF
[Unit]
Description=USB/IP Server Daemon
After=network.target

[Service]
Type=forking
ExecStart=$usbipd_bin -D
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
      sudo systemctl daemon-reload
      sudo systemctl enable --now usbipd.service
    fi
  else
    echo "Kein systemd gefunden, starte usbipd manuell:"
    sudo usbipd -D
  fi

  echo "Server bereit. usbipd laeuft auf Port 3240."
  echo "Hinweis: Port 3240/tcp muss in der Firewall fuer den Client freigegeben sein."
}

usbip_install_client() {
  echo "==> Installiere USB/IP Client-Komponenten ..."
  usbip_install_pkg || return 1

  sudo modprobe vhci-hcd || { echo "Fehler: Kernelmodul vhci-hcd konnte nicht geladen werden."; return 1; }
  usbip_persist_module "vhci-hcd"

  echo "Client bereit. Nutze 'Client: Geraet erkennen & verbinden', um ein USB-Geraet vom Server zu attachen."
}

usbip_server_select_device() {
  require_cmd usbip || return 1

  echo "==> Lokale USB-Geraete:"
  sudo usbip list -l
  echo

  read -rp "Bus-ID des freizugebenden Geraets (z.B. 1-2), leer = Abbruch: " busid
  if [[ -z "$busid" ]]; then
    echo "Abgebrochen."
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^usbipd\.service'; then
    systemctl is-active --quiet usbipd || sudo systemctl start usbipd
  fi

  if sudo usbip bind -b "$busid"; then
    echo "Geraet $busid freigegeben (bind)."
  else
    echo "Fehler beim Freigeben von $busid. Ist das Geraet bereits gebunden oder die Bus-ID falsch?"
  fi
}

usbip_client_select_device() {
  require_cmd usbip || return 1

  read -rp "IP-Adresse / Hostname des USB/IP-Servers: " server_ip
  if [[ -z "$server_ip" ]]; then
    echo "Abgebrochen."
    return 0
  fi

  echo "==> Verfuegbare Geraete auf $server_ip:"
  if ! sudo usbip list -r "$server_ip"; then
    echo "Konnte Geraete nicht abrufen. Laeuft usbipd auf dem Server und ist Port 3240 erreichbar?"
    return 1
  fi
  echo

  read -rp "Bus-ID des zu verbindenden Geraets (z.B. 1-2), leer = Abbruch: " busid
  if [[ -z "$busid" ]]; then
    echo "Abgebrochen."
    return 0
  fi

  sudo modprobe vhci-hcd

  if sudo usbip attach -r "$server_ip" -b "$busid"; then
    echo "Geraet verbunden. Pruefe mit 'usbip port' oder 'lsusb'."
  else
    echo "Fehler beim Verbinden von $busid auf $server_ip."
  fi
}

usbip_menu() {
  while true; do
    echo
    echo "==================== USB over IP ===================="
    echo "1) Server installieren (usbip-host)"
    echo "2) Client installieren (vhci-hcd)"
    echo "3) Server: Geraet erkennen & freigeben"
    echo "4) Client: Geraet erkennen & verbinden"
    echo "0) Zurueck zum Hauptmenue"
    echo "======================================================="
    read -rp "Auswahl: " choice
    case "$choice" in
      1) usbip_install_server; pause ;;
      2) usbip_install_client; pause ;;
      3) usbip_server_select_device; pause ;;
      4) usbip_client_select_device; pause ;;
      0) break ;;
      *) echo "Ungueltige Auswahl." ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Hauptmenue
# --------------------------------------------------------------------------

main_menu() {
  while true; do
    echo
    echo "======================= Setup ========================"
    echo "1) USB over IP"
    echo "0) Beenden"
    echo "======================================================="
    read -rp "Auswahl: " choice
    case "$choice" in
      1) usbip_menu ;;
      0) echo "Bye."; exit 0 ;;
      *) echo "Ungueltige Auswahl." ;;
    esac
  done
}

main_menu
