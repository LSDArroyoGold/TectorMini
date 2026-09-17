import sys
from pathlib import Path
from datetime import datetime

BASE_PATH = Path(__file__).resolve().parent.parent
LOG_SISTEMA = BASE_PATH / 'log_sistema.txt'

timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')
mensaje = sys.argv[1]
linea = f"[{timestamp}] {mensaje}\n"

with open(LOG_SISTEMA, 'a') as f:
    f.write(linea)
print(linea.strip())
