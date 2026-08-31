#!/bin/bash
# autopull.sh — keeps Homer config up to date from git
# Usage: run once, or set up as cron / systemd timer
#
# Cron example (every 5 min):
#   */5 * * * * /opt/homer/autopull.sh >> /var/log/homer-autopull.log 2>&1
#
# Systemd timer: see autopull.service / autopull.timer below

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$REPO_DIR" || exit 1

git pull --ff-only origin main && echo "[$(date '+%F %T')] pulled ok" || echo "[$(date '+%F %T')] pull failed / already up to date"
