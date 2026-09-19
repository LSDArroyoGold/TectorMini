#!/bin/bash
#
# limpiar_retencion.sh - acota el almacenamiento LOCAL por tamaño, borrando
# carpetas de fecha ENTERAS (By_Date/<fecha>/, con todas las especies de ese
# dia adentro) empezando por la mas vieja -- nunca archivos sueltos de un
# dia a medias, para que sea predecible ("o esta el dia completo, o no
# esta"). En Tector Mini (sin ventanas amanecer/atardecer) corre por cron
# una vez al dia (ver install.sh).
#
# RETENCION_AUDIO_LOCAL_MB en config/config_general.txt. Del servidor NO se
# borra nada desde aca: el tope de cada dispositivo en el servidor lo maneja
# el propio servidor (tector-retencion.timer).

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
export RCLONE_CONFIG="$USER_HOME/.config/rclone/rclone.conf"

CONFIG_GENERAL="$BASE_PATH/config/config_general.txt"
RETENCION_LOCAL_MB=$(awk -F'=' '/^RETENCION_AUDIO_LOCAL_MB=/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')

# du por carpeta de fecha (mas nueva primero), acumular tamaño, borrar
# carpetas enteras una vez superado el limite.
if [ -n "$RETENCION_LOCAL_MB" ]; then
	CAP_BYTES=$((RETENCION_LOCAL_MB * 1024 * 1024))
	find "$USER_HOME/BirdSongs/Extracted/By_Date" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
		| sort -r \
		| while IFS= read -r FECHA; do
			echo "$(du -sb "$USER_HOME/BirdSongs/Extracted/By_Date/$FECHA" 2>/dev/null | cut -f1) $FECHA"
		done \
		| awk -v cap="$CAP_BYTES" '{ acumulado += $1; if (acumulado > cap) print $2 }' \
		| while IFS= read -r FECHA; do
			rm -rf "$USER_HOME/BirdSongs/Extracted/By_Date/$FECHA"
		done
fi
