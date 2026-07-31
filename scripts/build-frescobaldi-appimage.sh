#!/usr/bin/env bash
#===============================================================================
# build-frescobaldi-appimage.sh (v1.0-Definitiva)
# Genera AppImage de Frescobaldi usando linuxdeploy + appimagetool
# Compatible con Debian Trixie (evita appimage-builder)
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
        *) echo "❌ Argumento desconocido: $1" >&2; exit 1 ;;
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

# Descargar linuxdeploy y appimagetool si no existen
TOOLS_DIR="$(pwd)/appimage-tools"
mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"

if [[ ! -f linuxdeploy-x86_64.AppImage ]]; then
    log "Descargando linuxdeploy..."
    wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
    chmod +x linuxdeploy-x86_64.AppImage
fi
if [[ ! -f appimagetool-x86_64.AppImage ]]; then
    log "Descargando appimagetool..."
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool-x86_64.AppImage
fi
cd ..

#===============================================================================
# PREPARACIÓN & CLONADO
#===============================================================================
header " PREPARANDO CÓDIGO FUENTE"
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
        log "️  Créditos ya presentes"
    fi
else
    warn "⚠️ No se encontró about.py"
fi

#===============================================================================
# CONSTRUCCIÓN DEL APPIMAGE AUTOCONTENIDO CON PYTHON-APPIMAGE
#===============================================================================
header "🚀 CONSTRUYENDO APPIMAGE AUTOCONTENIDO"

# Instalar python-appimage si no existe
if ! command -v python-appimage >/dev/null 2>&1; then
    log "Instalando python-appimage..."
    python3 -m pip install --break-system-packages python-appimage || die "No se pudo instalar python-appimage"
fi

cd "$PROJECT_DIR"

# Crear requirements.txt con todas las dependencias necesarias
log "Creando requirements.txt para el entorno autocontenido..."
cat > requirements.txt << 'REQEOF'
PyQt6>=6.4.0
PyQt6-Qt6>=6.4.0
PyQt6-sip>=13.0.0
qpageview>=1.0.0
python-ly>=0.9.0
REQEOF

# Asegurarnos de que los metadatos estén en el directorio actual para python-appimage
cp "$APPDIR/frescobaldi.desktop" .
cp "$APPDIR/frescobaldi.png" .

# Generar el AppImage autocontenido
# python-appimage se encarga de descargar Python 3.13 y las dependencias automáticamente
log "Generando AppImage autocontenido (esto puede tardar unos minutos)..."
python-appimage build app \
    --python-version 3.13 \
    --entry-point frescobaldi.__main__:main \
    --executable-name frescobaldi \
    --requirements requirements.txt \
    --desktop-file frescobaldi.desktop \
    --icon frescobaldi.png \
    || die "python-appimage build falló"

cd ..

# Buscar el AppImage generado (python-appimage lo deja en el directorio actual)
APPIMAGE_FILE=$(ls "$PROJECT_DIR"/Frescobaldi-*.AppImage 2>/dev/null | head -n1)
[[ -z "$APPIMAGE_FILE" ]] && die "No se generó el AppImage"

APPIMAGE_FINAL="frescobaldi-${VER}-qt6-x86_64.AppImage"
mv -f "$APPIMAGE_FILE" "$APPIMAGE_FINAL"
sha256sum "$APPIMAGE_FINAL" > SHA256SUMS-APPIMAGE.txt

if [[ "$SIGN" == true ]]; then
    header " FIRMANDO CON GPG"
    [[ -z "$GPG_KEY" ]] && GPG_KEY=$(gpg --list-secret-keys --keyid-format long | grep "^sec" | head -n1 | awk '{print $2}' | cut -d'/' -f2)
    gpg --default-key "$GPG_KEY" --yes --detach-sign --armor "$APPIMAGE_FINAL"
    log "✅ Firma generada: ${APPIMAGE_FINAL}.asc"
fi

#===============================================================================
# PUBLICACIÓN EN GITHUB
#===============================================================================
if [[ "$PUBLISH" == true ]]; then
    header "🌐 PUBLICANDO EN GITHUB RELEASES"
    gh auth status >/dev/null 2>&1 || die "No autenticado en GitHub CLI"
    FULL_REPO="${GITHUB_USER}/${REPO_NAME}"
    UPLOAD_FILES=("$APPIMAGE_FINAL" "SHA256SUMS-APPIMAGE.txt")
    [[ -f "${APPIMAGE_FINAL}.asc" ]] && UPLOAD_FILES+=("${APPIMAGE_FINAL}.asc")
    
    if gh release view "v${VER}" --repo "$FULL_REPO" >/dev/null 2>&1; then
        gh release upload "v${VER}" --clobber --repo "$FULL_REPO" "${UPLOAD_FILES[@]}"
        log "✅ AppImage AÑADIDO a la release existente"
    else
        log "ℹ️  La release v${VER} no existe, créala primero con el script .deb"
    fi
fi

#===============================================================================
# RESULTADO FINAL
#===============================================================================
header "🎉 RESULTADO FINAL"
if [[ -f "$APPIMAGE_FINAL" ]]; then
    log "¡ÉXITO! AppImage autocontenido listo:"
    echo "    $(basename "$APPIMAGE_FINAL")"
    echo "   📍 $(pwd)/$APPIMAGE_FINAL"
    echo "   🔧 Tamaño: $(du -h "$APPIMAGE_FINAL" | cut -f1)"
    echo "   🐍 Incluye: Python 3.13, PyQt6, qpageview, python-ly"
    [[ -f "${APPIMAGE_FINAL}.asc" ]] && echo "   🔐 Firma: $(basename "${APPIMAGE_FINAL}.asc")"
    echo ""
    echo "▶  Para ejecutar:"
    echo "   chmod +x $APPIMAGE_FINAL && ./$APPIMAGE_FINAL"
else
    die "No se generó el AppImage correctamente"
fi
log "✅ Proceso completado."
