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
# CONSTRUCCIÓN DEL APPDIR
#===============================================================================
header "📦 CONSTRUYENDO APPDIR"
APPDIR="$PROJECT_DIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib/python3/dist-packages" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# 1. Instalar Frescobaldi, qpageview y python-ly desde PyPI
log "Instalando paquetes Python en AppDir..."
python3 -m pip install --no-deps --target="$APPDIR/usr/lib/python3/dist-packages" "$PROJECT_DIR/dist/"*.whl 2>/dev/null || \
python3 -m build --wheel -o "$PROJECT_DIR/dist/" "$PROJECT_DIR" && \
python3 -m pip install --no-deps --target="$APPDIR/usr/lib/python3/dist-packages" "$PROJECT_DIR/dist/"*.whl

python3 -m pip install --no-deps --target="$APPDIR/usr/lib/python3/dist-packages" qpageview python-ly

# 2. Crear el ejecutable (wrapper limpio para AppImage)
cat > "$APPDIR/usr/bin/frescobaldi" << 'WRAPPER_EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export PYTHONPATH="$HERE/../lib/python3/dist-packages:$PYTHONPATH"
exec python3 -m frescobaldi "$@"
WRAPPER_EOF
chmod +x "$APPDIR/usr/bin/frescobaldi"

# 3. Crear archivo .desktop CORRECTO (categorías válidas según freedesktop.org)
log "Creando archivo .desktop..."
cat > "$APPDIR/frescobaldi.desktop" << 'DESKTOP_EOF'
[Desktop Entry]
Name=Frescobaldi
Comment=LilyPond sheet music editor
Exec=frescobaldi %F
Icon=frescobaldi
Type=Application
Categories=AudioVideo;Music;
MimeType=text/x-lilypond;
DESKTOP_EOF
cp "$APPDIR/frescobaldi.desktop" "$APPDIR/usr/share/applications/"

# Copiar icono (buscar en múltiples ubicaciones típicas)
log "Buscando ícono de Frescobaldi..."
ICON_FOUND=false

# Intentar múltiples nombres y ubicaciones comunes
for ICON_PATH in \
    "$PROJECT_DIR/frescobaldi.png" \
    "$PROJECT_DIR/frescobaldi.svg" \
    "$PROJECT_DIR/icons/frescobaldi.png" \
    "$PROJECT_DIR/icons/frescobaldi.svg" \
    "$PROJECT_DIR/frescobaldi_app/icons/frescobaldi.png" \
    "$PROJECT_DIR/frescobaldi_app/icons/frescobaldi.svg"; do
    if [[ -f "$ICON_PATH" ]]; then
        log "✅ Ícono encontrado: $ICON_PATH"
        cp "$ICON_PATH" "$APPDIR/frescobaldi.png"
        cp "$ICON_PATH" "$APPDIR/usr/share/icons/hicolor/256x256/apps/frescobaldi.png"
        ICON_FOUND=true
        break
    fi
done

# Si no se encontró, descargar desde el repositorio oficial
if [[ "$ICON_FOUND" == false ]]; then
    log "⚠️  Ícono no encontrado, descargando desde GitHub..."
    wget -q "https://raw.githubusercontent.com/frescobaldi/frescobaldi/main/frescobaldi_app/icons/frescobaldi.svg" \
        -O "$APPDIR/frescobaldi.png" || \
    wget -q "https://raw.githubusercontent.com/frescobaldi/frescobaldi/4.0.7/frescobaldi_app/icons/frescobaldi.svg" \
        -O "$APPDIR/frescobaldi.png" || \
    die "No se pudo descargar el ícono"
    cp "$APPDIR/frescobaldi.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/frescobaldi.png"
    log "✅ Ícono descargado y colocado"
fi

# 4. Optimización -OO (MANTENEMOS TODOS LOS IDIOMAS)
log "⚡ Aplicando optimización -OO..."
PKG_DIR=$(find "$APPDIR/usr/lib/python3/dist-packages" -maxdepth 1 -type d -name "frescobaldi*" | grep -v dist-info | head -n 1)
if [[ -n "$PKG_DIR" ]] && [[ -d "$PKG_DIR" ]]; then
    python3 -OO -m compileall "$PKG_DIR"
    find "$PKG_DIR" -name "*.py" -delete || true
    log "✅ Optimización completada"
fi

#===============================================================================
# EMPAQUETADO DIRECTO CON APPIMAGETOOL
#===============================================================================
header "🚀 GENERANDO APPIMAGE CON APPIMAGETOOL"

cd "$PROJECT_DIR"

# Generar AppImage directamente con ARCH explícito
log "Generando AppImage con appimagetool..."
ARCH=x86_64 "$TOOLS_DIR/appimagetool-x86_64.AppImage" AppDir || die "appimagetool falló"

cd ..

APPIMAGE_FILE=$(ls "$PROJECT_DIR"/Frescobaldi-*.AppImage 2>/dev/null | head -n1)
[[ -z "$APPIMAGE_FILE" ]] && die "No se generó el AppImage"

APPIMAGE_FINAL="frescobaldi-${VER}-qt6-x86_64.AppImage"
mv -f "$APPIMAGE_FILE" "$APPIMAGE_FINAL"
sha256sum "$APPIMAGE_FINAL" > SHA256SUMS-APPIMAGE.txt

if [[ "$SIGN" == true ]]; then
    header "🔐 FIRMANDO CON GPG"
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
header " RESULTADO FINAL"
if [[ -f "$APPIMAGE_FINAL" ]]; then
    log "¡ÉXITO! AppImage listo:"
    echo "   📦 $(basename "$APPIMAGE_FINAL")"
    echo "   📍 $(pwd)/$APPIMAGE_FINAL"
    echo "   🔧 Tamaño: $(du -h "$APPIMAGE_FINAL" | cut -f1)"
    [[ -f "${APPIMAGE_FINAL}.asc" ]] && echo "   🔐 Firma: $(basename "${APPIMAGE_FINAL}.asc")"
    echo ""
    echo "▶  Para ejecutar:"
    echo "   chmod +x $APPIMAGE_FINAL && ./$APPIMAGE_FINAL"
else
    die "No se generó el AppImage correctamente"
fi
log "✅ Proceso completado."
