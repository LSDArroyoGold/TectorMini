#!/bin/bash
#
# sincronizar_detecciones.sh - agregado el 18/9/2026. Cola de reintento para
# las detecciones: TectorNET-Pi sube cada archivo una sola vez y, si falla
# (sin red, servidor caido), no reintenta. Como "rclone copy" solo transfiere
# lo que falta en destino, alcanza con volver a copiar cada 10 minutos lo de
# los ultimos 7 dias; lo ya subido se saltea sin costo. Corre por cron.
# Destino = SYNC_REMOTE:SYNC_PATH/Detecciones (config/config_general.txt).

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
export RCLONE_CONFIG="$USER_HOME/.config/rclone/rclone.conf"
export HOME="$USER_HOME"

CONFIG_GENERAL="$BASE_PATH/config/config_general.txt"
SYNC_PATH=$(awk -F'=' '/^SYNC_PATH=/{print $2}' "$CONFIG_GENERAL" | tr -d '\r')
SYNC_REMOTE=$(awk -F'=' '/^SYNC_REMOTE=/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')
SYNC_REMOTE="${SYNC_REMOTE:-servidor}"

[ -n "$SYNC_PATH" ] || exit 0

flock -n /tmp/sincronizar_detecciones.lock \
	timeout 600 rclone copy "$USER_HOME/BirdSongs/Extracted/By_Date/" "$SYNC_REMOTE:$SYNC_PATH/Detecciones/" \
	--max-age 7d --min-age 1m --transfers 2 --contimeout 20s --timeout 60s --retries 2 2>/dev/null
