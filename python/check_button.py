import RPi.GPIO as GPIO
import subprocess
from pathlib import Path

BASE_PATH = Path(__file__).resolve().parent.parent

# GPIO5 (pin fisico 29), cableado a GND (pin fisico 30, el de al lado) con
# pull-up interno -- boton activo en bajo. A diferencia de Tector1/2 (GPIO24
# a 3.3V con PUD_DOWN), Tector Mini no tiene circuito de latch de encendido
# que coordinar, asi que cualquier GPIO libre sirve; se eligio GPIO5 por
# quedar junto a un pin de GND en el header de 40 pines.
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)
GPIO.setup(5, GPIO.IN, pull_up_down=GPIO.PUD_UP)

if GPIO.input(5) == 0:
    GPIO.cleanup()
    # La Pi de Tector Mini nunca duerme, asi que a diferencia de
    # check_button.py de Tector1/2 no hace falta marcar un flag y
    # reiniciar para "entrar en modo configuracion" -- se llama a
    # hotspot.sh directo, con --force para saltear el chequeo de
    # FIRST_START (que hotspot.sh solo usa para el flujo de primer
    # arranque).
    subprocess.run(['sudo', 'bash', str(BASE_PATH / 'scripts' / 'hotspot.sh'), '--force'])
else:
    GPIO.cleanup()
