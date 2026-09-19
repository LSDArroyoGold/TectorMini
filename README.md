# Tector Mini — Software

Este repositorio contiene el software de Tector Mini, la variante siempre-encendida (sin ventanas de grabación, sin batería, sin panel solar, sin RTC) del sistema de monitoreo autónomo de aves LSD-Tector, desarrollado en el Laboratorio de Sistemas Dinámicos (LSD), Facultad de Ciencias Exactas y Naturales, Universidad de Buenos Aires.

A diferencia de Tector1/Tector2.0 (que graban solo en ventanas de amanecer/atardecer y se apagan entre medio para ahorrar batería), Tector Mini se alimenta de una fuente de 5V dual diodo-OR'eada (adaptador de pared HLK-10M05 + powerbank USB-C de respaldo) y graba de forma continua, sin ningún ciclo de apagado/encendido programado. El sistema identifica especies con [TectorNET-Pi](https://github.com/LSDArroyoGold/TectorNET-Pi) (motor propio: Perch 2.0 + BirdSet EfficientNetB1, ambos ONNX) y envía cada detección al servidor propio del LSD-Tector y a BirdWeather. Para una descripción completa del hardware y el diseño físico del dispositivo, referirse al artículo asociado.

Este software fue desarrollado y probado sobre una **Raspberry Pi 4 Model B (2GB RAM)**. No se garantiza compatibilidad con otros modelos o configuraciones de hardware.

> [!NOTE]
> **Qué se sacó respecto a Tector1/Tector2.0, y por qué.** Tector Mini no tiene ventanas de grabación (`inicio_*.sh`/`cierre_*.sh`), ni corte/reposición de energía (`cortar-alimentacion.service`, latch 74HC74), ni RTC externo DS3231 (`sync-rtc.service`, `set_wake_rtc.py`) ni monitoreo de batería por INA219 (`chequeo_bateria.sh`) — todo eso resuelve un problema (sobrevivir con energía limitada, encendido programado) que no existe en un dispositivo alimentado de forma continua. `install.sh` y `actualizar_repo.sh` tampoco instalan/sincronizan nada de esto. Este repositorio es solo la capa de *dispositivo* (WiFi, botón, retención de disco, autoactualización); el motor de detección vive en el repo TectorNET-Pi, que se instala aparte (paso 8). `check_button.py` sí se mantiene, pero simplificado: reconfigurar el WiFi llama a `hotspot.sh --force` directamente (la Pi nunca duerme, no hace falta el reboot que usan Tector1/2 para volver a arrancar en modo hotspot).

---

## Dependencias

- Raspberry Pi OS Lite 64-bit (Bookworm o Trixie; probado en Trixie)
- TectorNET-Pi (motor de detección, ver paso 8)
- Python 3 (incluido en Raspberry Pi OS)
- rclone y ffmpeg — instalados automáticamente por `install.sh`
- Un micrófono USB
- nmcli (incluido en Raspberry Pi OS)
- dnsmasq y util-linux-extra — instalados automáticamente por `install.sh`

### 1. Sistema operativo

Instalar **Raspberry Pi OS Lite 64-bit** (Bookworm o Trixie) en la microSD usando [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Durante el proceso de flasheo, en la sección de configuración avanzada del Imager (ícono del engranaje), crear un usuario con nombre y contraseña a elección, y habilitar SSH.

> [!NOTE]
> Se usa Lite y no Full: el dispositivo corre siempre headless (todo el manejo es por SSH/cron), y el entorno gráfico de Full no aporta nada.

> [!NOTE]
> Los scripts detectan automáticamente la ubicación del repositorio y el usuario del sistema, por lo que no es necesario usar un nombre de usuario específico ni una ruta fija. El repositorio puede clonarse en cualquier ubicación y con cualquier usuario.

Una vez flasheada la microSD, insertarla en la Raspberry Pi y encenderla.

### 2. Clonar el repositorio

Repositorio privado (hace falta acceso a la organización LSDArroyoGold).

```bash
cd ~
git clone https://github.com/LSDArroyoGold/TectorMini.git
```

Los scripts se ejecutan directamente desde el repositorio, respetando su estructura de carpetas (`scripts/`, `python/`, `config/`, `systemd/`). No es necesario copiar ni mover archivos.

### 3. sudo sin contraseña

> [!IMPORTANT]
> Este paso no es opcional. Todo el sistema depende de que `cron` pueda ejecutar `sudo` (nmcli, systemctl, etc. en `hotspot.sh`) sin que haya nadie conectado para tipear una contraseña — el dispositivo corre desatendido.

```bash
echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR="tee" visudo -f /etc/sudoers.d/010-lsd-nopasswd
sudo chmod 440 /etc/sudoers.d/010-lsd-nopasswd
sudo visudo -c
```

La tercera línea valida la sintaxis del archivo nuevo antes de confiar en él. Verificar que funcionó:

```bash
sudo -n true && echo OK
```

### 4. Ejecutar el instalador

El script `install.sh` deja el sistema listo en una sola corrida: paquetes del sistema (`dnsmasq`, `util-linux-extra`, `ffmpeg`, `rclone`), permisos de ejecución a los scripts, instala y habilita `hotspot.service`, instala la rotación de logs (`logrotate-tector`), y configura el crontab con las cuatro tareas periódicas. Autodetecta la ubicación del repositorio y el usuario del sistema.

Ejecutarlo desde la raíz del repositorio, sin `sudo` (el script pide permisos de administrador solo donde los necesita):

```bash
cd ~/TectorMini
./install.sh
```

Verificar que la instalación fue exitosa:

```bash
sudo systemctl status hotspot.service
crontab -l
```

El crontab debe listar cinco tareas (la quinta, `sincronizar_detecciones.sh`, corre cada 10 minutos y reintenta subir las detecciones de los últimos 7 días que no hayan llegado al servidor): `check_button.py` (cada minuto, escucha el botón físico de reconfiguración en GPIO5) y `actualizar_repo.sh` (este repo; cada 15 minutos, barato: si el servidor no tiene un commit nuevo en `stable`, no hace nada), `actualizar_tectornet_pi.sh` (del repo TectorNET-Pi: `git fetch` desde el servidor, chequeo de salud y rollback automático; no hace nada hasta que TectorNET-Pi esté instalado) y `limpiar_retencion.sh` (estas dos una vez al día, de madrugada). Además crea el enlace `~/log_sistema.txt` → `~/TectorMini/log_sistema.txt`, para que las alertas de TectorNET-Pi caigan en el log real de Tector Mini (el que se sube al servidor).

### 5. rclone

`install.sh` ya instaló rclone (versión de los repos de Raspberry Pi OS).

**Conexión al servidor (SFTP)**

Tector Mini sube todo al servidor propio del LSD-Tector (`tectorserver`) por SFTP, con su propio usuario enjaulado (`tectormini`, solo escribe en `data/`) y una clave SSH por dispositivo. No hay tokens que venzan. Los pasos de alta están en `config/rclone.conf.ejemplo`; en resumen:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519_servidor
cat ~/.ssh/id_ed25519_servidor.pub          # agregarla en el servidor: /etc/ssh/tector_keys/tectormini y /srv/git/.ssh/authorized_keys (ver TectorHub-v2/docs/servicio-git.md)
ssh-keyscan 100.83.125.103 >> ~/.ssh/known_hosts
mkdir -p ~/.config/rclone
cp ~/TectorMini/config/rclone.conf.ejemplo ~/.config/rclone/rclone.conf && chmod 600 ~/.config/rclone/rclone.conf
rclone lsd servidor:data
```

Si el último comando lista las carpetas de `data/`, la configuración fue exitosa. La clave privada nunca sale del dispositivo.

### 6. Archivo de configuración

El archivo `config_general.txt` se encuentra en la carpeta `config/` del repositorio:

```bash
nano ~/TectorMini/config/config_general.txt
```

El archivo contiene los siguientes parámetros:

| Parámetro | Descripción |
|---|---|
| `SYNC_PATH` | Carpeta del servidor donde se sincronizan datos y logs. Siempre `data`, dentro del chroot del usuario SFTP. |
| `SYNC_REMOTE` | Nombre del remoto de rclone al que se sube todo (log, detecciones, retención). Por defecto `servidor`. |
| `RETENCION_AUDIO_LOCAL_MB` | Límite de espacio local antes de que `limpiar_retencion.sh` empiece a borrar carpetas de fecha enteras, empezando por la más vieja. El tope en el servidor lo maneja el propio servidor. |
| `FIRST_START` | Mantener en `TRUE` para activar el modo hotspot en el primer arranque. Una vez configurada la red WiFi exitosamente, el sistema lo cambia automáticamente a `FALSE`. Si el WiFi ya se configuró a mano (por ejemplo por SSH directo), poner en `FALSE` para no disparar el portal de configuración en el próximo arranque. |
| `HOTSPOT_SSID` | Nombre de la red WiFi de configuración que emite el dispositivo en el primer arranque, o al presionar el botón físico de reconfiguración. |
| `HOTSPOT_PASSWORD` | Contraseña de esa red WiFi de configuración. |
| `LAT` y `LON` | Coordenadas geográficas del lugar de instalación. Pueden dejarse con valores aproximados ya que se actualizan automáticamente mediante geolocalización por IP al utilizar el modo hotspot. |

> **Importante:** las variables se escriben sin espacios alrededor del signo `=` (formato `CLAVE=valor`). No modificar los nombres de las variables.

### 7. Verificar el destino en el servidor

Con `SYNC_PATH=data` y `SYNC_REMOTE=servidor`, las carpetas se crean solas en la primera subida. Verificar la conexión:

```bash
rclone lsd servidor:data
```

> **Nota:** la subcarpeta `Detecciones` es fija, y las detecciones quedan ahí organizadas en subcarpetas por fecha (`AAAA-MM-DD/<especie>/`, la misma convención de carpetas localmente en `~/BirdSongs/Extracted/By_Date/`).

Con esto, la capa de dispositivo de Tector Mini (WiFi, portal de configuración, log en el servidor, retención) ya está operativa. El paso que sigue instala el motor de detección.

### 8. TectorNET-Pi (motor de detección)

TectorNET-Pi graba con `arecord`, clasifica con Perch 2.0 (decide) + BirdSet EfficientNetB1 (confirma) usando solo `onnxruntime` (sin TensorFlow ni PyTorch, entra en los 2GB de la Pi 4), y sube cada detección a BirdWeather y al servidor en el momento. Corre como servicio systemd (`TectorNET-Pi.service`, `Restart=always`). Ver su README para el detalle del diseño.

```bash
cd ~
git clone -b stable tectorgit@100.83.125.103:tectornet-pi.git TectorNET-Pi
cd TectorNET-Pi
bash instalar.sh            # venv + dependencias + prueba de que el clasificador carga (baja Perch2 de HuggingFace, varios minutos)
```

Configuración del dispositivo (ambos archivos son datos del dispositivo y no se versionan):

```bash
cp config/config_birdweather.txt.ejemplo config/config_birdweather.txt
cp config/config_sincronizacion.txt.ejemplo config/config_sincronizacion.txt
nano config/config_birdweather.txt        # BIRDWEATHER_ID (token de la estación); LATITUDE/LONGITUDE los completa hotspot.sh solo
nano config/config_sincronizacion.txt     # DRIVE_REMOTE = servidor ; DRIVE_PATH = data ; DRIVE_SUBCARPETA = Detecciones ; REC_CARD / CHANNELS según el micrófono
```

`REC_CARD`/`CHANNELS` dependen del micrófono USB. Raspberry Pi OS Lite no trae PulseAudio, así que `default` no sirve: usar el nombre ALSA de la tarjeta (estable entre reinicios, a diferencia del número), por ejemplo `REC_CARD = plughw:CARD=Device,DEV=0` y `CHANNELS = 1` para un micrófono USB mono. `arecord -l` / `arecord -L` lista las tarjetas.

Registrar el servicio, marcar la instalación como lista para autoactualizarse (`actualizar_tectornet_pi.sh` no hace nada sin esa marca) y arrancarlo:

```bash
bash instalar_servicio.sh
touch ~/.tectornet_pi_migrado
sudo systemctl start TectorNET-Pi.service
journalctl -u TectorNET-Pi.service -f     # o: tail -f ~/TectorNET-Pi/motor.log
```

`instalar_servicio.sh` también habilita `linger` para el usuario (deja correr el servicio sin sesión abierta) y registra la rotación de `motor.log`.

> [!NOTE]
> La regla de logrotate que instala `instalar_servicio.sh` no trae la directiva `su`, así que logrotate se niega a rotar `motor.log` ("parent directory has insecure permissions"). Agregarla a mano una vez:
> ```bash
> sudo sed -i 's|^\tcopytruncate|\tcopytruncate\n\tsu lsd lsd|' /etc/logrotate.d/TectorNET-Pi
> sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -i "error: "   # no debe imprimir nada
> ```

> [!NOTE]
> Desde el primer día, `actualizar_tectornet_pi.sh` (cron, 03:23) mantiene TectorNET-Pi al día sin intervención: si el `git pull` trae algo que rompe el servicio, vuelve solo al commit anterior. Para forzarlo: `bash ~/TectorNET-Pi/scripts/actualizar_tectornet_pi.sh`.

---

## Primer arranque

1. Verificar que en `config_general.txt` el parámetro `FIRST_START` está en `TRUE`.
2. Encender la Raspberry Pi. Esperar aproximadamente 30 segundos a que el sistema arranque completamente y se active el servicio `hotspot.service`.
3. Desde un celular o computadora, buscar redes WiFi disponibles. Conectarse a la red de configuración (nombre y contraseña definidos en `HOTSPOT_SSID` y `HOTSPOT_PASSWORD`).
4. Abrir un navegador web y navegar a `http://192.168.4.1:5000`. Se mostrará el portal de configuración.
5. Seleccionar de la lista la red WiFi a la que se conectará el dispositivo. Ingresar la contraseña correspondiente. Presionar **Conectar**.
6. El dispositivo se desconecta del modo hotspot e intenta conectarse a la red indicada. Si la conexión es exitosa:
   - Las coordenadas geográficas se actualizan automáticamente mediante geolocalización por IP (y se propagan a `config_birdweather.txt` de TectorNET-Pi, si está instalado, reiniciando el servicio).
   - El parámetro `FIRST_START` se cambia a `FALSE`.
7. Si la conexión falla, la red de configuración vuelve a aparecer automáticamente. Reconectarse y reintentar con las credenciales correctas.

A partir de este momento, el dispositivo graba de forma continua.

> [!NOTE]
> Si el WiFi ya se configuró a mano durante la instalación (por ejemplo, por SSH directo sin pasar por el portal), este procedimiento no hace falta: dejar `FIRST_START=FALSE`.

### Reconfigurar el WiFi más adelante

Si hace falta cambiar de red WiFi después del primer arranque (sin acceso SSH a mano), mantener presionado el botón físico conectado a GPIO5 — `check_button.py`, que corre cada minuto por cron, detecta la pulsación y relanza `hotspot.sh --force`, saltando el chequeo de `FIRST_START` para levantar el portal de configuración de nuevo.

---

## Monitoreo remoto

`log_sistema.txt` y `log_reciente.txt` se suben al servidor (`data/`) cada vez que corre `hotspot.sh` con conexión exitosa o `generar_log_reciente.sh`, y permiten monitorear el estado del dispositivo de forma remota (también desde el Hub). Además `sincronizar_detecciones.sh` anota cada 10 min temperatura de CPU, `throttled`, carga, MHz reales, uptime, % de disco y RAM disponible en `log_salud.txt` y lo sube a `data/` (los bits 16-19 de `throttled` son latches de lo ocurrido desde el arranque; sirve para ver cuándo empezó un undervoltage).
