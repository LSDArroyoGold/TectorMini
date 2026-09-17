# Tector Mini — Software

Este repositorio contiene el software de Tector Mini, la variante siempre-encendida (sin ventanas de grabación, sin batería, sin panel solar, sin RTC) del sistema de monitoreo autónomo de aves LSD-Tector, desarrollado en el Laboratorio de Sistemas Dinámicos (LSD), Facultad de Ciencias Exactas y Naturales, Universidad de Buenos Aires.

A diferencia de Tector1/Tector2.0 (que graban solo en ventanas de amanecer/atardecer y se apagan entre medio para ahorrar batería), Tector Mini se alimenta de una fuente de 5V dual diodo-OR'eada (adaptador de pared HLK-10M05 + powerbank USB-C de respaldo) y graba de forma continua, sin ningún ciclo de apagado/encendido programado. El sistema identifica especies mediante BirdNET-Pi y envía detecciones a Google Drive. Para una descripción completa del hardware y el diseño físico del dispositivo, referirse al artículo asociado.

Este software fue desarrollado y probado sobre una **Raspberry Pi 4 Model B (2GB RAM)**. No se garantiza compatibilidad con otros modelos o configuraciones de hardware.

> [!NOTE]
> **Qué se sacó respecto a Tector1/Tector2.0, y por qué.** Tector Mini no tiene ventanas de grabación (`inicio_*.sh`/`cierre_*.sh`), ni corte/reposición de energía (`cortar-alimentacion.service`, latch 74HC74), ni RTC externo DS3231 (`sync-rtc.service`, `set_wake_rtc.py`) ni monitoreo de batería por INA219 (`chequeo_bateria.sh`) — todo eso resuelve un problema (sobrevivir con energía limitada, encendido programado) que no existe en un dispositivo alimentado de forma continua. `install.sh` y `actualizar_repo.sh` tampoco instalan/sincronizan nada de esto. `check_button.py` sí se mantiene, pero simplificado: reconfigurar el WiFi llama a `hotspot.sh --force` directamente (la Pi nunca duerme, no hace falta el reboot que usan Tector1/2 para volver a arrancar en modo hotspot).

---

## Dependencias

- Raspberry Pi OS Lite 64-bit (Bookworm)
- BirdNET-Pi (ver paso 8; salteable si por ahora solo se quiere probar el software propio de Tector)
- [LSDTector-BirdNET-retrain-bsas](https://github.com/LSDArroyoGold/LSDTector-BirdNET-retrain-bsas) (clasificador reentrenado, opcional — ver paso 8.5)
- Python 3 (incluido en Raspberry Pi OS)
- rclone
- nmcli (incluido en Raspberry Pi OS)
- dnsmasq y util-linux-extra — instalados automáticamente por `install.sh`

### 1. Sistema operativo

Instalar **Raspberry Pi OS Lite 64-bit (Bookworm)** en la microSD usando [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Durante el proceso de flasheo, en la sección de configuración avanzada del Imager (ícono del engranaje), crear un usuario con nombre y contraseña a elección, y habilitar SSH.

> [!NOTE]
> Se usa Lite y no Full: el dispositivo corre siempre headless (todo el manejo es por SSH/cron), y el entorno gráfico de Full no aporta nada.

> [!NOTE]
> Los scripts detectan automáticamente la ubicación del repositorio y el usuario del sistema, por lo que no es necesario usar un nombre de usuario específico ni una ruta fija. El repositorio puede clonarse en cualquier ubicación y con cualquier usuario.

Una vez flasheada la microSD, insertarla en la Raspberry Pi y encenderla.

### 2. Clonar el repositorio

```bash
cd ~
git clone https://github.com/LSDArroyoGold/TectorMini.git
```

Los scripts se ejecutan directamente desde el repositorio, respetando su estructura de carpetas (`scripts/`, `python/`, `config/`, `systemd/`). No es necesario copiar ni mover archivos.

### 3. sudo sin contraseña

> [!IMPORTANT]
> Este paso no es opcional. Todo el sistema depende de que `cron` pueda ejecutar `sudo` (nmcli, systemctl, etc. en `hotspot.sh`) sin que haya nadie conectado para tipear una contraseña — el dispositivo corre desatendido. También lo exige el instalador oficial de BirdNET-Pi (paso 8), que aborta si no lo detecta.

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

El script `install.sh` deja el sistema listo en una sola corrida: paquetes del sistema (`dnsmasq`, `util-linux-extra`), permisos de ejecución a los scripts, instala y habilita `hotspot.service`, instala la rotación de logs (`logrotate-tector`), y configura el crontab con las cuatro tareas periódicas. Autodetecta la ubicación del repositorio y el usuario del sistema.

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

El crontab debe listar cuatro tareas: `check_button.py` (cada minuto, escucha el botón físico de reconfiguración en GPIO5) y `actualizar_repo.sh`/`actualizar_modelo.sh`/`limpiar_retencion.sh` (una vez al día cada una, de madrugada).

### 5. rclone

Instalar rclone:

```bash
sudo apt install rclone
```

**Autenticación con Google Drive**

La autenticación con Google requiere un navegador con interfaz gráfica. Como BirdNET-Pi ocupa el navegador de la Raspberry Pi, la autenticación se realiza desde una PC con Windows o Linux como intermediaria.

**En la PC intermediaria:**

1. Descargar rclone para el sistema operativo correspondiente desde [https://rclone.org/downloads/](https://rclone.org/downloads/)
2. Descomprimir el archivo
3. Abrir una terminal (PowerShell en Windows) en la carpeta donde se descomprimió rclone
4. Ejecutar el siguiente comando:

```bash
.\rclone.exe authorize "drive" --drive-scope drive.file
```

> **Nota:** en Linux o macOS el comando es `./rclone authorize "drive" --drive-scope drive.file`. El flag `--drive-scope drive.file` es imprescindible — sin él, rclone pide el scope completo (`drive`), que Google clasifica como "restringido" y cuyo refresh token caduca cada 7 días sin verificación adicional. Ver `config/rclone.conf.ejemplo` para el detalle completo de este problema y su solución.

5. El navegador se abrirá automáticamente. Iniciar sesión con la cuenta de Google deseada y otorgar los permisos solicitados.
6. La terminal mostrará un token JSON entre llaves (`{...}`). Copiar el token completo, incluyendo las llaves.

**En la Raspberry Pi:**

Copiar `config/rclone.conf.ejemplo` a `~/.config/rclone/rclone.conf`, completar `client_id`, `client_secret` y `token` con los valores obtenidos, y verificar la conexión:

```bash
mkdir -p ~/.config/rclone
cp ~/TectorMini/config/rclone.conf.ejemplo ~/.config/rclone/rclone.conf
nano ~/.config/rclone/rclone.conf
rclone lsd gdrive:
```

Si el comando devuelve la lista de carpetas existentes en la cuenta de Google, la configuración fue exitosa.

### 6. Archivo de configuración

El archivo `config_general.txt` se encuentra en la carpeta `config/` del repositorio:

```bash
nano ~/TectorMini/config/config_general.txt
```

El archivo contiene los siguientes parámetros:

| Parámetro | Descripción |
|---|---|
| `DRIVE_PATH` | Ruta de la carpeta en Google Drive donde se sincronizan datos y configuración. Puede ser una carpeta en la raíz (ej: `Tector Mini`) o anidada. |
| `RETENCION_AUDIO_LOCAL_MB` / `RETENCION_DRIVE_MB` | Límite de espacio (local y en Drive) antes de que `limpiar_retencion.sh` empiece a borrar carpetas de fecha enteras, empezando por la más vieja. |
| `FIRST_START` | Mantener en `TRUE` para activar el modo hotspot en el primer arranque. Una vez configurada la red WiFi exitosamente, el sistema lo cambia automáticamente a `FALSE`. Si el WiFi ya se configuró a mano (por ejemplo por SSH directo), poner en `FALSE` para no disparar el portal de configuración en el próximo arranque. |
| `HOTSPOT_SSID` | Nombre de la red WiFi de configuración que emite el dispositivo en el primer arranque, o al presionar el botón físico de reconfiguración. |
| `HOTSPOT_PASSWORD` | Contraseña de esa red WiFi de configuración. |
| `LAT` y `LON` | Coordenadas geográficas del lugar de instalación. Pueden dejarse con valores aproximados ya que se actualizan automáticamente mediante geolocalización por IP al utilizar el modo hotspot. |
| `EBIRD_API_KEY` | Opcional. Ver comentario en el propio archivo. |

> **Importante:** las variables se escriben sin espacios alrededor del signo `=` (formato `CLAVE=valor`). No modificar los nombres de las variables.

### 7. Crear carpeta en Google Drive y subir la configuración inicial

Usando la ruta definida en `DRIVE_PATH` (en los ejemplos siguientes se asume `DRIVE_PATH=Tector Mini`):

```bash
rclone mkdir "gdrive:Tector Mini"
rclone mkdir "gdrive:Tector Mini/Detecciones"
rclone copy ~/TectorMini/config/config_general.txt "gdrive:Tector Mini/"
```

Verificar:

```bash
rclone ls "gdrive:Tector Mini/"
```

> **Nota:** la subcarpeta `Detecciones` es fija, y las detecciones quedan ahí organizadas en subcarpetas por fecha (heredadas de la estructura que ya usa BirdNET-Pi localmente).

Con esto, el software propio de Tector Mini (WiFi, portal de configuración, sincronización con Drive) ya está completamente operativo. Los dos pasos que siguen son sobre BirdNET-Pi, opcionales para llegar a este punto.

### 8. BirdNET-Pi

BirdNET-Pi es el motor de grabación, análisis y extracción de detecciones: Tector Mini no reimplementa nada de eso, se apoya en su pipeline (`birdnet_recording.service` + `birdnet_analysis.service`) y en su convención de carpetas (`BirdSongs/Extracted/By_Date/`), de la que depende directamente `limpiar_retencion.sh`. También se usa su integración nativa con BirdWeather.

> [!NOTE]
> Si el objetivo inmediato es solo poner en marcha la Raspberry con el software propio de Tector y dejar BirdNET-Pi para después, este paso puede saltearse: nada de los pasos anteriores depende de que esté presente.

> [!NOTE]
> **Alternativa:** [`TectorNET-Pi`](https://github.com/LSDArroyoGold/TectorNET-Pi) es un motor de grabación y análisis propio, en reemplazo completo de BirdNET-Pi. Usa la misma convención de carpetas y nombre de archivo. Sincroniza a BirdWeather y Drive por detección (no periódico) — ver la sección de sincronización en su propio README.

Desde la terminal de la RP, ejecutar:

```bash
curl -s https://raw.githubusercontent.com/Nachtzuster/BirdNET-Pi/main/newinstaller.sh | bash
```

La instalación tarda varios minutos (y necesita `sudo` sin contraseña — ver paso 3). Una vez finalizada, BirdNET-Pi queda corriendo automáticamente y es accesible desde cualquier dispositivo en la misma red ingresando `http://[IP_de_la_RP]` en el navegador. Para obtener la IP de la Raspberry Pi:

```bash
hostname -I
```

### 8.5. Configurar BirdNET-Pi para uso desatendido, y cargar el modelo reentrenado

El script `configurar_birdnet.sh` apaga y enmascara los servicios de dashboard/streaming que no hacen falta en un dispositivo desatendido, arranca en modo consola, configura la gestión de disco, deja `CONFIDENCE`/`SENSITIVITY` en los valores de partida, y de paso pide el token de BirdWeather:

```bash
cd ~/TectorMini
./scripts/configurar_birdnet.sh
```

Correrlo una sola vez, después de instalar BirdNET-Pi. El token de BirdWeather queda guardado en `birdnet.conf` (fuera de este repositorio, nunca se sube a GitHub).

> [!NOTE]
> El modelo reentrenado (las 193 especies locales, además del catálogo global de BirdNET sin modificar) se instala aparte, automáticamente, mediante `actualizar_modelo.sh`: corre una vez al día por cron y actualiza el `.tflite` cada vez que hay una versión nueva en [`LSDTector-BirdNET-retrain-bsas`](https://github.com/LSDArroyoGold/LSDTector-BirdNET-retrain-bsas), sin necesidad de reinstalar nada a mano. Para forzarlo de inmediato: `bash ~/TectorMini/scripts/actualizar_modelo.sh`.

> [!NOTE]
> Además del modelo universal, `LSDTector-BirdNET-retrain-bsas` permite generar una versión ajustada a la región del dispositivo: a cada una de las 193 especies locales se le suma un sesgo según su frecuencia real de observación en esa región. Corre solo, vía `scripts/aplicar_ajuste_regional.sh` (llamado al final de `actualizar_modelo.sh`, y también desde `hotspot.sh` justo después de geolocalizar), pero necesita el entorno `~/birdnet-v2-env` (`bash instalar.sh` dentro de un clon de `LSDTector-BirdNET-retrain-bsas`). Prioriza un archivo de frecuencias ya descargado a mano y versionado en ese repositorio (sin conexión a eBird desde el dispositivo); si todavía no existe para la región y se cargó `EBIRD_API_KEY`, usa la API pública de eBird como respaldo.

---

## Primer arranque

1. Verificar que en `config_general.txt` el parámetro `FIRST_START` está en `TRUE`.
2. Encender la Raspberry Pi. Esperar aproximadamente 30 segundos a que el sistema arranque completamente y se active el servicio `hotspot.service`.
3. Desde un celular o computadora, buscar redes WiFi disponibles. Conectarse a la red de configuración (nombre y contraseña definidos en `HOTSPOT_SSID` y `HOTSPOT_PASSWORD`).
4. Abrir un navegador web y navegar a `http://192.168.4.1:5000`. Se mostrará el portal de configuración.
5. Seleccionar de la lista la red WiFi a la que se conectará el dispositivo. Ingresar la contraseña correspondiente. Presionar **Conectar**.
6. El dispositivo se desconecta del modo hotspot e intenta conectarse a la red indicada. Si la conexión es exitosa:
   - Las coordenadas geográficas se actualizan automáticamente mediante geolocalización por IP (y se propagan a `birdnet.conf` si BirdNET-Pi está instalado).
   - El parámetro `FIRST_START` se cambia a `FALSE`.
7. Si la conexión falla, la red de configuración vuelve a aparecer automáticamente. Reconectarse y reintentar con las credenciales correctas.

A partir de este momento, el dispositivo graba de forma continua.

> [!NOTE]
> Si el WiFi ya se configuró a mano durante la instalación (por ejemplo, por SSH directo sin pasar por el portal), este procedimiento no hace falta: dejar `FIRST_START=FALSE`.

### Reconfigurar el WiFi más adelante

Si hace falta cambiar de red WiFi después del primer arranque (sin acceso SSH a mano), mantener presionado el botón físico conectado a GPIO5 — `check_button.py`, que corre cada minuto por cron, detecta la pulsación y relanza `hotspot.sh --force`, saltando el chequeo de `FIRST_START` para levantar el portal de configuración de nuevo.

---

## Control remoto via Google Drive

Una vez el dispositivo está en operación, el archivo `config_general.txt` en la carpeta de Google Drive definida por `DRIVE_PATH` puede editarse desde cualquier lugar. Los cambios se aplican la próxima vez que corre `hotspot.sh` (primer arranque o botón de reconfiguración) o el cron diario correspondiente, según el parámetro.

El archivo `log_sistema.txt` se sube a Drive cada vez que corre `hotspot.sh` con conexión exitosa, y permite monitorear el estado del dispositivo de forma remota.
