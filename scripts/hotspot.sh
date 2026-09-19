#!/bin/bash
#
# hotspot.sh - Levanta el hotspot de configuracion WiFi (Tector Mini)
#
# Dos formas de disparo:
#   - Al arrancar (hotspot.service, sin argumentos): solo corre si
#     FIRST_START=TRUE en config_general.txt (primer arranque, o
#     reconfiguracion pendiente).
#   - A demanda por el boton fisico (python/check_button.py, con --force):
#     corre siempre, sin mirar FIRST_START. No hay latch de energia ni
#     reboot involucrados -- la Pi de Tector Mini esta siempre encendida,
#     asi que el boton dispara el flujo de hotspot directo.
#
# A diferencia de Tector1/2, este script no maneja radio WiFi apagado
# entre corridas (Tector Mini nunca apaga el radio, no hay
# cierre_amanecer/atardecer que lo hagan), no reinicia la Pi al terminar
# (no hay circuito de corte de energia ni falta hace, siempre esta
# conectada a la red o a una powerbank), y no calcula ni programa ninguna
# ventana de despertar (no hay RTC ni ventanas amanecer/atardecer).

FORZAR=0
if [ "$1" = "--force" ]; then
	FORZAR=1
fi

# Autodeteccion de rutas del proyecto
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

# Deteccion robusta del usuario real y su home (incluso si el script corre con sudo)
REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

export RCLONE_CONFIG="$USER_HOME/.config/rclone/rclone.conf"
export HOME="$USER_HOME"

LOG_PATH="$BASE_PATH/log_sistema.txt"
CONFIG_PATH="$BASE_PATH/config/config_general.txt"

DRIVE_PATH=$(awk -F'=' '/^DRIVE_PATH=/{print $2}' "$CONFIG_PATH" | tr -d '\r')
SYNC_REMOTE=$(awk -F'=' '/^SYNC_REMOTE=/{print $2}' "$CONFIG_PATH" | tr -d ' \r')
SYNC_REMOTE="${SYNC_REMOTE:-servidor}"
HOTSPOT_SSID=$(awk -F'=' '/^HOTSPOT_SSID=/{print $2}' "$CONFIG_PATH" | tr -d '\r')
HOTSPOT_PASSWORD=$(awk -F'=' '/^HOTSPOT_PASSWORD=/{print $2}' "$CONFIG_PATH" | tr -d '\r')

log() {
	python3 "$BASE_PATH/python/log_sistema.py" "$1"
}

FIRST_START=$(awk -F'=' '/FIRST_START/{print $2}' "$CONFIG_PATH" | tr -d '\r')

if [ "$FORZAR" != "1" ] && [ "$FIRST_START" != "TRUE" ]; then
	exit 0
fi

levantar_hotspot() {
	sudo ip addr flush dev wlan0
	sleep 1
	sudo pkill dnsmasq 2>/dev/null
	sleep 2
	sudo nmcli device wifi hotspot ifname wlan0 ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASSWORD" con-name Hotspot
	sleep 3
	sudo nmcli connection modify Hotspot ipv4.addresses 192.168.4.1/24 ipv4.method shared
	sudo nmcli connection up Hotspot
}

levantar_hotspot
if [ $? -ne 0 ]; then
	log "Primer intento fallido. Reintentando hotspot..."
	sleep 5
	levantar_hotspot
	if [ $? -ne 0 ]; then
		log "Error: no se pudo levantar el hotspot después de dos intentos."
		exit 1
	fi
fi

sleep 5

IP_HOTSPOT=$(ip addr show wlan0 | grep -oP 'inet \K[\d.]+')
log "Hotspot activo (IP: $IP_HOTSPOT)"

# Lanzar portal y capturar exit code
sudo python3 "$BASE_PATH/python/portal_configuracion.py"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
	log "Conexión fallida. Hotspot reactivado, esperando nuevas credenciales."
	exit 1
fi

# --- CONEXION EXITOSA ---

# Sincronizar hora por NTP. Sin RTC (ver README) -- fake-hwclock de
# Raspberry Pi OS retiene la hora entre reinicios sin red con precision
# de segundos, suficiente para timestamps de log sin ventanas que
# programar.
sudo systemctl restart systemd-timesyncd
sleep 5

SSID_CONECTADA=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2; exit}')

UBICACION=$(curl -s ipinfo.io/json)
LAT=$(echo $UBICACION | python3 -c "import sys,json; coords=json.load(sys.stdin)['loc'].split(','); print(coords[0])")
LON=$(echo $UBICACION | python3 -c "import sys,json; coords=json.load(sys.stdin)['loc'].split(','); print(coords[1])")
sed -i "s/LAT=.*/LAT=$LAT/" "$CONFIG_PATH"
sed -i "s/LON=.*/LON=$LON/" "$CONFIG_PATH"

# Si TectorNET-Pi esta instalado, propagarle las mismas coordenadas: las
# manda a BirdWeather junto con cada deteccion (config_birdweather.txt, claves
# LATITUDE/LONGITUDE, separadas de LAT/LON de este archivo). El motor relee
# X="$USER_HOME/TectorNET-Pi/config/config_birdweather.txt"
if [ -f "$BW_CONF" ]; then
	sed -i "s/^LATITUDE *=.*/LATITUDE = $LAT/" "$BW_CONF"
	sed -i "s/^LONGITUDE *=.*/LONGITUDE = $LON/" "$BW_CONF"
	sudo systemctl restart TectorNET-Pi.service 2>/dev/null
fi

# Marcar FIRST_START = FALSE
sed -i 's/FIRST_START=TRUE/FIRST_START=FALSE/' "$CONFIG_PATH"

log "Conectado a $SSID_CONECTADA."

# Subir log al remoto de sincronizacion
rclone copy "$LOG_PATH" "$SYNC_REMOTE:$DRIVE_PATH/"
bash "$BASE_PATH/scripts/generar_log_reciente.sh"

sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"
