#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
src="SolidSecViewer/Assets.xcassets/TakopiLogo.imageset/takopi.png"
icon="SolidSecViewer/Assets.xcassets/AppIcon.appiconset/TakopiIcon.png"
mkdir -p build/icon
test -s "$src"
sips -s format jpeg -z 1024 1024 "$src" --out build/icon/takopi-opaque.jpg >/dev/null
sips -s format png build/icon/takopi-opaque.jpg --out "$icon" >/dev/null
python3 - <<'PY'
import struct
from pathlib import Path
data = Path("SolidSecViewer/Assets.xcassets/AppIcon.appiconset/TakopiIcon.png").read_bytes()
assert data.startswith(bytes.fromhex("89504e470d0a1a0a"))
assert struct.unpack(">II", data[16:24]) == (1024, 1024)
assert data[25] in (2, 3), "AppIcon must have no alpha"
print("Icono de Takopi preparado: OK")
PY
