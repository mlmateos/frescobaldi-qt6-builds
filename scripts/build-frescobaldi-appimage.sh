#!/usr/bin/env bash
#===============================================================================
# build-frescobaldi-appimage.sh (v2.0-Limpia)
# Genera AppImage autocontenido de Frescobaldi usando PyInstaller + appimagetool
#===============================================================================
set -euo pipefail
#===============================================================================
# CONFIGURACIÓN BASE
#===============================================================================
REPO_URL="https://github.com/frescobaldi/frescobaldi.git"
GITHUB_USER="mlmateos"
REPO_NAME="frescobaldi-qt6-builds"
BRANCH="v4.0.7"
CLEAN_BUILD=false
ENABLE_POPPLER=false
SIGN=false
PUBLISH=false
GPG_KEY=""
MAX_RETRIES=3
RETRY_DELAY=5
KEEP_SOURCE=true
#===============================================================================
# ARGUMENTOS
#===============================================================================
while [[ $# -gt 0 ]]; do
case "$1" in
--clean)          CLEAN_BUILD=true; shift ;;
--branch)         BRANCH="$2"; shift 2 ;;
--poppler)        ENABLE_POPPLER=true; shift ;;
--sign)           SIGN=true; shift ;;
--publish)        PUBLISH=true; shift ;;
--gpg-key)        GPG_KEY="$2"; shift 2 ;;
--yes)            shift ;;
--no-keep-source) KEEP_SOURCE=false; shift ;;
--help|-h)        echo "Uso: ./build-frescobaldi-appimage.sh [OPCIONES]"; exit 0 ;;
*) echo " Argumento desconocido: $1" >&2; exit 1 ;;
esac
done
#===============================================================================
# HELPERS
#===============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "\n${GREEN}✅ [$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "\n${YELLOW}⚠️  [$(date '+%H:%M:%S')]${NC} $*" >&2; }
die()  { echo -e "\n${RED}❌ [$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}ℹ️  [$(date '+%H:%M:%S')]${NC} $*"; }
header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"; }
check_cmd() { command -v "$1" >/dev/null 2>&1 || die "No se encontró '$1'."; }
git_with_retry() {
local description="$1"; shift; local attempt=1
while true; do
info "🔄 $description (intento $attempt/$MAX_RETRIES)..."
if "$@"; then return 0; fi
if (( attempt >= MAX_RETRIES )); then return 1; fi
warn "⚠️  Intento $attempt falló. Reintentando en ${RETRY_DELAY}s..."
sleep "$RETRY_DELAY"; attempt=$((attempt + 1))
done
}
#===============================================================================
# DEPENDENCIAS Y HERRAMIENTAS
#===============================================================================
header "🔧 PREPARANDO HERRAMIENTAS APPIMAGE"
for cmd in python3 git wget desktop-file-validate; do check_cmd "$cmd"; done
if [[ "$SIGN" == true ]]; then check_cmd gpg; fi
if [[ "$PUBLISH" == true ]]; then check_cmd gh; fi
# Descargar appimagetool si no existe
TOOLS_DIR="$(pwd)/appimage-tools"
mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"
if [[ ! -f appimagetool-x86_64.AppImage ]]; then
log "Descargando appimagetool..."
wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage
fi
cd ..
#===============================================================================
# PREPARACIÓN & CLONADO
#===============================================================================
header "📥 PREPARANDO CÓDIGO FUENTE"
PROJECT_DIR="$(pwd)/frescobaldi-appimage"
if [[ "$CLEAN_BUILD" == true ]]; then
[[ "$KEEP_SOURCE" == true ]] && rm -rf "$PROJECT_DIR/AppDir" "$PROJECT_DIR"/*.AppImage || rm -rf "$PROJECT_DIR"
fi
if [[ ! -d "$PROJECT_DIR/.git" ]]; then
log "Clonando repositorio (rama: $BRANCH)..."
git_with_retry "git clone" git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$PROJECT_DIR" || die "No se pudo clonar."
else
cd "$PROJECT_DIR" && git fetch origin "$BRANCH" && git checkout -f "$BRANCH" && git reset --hard "origin/$BRANCH" && cd - >/dev/null
fi
#===============================================================================
# DETECCIÓN DE VERSIÓN
#===============================================================================
header "🏷️ DETECTANDO VERSIÓN"
cd "$PROJECT_DIR"
VER_GIT=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//') || VER_GIT="4.0.7"
VER=$(echo "$VER_GIT" | sed -E 's/alpha([0-9]+)/-alpha\1/; s/beta([0-9]+)/-beta\1/; s/rc([0-9]+)/-rc\1/')
log "Versión final: $VER"
cd ..
#===============================================================================
# PARCHE: CRÉDITOS EN EL DIÁLOGO ABOUT
#===============================================================================
header "🔧 APLICANDO PARCHE PERSONALIZADO"
log "Añadiendo créditos al diálogo About..."
ABOUT_FILE=$(find "$PROJECT_DIR" -name "about.py" | grep -v test | head -n 1)
if [[ -n "$ABOUT_FILE" && -f "$ABOUT_FILE" ]]; then
if ! grep -q "Custom PyQt6 / Qt 6.8.x LTS Build" "$ABOUT_FILE"; then
python3 - "$ABOUT_FILE" << 'PYTHON'
import sys, re
about_file_path = sys.argv[1]
with open(about_file_path, 'r') as f: content = f.read()
custom_credits = '''<br>
<p><b>Custom PyQt6 / Qt 6.8.x LTS Build</b><br>
Compiled by Manuel L&oacute;pez Mateos<br>
AI assistance provided by Qwen (Alibaba Group).<br>
<a href="https://github.com/mlmateos/frescobaldi-qt6-builds">https://github.com/mlmateos/frescobaldi-qt6-builds</a></p>'''
new_content = re.sub(r'(</div></body>)', custom_credits + r'\n\1', content)
if new_content != content:
with open(about_file_path, 'w') as f: f.write(new_content)
print("✅ About dialog patched successfully.")
PYTHON
log "✅ Créditos añadidos"
else
log "ℹ️  Créditos ya presentes"
fi
else
warn "⚠️ No se encontró about.py"
fi
#===============================================================================
# PARCHE: ACTUALIZAR PESTAÑA "VERSION"
#===============================================================================
header "🔧 ACTUALIZANDO PESTAÑA VERSION"
log "Parcheando información de versión..."
ABOUT_FILE=$(find "$PROJECT_DIR" -name "about.py" | grep -v test | head -n 1)
if [[ -n "$ABOUT_FILE" && -f "$ABOUT_FILE" ]]; then
python3 - "$ABOUT_FILE" << 'PYTHON'
import sys, re
about_file_path = sys.argv[1]
with open(about_file_path, 'r') as f:
content = f.read()
old_version_class = r'''class Version\(QTextBrowser\):
"""Version information\."""
def __init__\(self, parent=None\):
super\(\).__init__\(parent\)
self\.setPlainText\(debuginfo\.version_info_string\(\)\)'''
new_version_class = '''class Version(QTextBrowser):
"""Version information."""
def __init__(self, parent=None):
super().__init__(parent)
custom_version_info = """Frescobaldi: 4.0.7
Extension API: 0.9.0
Python: 3.13
python-ly: 0.9.10
Qt: 6.8.x LTS
PyQt: 6.8.x LTS
qpageview: 1.0.5
OS: Linux
Installation kind: Custom build from https://github.com/mlmateos/frescobaldi-qt6-builds"""
self.setPlainText(custom_version_info)'''
new_content = re.sub(old_version_class, new_version_class, content)
if new_content != content:
with open(about_file_path, 'w') as f:
f.write(new_content)
print("✅ Version tab patched successfully.")
else:
print("⚠️ No se encontró el patrón exacto para parchear Version.")
PYTHON
log "✅ Pestaña Version actualizada"
else
warn "⚠️ No se encontró about.py"
fi
#===============================================================================
# CONSTRUCCIÓN DEL APPIMAGE AUTOCONTENIDO CON PYINSTALLER
#===============================================================================
header "🚀 CONSTRUYENDO APPIMAGE AUTOCONTENIDO CON PYINSTALLER"
# Paso 1: Definir y preparar el AppDir
APPDIR="$PROJECT_DIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
# Paso 2: Crear archivo .desktop (nombre oficial según INSTALL.md)
log "Creando archivo .desktop oficial..."
cat > "$APPDIR/org.frescobaldi.Frescobaldi.desktop" << 'DESKTOP_EOF'
[Desktop Entry]
Name=Frescobaldi
Comment=LilyPond sheet music editor
Exec=frescobaldi %F
Icon=org.frescobaldi.Frescobaldi
Type=Application
Categories=AudioVideo;Music;
MimeType=text/x-lilypond;
DESKTOP_EOF
cp "$APPDIR/org.frescobaldi.Frescobaldi.desktop" "$APPDIR/usr/share/applications/"
# Paso 3: Buscar y copiar el ícono (nombre oficial según INSTALL.md)
log "Buscando ícono oficial de Frescobaldi..."
ICON_PATH=$(find "$PROJECT_DIR" -type f \( -name "org.frescobaldi.Frescobaldi.svg" -o -name "org.frescobaldi.Frescobaldi.png" -o -name "frescobaldi.png" -o -name "frescobaldi.svg" \) 2>/dev/null | head -n 1) || true
if [[ -n "$ICON_PATH" ]] && [[ -f "$ICON_PATH" ]]; then
log "✅ Ícono encontrado: $ICON_PATH"
cp "$ICON_PATH" "$APPDIR/org.frescobaldi.Frescobaldi.svg"
cp "$ICON_PATH" "$APPDIR/usr/share/icons/hicolor/256x256/apps/org.frescobaldi.Frescobaldi.svg"
else
log "️  Ícono no encontrado en el código fuente, descargando desde GitHub..."
wget -q "https://raw.githubusercontent.com/frescobaldi/frescobaldi/v4.0.7/frescobaldi_app/icons/org.frescobaldi.Frescobaldi.svg" -O "$APPDIR/org.frescobaldi.Frescobaldi.svg" 2>/dev/null || true
if [[ -f "$APPDIR/org.frescobaldi.Frescobaldi.svg" ]]; then
cp "$APPDIR/org.frescobaldi.Frescobaldi.svg" "$APPDIR/usr/share/icons/hicolor/256x256/apps/org.frescobaldi.Frescobaldi.svg"
log "✅ Ícono oficial descargado"
else
wget -q "https://raw.githubusercontent.com/frescobaldi/frescobaldi/v4.0.7/frescobaldi_app/icons/frescobaldi.svg" -O "$APPDIR/org.frescobaldi.Frescobaldi.svg" 2>/dev/null || true
if [[ -f "$APPDIR/org.frescobaldi.Frescobaldi.svg" ]]; then
cp "$APPDIR/org.frescobaldi.Frescobaldi.svg" "$APPDIR/usr/share/icons/hicolor/256x256/apps/org.frescobaldi.Frescobaldi.svg"
log "✅ Ícono alternativo descargado"
else
python3 -c "
import struct, zlib
def create_png(filename, width=256, height=256, color=(0, 120, 215)):
def chunk(chunk_type, data):
c = chunk_type + data
return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
with open(filename, 'wb') as
