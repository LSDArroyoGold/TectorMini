#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

# Los dispositivos siguen la rama `stable` del servidor Tector (repo bare
# espejado desde GitHub, que solo la avanza si el codigo pasa bash -n /
# py_compile; ver tector-git-sync.sh en el servidor). Nunca hablan con GitHub.
SERVIDOR="tectorgit@100.83.125.103:tectormini.git"
export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519_servidor -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"
MARCA="$BASE_PATH/.ultima_actualizacion"
TMP="$BASE_PATH/.actualizar_tmp"
CACHE="$BASE_PATH/.software.git"

ULTIMO_SHA=$(cat "$MARCA" 2>/dev/null)

# Sin conexion al servidor (o sin cambios): salir en silencio, se reintenta
# en la proxima corrida.
SHA_ACTUAL=$(timeout 60 git ls-remote "$SERVIDOR" refs/heads/stable 2>/dev/null | cut -f1)

if [ -z "$SHA_ACTUAL" ] || [ "$SHA_ACTUAL" = "$ULTIMO_SHA" ]; then
	exit 0
fi

# $CACHE es solo un repo bare local desde donde se leen los archivos.
[ -d "$CACHE" ] || git init -q --bare "$CACHE"
if ! timeout 180 git --git-dir="$CACHE" fetch -q "$SERVIDOR" +refs/heads/stable:refs/heads/stable; then
	echo "Fallo la descarga desde el servidor, aborto sin tocar nada" >&2
	exit 1
fi
SHA_ACTUAL=$(git --git-dir="$CACHE" rev-parse refs/heads/stable)

# Todos los archivos que corren activamente. config_general.txt queda
# afuera a propósito: guarda estado en vivo del dispositivo (FIRST_START,
# coordenadas reales), no solo configuración de fábrica.
#
# config/rclone.conf tampoco va en esta lista: es configuracion propia de
# cada dispositivo (ver config/rclone.conf.ejemplo) y se pone a mano en
# ~/.config/rclone/rclone.conf.
ARCHIVOS="scripts/hotspot.sh scripts/generar_log_reciente.sh scripts/actualizar_repo.sh scripts/limpiar_retencion.sh scripts/sincronizar_detecciones.sh python/check_button.py python/log_sistema.py python/portal_configuracion.py systemd/hotspot.service config/logrotate-tector"

rm -rf "$TMP"
mkdir -p "$TMP"

for ARCHIVO in $ARCHIVOS; do
	mkdir -p "$TMP/$(dirname "$ARCHIVO")"
	if ! git --git-dir="$CACHE" show "$SHA_ACTUAL:$ARCHIVO" > "$TMP/$ARCHIVO" 2>/dev/null; then
		echo "Fallo la descarga de $ARCHIVO, aborto sin tocar nada" >&2
		rm -rf "$TMP"
		exit 1
	fi
done

SELF_CAMBIO=0
if [ ! -f "$BASE_PATH/scripts/actualizar_repo.sh" ] || ! cmp -s "$TMP/scripts/actualizar_repo.sh" "$BASE_PATH/scripts/actualizar_repo.sh"; then
	SELF_CAMBIO=1
fi

# Mismo filesystem que BASE_PATH: el mv es un rename atómico, seguro
# incluso si el archivo que se reemplaza es el que está corriendo ahora
# mismo (este mismo script, disparado por cron -- ver install.sh).
for ARCHIVO in $ARCHIVOS; do
	case "$ARCHIVO" in
		systemd/hotspot.service)
			# Tiene el placeholder __BASE_PATH__ (ver install.sh) -- no se
			# puede copiar tal cual a /etc/systemd/system.
			mv "$TMP/$ARCHIVO" "$BASE_PATH/$ARCHIVO"
			sed "s|__BASE_PATH__|$BASE_PATH|g" "$BASE_PATH/$ARCHIVO" | sudo tee /etc/systemd/system/hotspot.service > /dev/null
			sudo chmod 644 /etc/systemd/system/hotspot.service
			;;
		systemd/*)
			NOMBRE=$(basename "$ARCHIVO")
			mv "$TMP/$ARCHIVO" "$BASE_PATH/$ARCHIVO"
			sudo cp "$BASE_PATH/$ARCHIVO" "/etc/systemd/system/$NOMBRE"
			sudo chmod 644 "/etc/systemd/system/$NOMBRE"
			;;
		config/logrotate-tector)
			# No es una unit de systemd -- va a /etc/logrotate.d/, corre solo
			# via el cron.daily estandar de logrotate, no necesita reload ni
			# enable de nada.
			mv "$TMP/$ARCHIVO" "$BASE_PATH/$ARCHIVO"
			sudo cp "$BASE_PATH/$ARCHIVO" /etc/logrotate.d/tector
			sudo chown root:root /etc/logrotate.d/tector
			sudo chmod 644 /etc/logrotate.d/tector
			;;
		*)
			mv "$TMP/$ARCHIVO" "$BASE_PATH/$ARCHIVO"
			;;
	esac
done

chmod +x "$BASE_PATH"/scripts/*.sh
sudo systemctl daemon-reload

rm -rf "$TMP"

# Si actualizar_repo.sh cambió, la lista de $ARCHIVOS que acabamos de usar
# para bajar todo puede ser la vieja (la que ya estaba cargada en memoria
# al arrancar esta corrida) -- por ejemplo, si el mismo commit que nos trajo
# esta versión nueva también agregó un archivo a la lista. Nos volvemos a
# ejecutar una vez con la versión ya instalada para completar el ciclo con
# la lista correcta antes de marcar la actualización como terminada.
# _REEXEC evita un bucle si por lo que sea el archivo siguiera "cambiando".
if [ "$SELF_CAMBIO" = "1" ] && [ -z "$_REEXEC" ]; then
	_REEXEC=1 exec bash "$BASE_PATH/scripts/actualizar_repo.sh"
fi

echo "$SHA_ACTUAL" > "$MARCA"

echo "[$(date '+%Y-%m-%d %H:%M')] Software actualizado ($SHA_ACTUAL)" >> "$BASE_PATH/log_sistema.txt"
