#!/bin/bash
#
# install.sh - Instalador de Tector Mini
#
# Deja el sistema completamente listo para operar: paquetes del sistema,
# permisos, servicios systemd y crontab. Autodetecta la ubicacion del
# repositorio y el usuario.
#
# No instala TectorNET-Pi (repo aparte, ver README) ni configura rclone
# (necesita autenticacion interactiva con Google, ver README) -- eso queda
# aparte a proposito.
#
# Uso: ./install.sh   (NO con sudo; el script pide sudo donde lo necesita)

set -e

# --- Autodeteccion de rutas ---
BASE_PATH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SCRIPTS_DIR="$BASE_PATH/scripts"
PYTHON_DIR="$BASE_PATH/python"
SYSTEMD_DIR="$BASE_PATH/systemd"

# --- Deteccion del usuario real (aunque se corra con sudo por error) ---
REAL_USER="${SUDO_USER:-$(whoami)}"

echo "==> Instalando Tector Mini"
echo "    Repositorio detectado en: $BASE_PATH"
echo "    Usuario: $REAL_USER"
echo ""

# --- 1. Paquetes del sistema ---
echo "==> Paquetes del sistema (dnsmasq, util-linux-extra)"
sudo apt-get update -qq
sudo apt-get install -y -qq dnsmasq util-linux-extra

# NO habilitar dnsmasq como servicio systemd: hotspot.sh lo mata a mano
# (pkill dnsmasq) antes de levantar el AP, y NetworkManager lanza su propia
# instancia privada al activar la conexion Hotspot (ipv4.method shared).
# Un dnsmasq systemd corriendo de forma standalone escucha DHCP/DNS en todas
# las interfaces por default, incluida wlan0 mientras esta conectada como
# cliente normal -- eso corto la conexion de wlan0 la primera vez que se
# corrio este instalador en Tector2. Solo hace falta el paquete instalado.
sudo systemctl disable --now dnsmasq 2>/dev/null || true

# --- 2. Permisos de ejecucion a los scripts ---
echo "==> Dando permisos de ejecucion a los scripts .sh"
chmod +x "$SCRIPTS_DIR"/*.sh

# --- 3. Servicio systemd ---
echo "==> Instalando servicio systemd"

# hotspot.service: reemplazar el placeholder __BASE_PATH__ por la ruta real
sed "s|__BASE_PATH__|$BASE_PATH|g" "$SYSTEMD_DIR/hotspot.service" \
	| sudo tee /etc/systemd/system/hotspot.service > /dev/null
sudo chmod 644 /etc/systemd/system/hotspot.service

sudo systemctl daemon-reload
sudo systemctl enable hotspot.service

echo "    Servicio hotspot.service habilitado"

# --- 4. Rotacion de logs (logrotate) ---
echo "==> Instalando rotacion de logs"
sudo cp "$BASE_PATH/config/logrotate-tector" /etc/logrotate.d/tector
sudo chown root:root /etc/logrotate.d/tector
sudo chmod 644 /etc/logrotate.d/tector
echo "    /etc/logrotate.d/tector instalado (corre solo via el cron.daily estandar de logrotate)"

# --- 5. Crontab del usuario ---
echo "==> Configurando crontab para el usuario $REAL_USER"

# Lineas del crontab, apuntando a las rutas reales del repo. Tector Mini no
# tiene ventanas amanecer/atardecer (siempre encendido) asi que, a
# diferencia de Tector1/2, check_button.py es la unica tarea de alta
# frecuencia -- el resto (repo, TectorNET-Pi, retencion) corre una vez al dia,
# alcanza porque no hay urgencia de horario detras de ninguna de las tres.
# actualizar_tectornet_pi.sh es del repo TectorNET-Pi (git pull + chequeo de
# salud + rollback); sale solo si TectorNET-Pi todavia no esta instalado.
TECTORNET_UPDATE="$HOME/TectorNET-Pi/scripts/actualizar_tectornet_pi.sh"
CRON_LINES="* * * * * python3 $PYTHON_DIR/check_button.py
17 3 * * * $SCRIPTS_DIR/actualizar_repo.sh
23 3 * * * $TECTORNET_UPDATE
41 3 * * * $SCRIPTS_DIR/limpiar_retencion.sh"

# Tomar el crontab actual del usuario (si existe), quitar cualquier linea previa
# de Tector Mini para no duplicar, y agregar las nuevas.
CRON_ACTUAL=$(crontab -u "$REAL_USER" -l 2>/dev/null | grep -v "$SCRIPTS_DIR" | grep -v "$PYTHON_DIR/check_button.py" | grep -v "actualizar_tectornet_pi.sh" || true)

printf '%s\n%s\n' "$CRON_ACTUAL" "$CRON_LINES" | grep -v '^$' | crontab -u "$REAL_USER" -

echo "    Crontab configurado con 4 tareas"

# --- 6. Log de sistema en la ruta "plana" ---
# actualizar_tectornet_pi.sh y motor.py escriben sus alertas a
# /home/lsd/log_sistema.txt salvo que exista /home/lsd/LSD-Tector2.0 (ver
# esos scripts). Un symlink hace que caigan en el log real de Tector Mini,
# el que se sube a Drive.
touch "$BASE_PATH/log_sistema.txt"
ln -sfn "$BASE_PATH/log_sistema.txt" "$HOME/log_sistema.txt"

# --- Fin ---
echo ""
echo "==> Instalacion completada."
echo "    Verifica el servicio con: sudo systemctl status hotspot.service"
echo "    Verifica el crontab con:  crontab -l"
