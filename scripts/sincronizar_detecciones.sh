#!/bin/bash
#
# sincronizar_detecciones.sh - agregado el 18/9/2026. Cola de reintento para
# las detecciones: TectorNET-Pi sube cada archivo una sola vez y, si falla
# (sin red, servidor caido), no reintenta. Como "rclone copy" solo transfiere
# lo que falta en destino, alcanza con volver a copiar cada 10 minutos lo de
# los ultimos 7 dias; lo ya subido se saltea sin costo. Corre por cron.
# Destino = SYNC_REMOTE:SYNC_PATH/Detecciones (config/config_general.txt).
#
# Tambien publica estado.json (mismo cron): Tector Mini no tiene ventanas,
# asi que su unico estado es "en_linea" y la prueba de que sigue vivo es que
# 'generado' se renueva. Si el Hub ve ese sello viejo, lo muestra sin conexion.

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

# --- estado.json (formato de la 2.1, recortado: sin ventanas ni bateria: la app muestra la fila Bateria si existe la clave) ---
HOY=$(date +%Y-%m-%d)
DETECCIONES_HOY=$(find "$USER_HOME/BirdSongs/Extracted/By_Date/$HOY" -name '*.mp3' ! -name '*-nbw.mp3' 2>/dev/null | wc -l)
TEMP=$(LC_ALL=C awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
THROTTLED=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
VERSION=$(cut -c1-7 "$BASE_PATH/.ultima_actualizacion" 2>/dev/null)
ESTADO_TMP=$(mktemp)
printf '{"version_formato":1,"serie":"0003","generado":"%s","estado":"en_linea","detecciones_hoy":%s,"temp_cpu_c":%s,"throttled":"%s","version_software":"%s","carpeta":"%s"}\n' \
	"$(date +%Y-%m-%dT%H:%M:%S)" "$DETECCIONES_HOY" "${TEMP:-null}" "${THROTTLED:-0x0}" "$VERSION" "$SYNC_PATH" > "$ESTADO_TMP"
timeout 60 rclone copyto "$ESTADO_TMP" "$SYNC_REMOTE:$SYNC_PATH/estado.json" --contimeout 20s --timeout 30s 2>/dev/null
rm -f "$ESTADO_TMP"

# --- log_salud.txt: historial de salud del equipo (mismo formato que Tector 2).
# temp, throttled (los bits 16-19 son latches desde el arranque), load, MHz
# reales del CPU, uptime en segundos (si baja entre dos filas hubo un
# reinicio), % de disco en / y RAM disponible en MB.
# Columnas fijas: si alguna vez cambian, apartar a mano el log viejo (un
# encabezado que no coincide con las filas fue el bug de log_bateria.txt).
LOG_SALUD="$BASE_PATH/log_salud.txt"
ENCABEZADO="timestamp,temp_cpu_c,throttled,load_avg_1min,cpu_mhz,uptime_s,disco_pct,ram_disp_mb"
# -s y no -e: logrotate (copytruncate) deja el archivo existiendo pero vacio.
[ -s "$LOG_SALUD" ] || echo "$ENCABEZADO" > "$LOG_SALUD"
MHZ=$(timeout 5 vcgencmd measure_clock arm 2>/dev/null | awk -F= '{printf "%d", $2/1000000}')
UPTIME=$(cut -d. -f1 /proc/uptime)
DISCO=$(df --output=pcent / | tail -n1 | tr -dc '0-9')
RAM=$(awk '/^MemAvailable:/{printf "%d", $2/1024}' /proc/meminfo)
echo "$(date '+%Y-%m-%d %H:%M:%S'),$TEMP,$THROTTLED,$(cut -d' ' -f1 /proc/loadavg),$MHZ,$UPTIME,$DISCO,$RAM" >> "$LOG_SALUD"
timeout 60 rclone copyto "$LOG_SALUD" "$SYNC_REMOTE:$SYNC_PATH/log_salud.txt" --contimeout 20s --timeout 30s 2>/dev/null

flock -n /tmp/sincronizar_detecciones.lock \
	timeout 600 rclone copy "$USER_HOME/BirdSongs/Extracted/By_Date/" "$SYNC_REMOTE:$SYNC_PATH/Detecciones/" \
	--max-age 7d --min-age 1m --transfers 2 --contimeout 20s --timeout 60s --retries 2 2>/dev/null
