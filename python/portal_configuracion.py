# -*- coding: utf-8 -*-
import http.server
import urllib.parse
import subprocess
import re
import time
import threading
import os
from pathlib import Path

BASE_PATH = Path(__file__).resolve().parent.parent
CONFIG_PATH = BASE_PATH / 'config' / 'config_general.txt'


# ---------- UTILIDADES ----------

def leer_config(archivo, clave):
    with open(archivo) as f:
        for linea in f:
            linea = linea.strip()
            if linea.startswith('#') or '=' not in linea:
                continue
            k, v = linea.split('=', 1)
            if k.strip() == clave:
                return v.strip()


HOTSPOT_SSID = leer_config(CONFIG_PATH, 'HOTSPOT_SSID')
HOTSPOT_PASSWORD = leer_config(CONFIG_PATH, 'HOTSPOT_PASSWORD')


def escanear_redes():
    subprocess.run(['sudo', 'nmcli', 'device', 'wifi', 'rescan'],
                   capture_output=True, text=True)
    time.sleep(3)
    result = subprocess.run(
        ['nmcli', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'device', 'wifi', 'list'],
        capture_output=True, text=True
    )
    redes = []
    seen = set()
    for linea in result.stdout.strip().split('\n'):
        partes = linea.split(':')
        if len(partes) >= 2:
            ssid = partes[0].strip()
            if ssid and ssid not in seen:
                seen.add(ssid)
                signal = partes[1].strip() if len(partes) > 1 else '?'
                security = partes[2].strip() if len(partes) > 2 else ''
                redes.append((ssid, signal, security))
    return redes


def intentar_conexion(ssid, password):
    # Bajar hotspot
    subprocess.run(['sudo', 'nmcli', 'connection', 'down', 'Hotspot'],
                   capture_output=True, text=True)
    time.sleep(3)

    # Borrar perfil previo si existe
    subprocess.run(['sudo', 'nmcli', 'connection', 'delete', ssid],
                   capture_output=True, text=True)

    # Crear nueva conexión con key-mgmt explícito
    result_add = subprocess.run(
        ['sudo', 'nmcli', 'connection', 'add',
         'type', 'wifi',
         'ifname', 'wlan0',
         'con-name', ssid,
         'ssid', ssid,
         '802-11-wireless-security.key-mgmt', 'wpa-psk',
         '802-11-wireless-security.psk', password],
        capture_output=True, text=True, timeout=30
    )

    if result_add.returncode != 0:
        print(f"DEBUG add error: {result_add.stderr}")
        return False

    # Activar la conexión
    result_up = subprocess.run(
        ['sudo', 'nmcli', 'connection', 'up', ssid],
        capture_output=True, text=True, timeout=60
    )

    print(f"DEBUG up returncode: {result_up.returncode}")
    print(f"DEBUG up stdout: {result_up.stdout}")
    print(f"DEBUG up stderr: {result_up.stderr}")

    return result_up.returncode == 0


def reactivar_hotspot():
    subprocess.run(
        ['sudo', 'nmcli', 'device', 'wifi', 'hotspot',
         'ifname', 'wlan0', 'ssid', HOTSPOT_SSID, 'password', HOTSPOT_PASSWORD],
        capture_output=True, text=True
    )


# ---------- HTML ----------

def generar_html_redes(redes):
    opciones = ''
    for ssid, signal, security in redes:
        icono = '🔒 ' if security and security != '--' else ''
        opciones += f'<option value="{ssid}">{icono}{ssid} ({signal}%)</option>\n'

    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>LSD-Tector Setup</title>
    <style>
        body {{ font-family: Arial, sans-serif; max-width: 400px; margin: 50px auto; padding: 20px; }}
        select, input[type="text"], input[type="password"] {{
            width: 100%; padding: 14px; margin: 10px 0;
            box-sizing: border-box; font-size: 16px; }}
        button {{ width: 100%; padding: 14px; background: #4CAF50; color: white;
            border: none; cursor: pointer; font-size: 18px; border-radius: 4px; }}
        .refresh-btn {{ background: #888; margin-bottom: 10px; font-size: 14px; padding: 10px; }}
        h1 {{ color: #333; }}
        label {{ font-size: 16px; }}
        .checkbox-line {{ margin: 10px 0; font-size: 14px; }}
    </style>
    <script>
        function toggleMostrar() {{
            var pwd = document.getElementById('password');
            pwd.type = pwd.type === 'password' ? 'text' : 'password';
        }}
    </script>
</head>
<body>
    <h1>LSD-Tector Setup</h1>
    <p>Seleccioná la red WiFi a la que se conectará el dispositivo.</p>
    <form method="POST" action="/configurar">
        <label>Red WiFi disponible:</label>
        <select name="ssid" required>
            {opciones}
        </select>
        <button type="button" class="refresh-btn" onclick="location.reload()">↻ Actualizar lista de redes</button>
        <label>Contraseña:</label>
        <input type="password" name="password" id="password" required>
        <div class="checkbox-line">
            <input type="checkbox" onclick="toggleMostrar()"> Mostrar contraseña
        </div>
        <button type="submit">Conectar</button>
    </form>
</body>
</html>"""


HTML_ESPERA = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>LSD-Tector Setup</title>
    <style>
        body {{ font-family: Arial, sans-serif; max-width: 400px; margin: 50px auto; padding: 20px; }}
        h1 {{ color: #333; }}
        p {{ font-size: 16px; line-height: 1.6; }}
    </style>
</head>
<body>
    <h1>Conectando...</h1>
    <p>Las credenciales fueron enviadas al dispositivo. El proceso puede tardar hasta 1 minuto.</p>
    <p>Para verificar el resultado:</p>
    <p>✅ Si la conexión fue <strong>exitosa</strong>: el archivo <strong>log_sistema.txt</strong>
    en Google Drive mostrará una entrada de conexión exitosa y el dispositivo se apagará automáticamente.</p>
    <p>📶 Si la conexión <strong>falló</strong>: el hotspot <strong>{HOTSPOT_SSID}</strong>
    volverá a aparecer en tu lista de redes WiFi. Volvé a conectarte y reintentá.</p>
</body>
</html>"""


# ---------- SERVIDOR ----------

class Handler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        redes = escanear_redes()
        html = generar_html_redes(redes)
        self.send_response(200)
        self.send_header('Content-type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode('utf-8'))

    def do_POST(self):
        content_length = self.headers.get('Content-Length')
        if not content_length:
            self.send_response(302)
            self.send_header('Location', '/')
            self.end_headers()
            return
        length = int(content_length)
        data = urllib.parse.parse_qs(self.rfile.read(length).decode())
        ssid = data.get('ssid', [''])[0]
        password = data.get('password', [''])[0]

        self.send_response(200)
        self.send_header('Content-type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(HTML_ESPERA.encode('utf-8'))
        self.wfile.flush()

        def cambiar_red():
            time.sleep(2)
            exito = intentar_conexion(ssid, password)
            if exito:
                os._exit(0)
            else:
                reactivar_hotspot()

        threading.Thread(target=cambiar_red).start()

    def log_message(self, format, *args):
        pass


if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', 5000), Handler)
    print("Portal de configuracion iniciado en puerto 5000")
    server.serve_forever()
