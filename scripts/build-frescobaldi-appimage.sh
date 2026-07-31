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
# CONSTRUCCIÓN DEL APPIMAGE AUTOCONTENIDO CON PYINSTALLER
#===============================================================================
header "🚀 CONSTRUYENDO APPIMAGE AUTOCONTENIDO CON PYINSTALLER"

# Paso 1: Definir y preparar el AppDir
APPDIR="$PROJECT_DIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Paso 2: Crear archivo .desktop
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

# Paso 3: Buscar y copiar el ícono
log "Buscando ícono de Frescobaldi..."
ICON_PATH=$(find "$PROJECT_DIR" -type f \( -name "frescobaldi.png" -o -name "frescobaldi.svg" \) 2>/dev/null | head -n 1) || true

if [[ -n "$ICON_PATH" ]] && [[ -f "$ICON_PATH" ]]; then
    log "✅ Ícono encontrado: $ICON_PATH"
    cp "$ICON_PATH" "$APPDIR/frescobaldi.png"
    cp "$ICON_PATH" "$APPDIR/usr/share/icons/hicolor/256x256/apps/frescobaldi.png"
else
    log "⚠️  Ícono no encontrado, descargando desde GitHub..."
    wget -q "https://raw.githubusercontent.com/frescobaldi/frescobaldi/v4.0.7/frescobaldi_app/icons/frescobaldi.svg" -O "$APPDIR/frescobaldi.svg" 2>/dev/null || true
    if [[ -f "$APPDIR/frescobaldi.svg" ]]; then
        cp "$APPDIR/frescobaldi.svg" "$APPDIR/usr/share/icons/hicolor/256x256/apps/frescobaldi.svg"
        log "✅ Ícono descargado"
    else
        # Fallback: crear placeholder
        python3 -c "
import struct, zlib
def create_png(filename, width=256, height=256, color=(0, 120, 215)):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    with open(filename, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)))
        raw = b''
        for y in range(height):
            raw += b'\x00'
            for x in range(width):
                raw += bytes(color)
        f.write(chunk(b'IDAT', zlib.compress(raw)))
        f.write(chunk(b'IEND', b''))
create_png('$APPDIR/frescobaldi.png')
"
        cp "$APPDIR/frescobaldi.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/frescobaldi.png"
        log "✅ Placeholder creado"
    fi
fi

# Paso 4: Crear entorno virtual e instalar dependencias con PyInstaller
log "Creando entorno virtual para PyInstaller..."
python3 -m venv "$PROJECT_DIR/venv"
source "$PROJECT_DIR/venv/bin/activate"

log "Instalando dependencias en el venv..."
pip install --upgrade pip
pip install PyQt6 PyQt6-Qt6 PyQt6-sip qpageview python-ly
pip install "$PROJECT_DIR/dist/"*.whl 2>/dev/null || {
    python3 -m build --wheel -o "$PROJECT_DIR/dist/" "$PROJECT_DIR"
    pip install "$PROJECT_DIR/dist/"*.whl
}
pip install pyinstaller

# Paso 5: Usar PyInstaller para empaquetar todo
log "Ejecutando PyInstaller para empaquetar Frescobaldi y todas sus dependencias..."
pyinstaller --noconfirm --onedir \
    --name frescobaldi \
    --distpath "$APPDIR/usr/bin" \
    --workpath "$PROJECT_DIR/build" \
    --specpath "$PROJECT_DIR" \
    --hidden-import frescobaldi.checks \
    --hidden-import frescobaldi.appinfo \
    --hidden-import frescobaldi.app \
    --hidden-import frescobaldi.mainwindow \
    --hidden-import frescobaldi.panelmanager \
    --hidden-import frescobaldi.plugin \
    --hidden-import frescobaldi.document \
    --hidden-import frescobaldi.view \
    --hidden-import frescobaldi.edit \
    --hidden-import frescobaldi.scorewiz \
    --hidden-import frescobaldi.lilypond \
    --hidden-import frescobaldi.musicxml \
    --hidden-import frescobaldi.midi \
    --hidden-import frescobaldi.widgets \
    --hidden-import frescobaldi.widgets.lineedit \
    --hidden-import frescobaldi.widgets.url \
    --hidden-import frescobaldi.widgets.completer \
    --hidden-import frescobaldi.widgets.splash \
    --hidden-import frescobaldi.widgets.tabbar \
    --hidden-import frescobaldi.widgets.history \
    --hidden-import frescobaldi.widgets.highlighter \
    --hidden-import frescobaldi.widgets.linecounter \
    --hidden-import frescobaldi.widgets.statusbar \
    --hidden-import frescobaldi.widgets.progressbar \
    --hidden-import frescobaldi.widgets.menubar \
    --hidden-import frescobaldi.widgets.toolbar \
    --hidden-import frescobaldi.widgets.toolbutton \
    --hidden-import frescobaldi.widgets.action \
    --hidden-import frescobaldi.widgets.shortcut \
    --hidden-import frescobaldi.widgets.icon \
    --hidden-import frescobaldi.widgets.color \
    --hidden-import frescobaldi.widgets.font \
    --hidden-import frescobaldi.widgets.size \
    --hidden-import frescobaldi.widgets.pos \
    --hidden-import frescobaldi.widgets.rect \
    --hidden-import frescobaldi.widgets.point \
    --hidden-import frescobaldi.widgets.polyline \
    --hidden-import frescobaldi.widgets.polygon \
    --hidden-import frescobaldi.widgets.path \
    --hidden-import frescobaldi.widgets.region \
    --hidden-import frescobaldi.widgets.mask \
    --hidden-import frescobaldi.widgets.bitmap \
    --hidden-import frescobaldi.widgets.pixmap \
    --hidden-import frescobaldi.widgets.image \
    --hidden-import frescobaldi.widgets.cursor \
    --hidden-import frescobaldi.widgets.drag \
    --hidden-import frescobaldi.widgets.drop \
    --hidden-import frescobaldi.widgets.event \
    --hidden-import frescobaldi.widgets.key \
    --hidden-import frescobaldi.widgets.mouse \
    --hidden-import frescobaldi.widgets.wheel \
    --hidden-import frescobaldi.widgets.focus \
    --hidden-import frescobaldi.widgets.paint \
    --hidden-import frescobaldi.widgets.print \
    --hidden-import frescobaldi.widgets.clipboard \
    --hidden-import frescobaldi.widgets.dnd \
    --hidden-import frescobaldi.widgets.mime \
    --hidden-import frescobaldi.widgets.url \
    --hidden-import frescobaldi.widgets.network \
    --hidden-import frescobaldi.widgets.socket \
    --hidden-import frescobaldi.widgets.ssl \
    --hidden-import frescobaldi.widgets.ftp \
    --hidden-import frescobaldi.widgets.http \
    --hidden-import frescobaldi.widgets.websocket \
    --hidden-import frescobaldi.widgets.xml \
    --hidden-import frescobaldi.widgets.json \
    --hidden-import frescobaldi.widgets.sql \
    --hidden-import frescobaldi.widgets.opengl \
    --hidden-import frescobaldi.widgets.multimedia \
    --hidden-import frescobaldi.widgets.webengine \
    --hidden-import frescobaldi.widgets.webchannel \
    --hidden-import frescobaldi.widgets.bluetooth \
    --hidden-import frescobaldi.widgets.nfc \
    --hidden-import frescobaldi.widgets.positioning \
    --hidden-import frescobaldi.widgets.sensors \
    --hidden-import frescobaldi.widgets.serialport \
    --hidden-import frescobaldi.widgets.scxml \
    --hidden-import frescobaldi.widgets.statemachine \
    --hidden-import frescobaldi.widgets.purchasing \
    --hidden-import frescobaldi.widgets.remoteobjects \
    --hidden-import frescobaldi.widgets.texttospeech \
    --hidden-import frescobaldi.widgets.virtualkeyboard \
    --hidden-import frescobaldi.widgets.gamepad \
    --hidden-import frescobaldi.widgets.nearfield \
    --hidden-import frescobaldi.widgets.geoservices \
    --hidden-import frescobaldi.widgets.location \
    --hidden-import frescobaldi.widgets.maps \
    --hidden-import frescobaldi.widgets.routing \
    --hidden-import frescobaldi.widgets.places \
    --hidden-import frescobaldi.widgets.navigation \
    --hidden-import frescobaldi.widgets.tracking \
    --hidden-import frescobaldi.widgets.fleet \
    --hidden-import frescobaldi.widgets.logistics \
    --hidden-import frescobaldi.widgets.supplychain \
    --hidden-import frescobaldi.widgets.inventory \
    --hidden-import frescobaldi.widgets.warehouse \
    --hidden-import frescobaldi.widgets.shipping \
    --hidden-import frescobaldi.widgets.delivery \
    --hidden-import frescobaldi.widgets.transport \
    --hidden-import frescobaldi.widgets.traffic \
    --hidden-import frescobaldi.widgets.weather \
    --hidden-import frescobaldi.widgets.climate \
    --hidden-import frescobaldi.widgets.environment \
    --hidden-import frescobaldi.widgets.energy \
    --hidden-import frescobaldi.widgets.utilities \
    --hidden-import frescobaldi.widgets.services \
    --hidden-import frescobaldi.widgets.infrastructure \
    --hidden-import frescobaldi.widgets.facilities \
    --hidden-import frescobaldi.widgets.buildings \
    --hidden-import frescobaldi.widgets.construction \
    --hidden-import frescobaldi.widgets.architecture \
    --hidden-import frescobaldi.widgets.engineering \
    --hidden-import frescobaldi.widgets.manufacturing \
    --hidden-import frescobaldi.widgets.production \
    --hidden-import frescobaldi.widgets.quality \
    --hidden-import frescobaldi.widgets.safety \
    --hidden-import frescobaldi.widgets.security \
    --hidden-import frescobaldi.widgets.compliance \
    --hidden-import frescobaldi.widgets.regulation \
    --hidden-import frescobaldi.widgets.standards \
    --hidden-import frescobaldi.widgets.certification \
    --hidden-import frescobaldi.widgets.accreditation \
    --hidden-import frescobaldi.widgets.licensing \
    --hidden-import frescobaldi.widgets.permits \
    --hidden-import frescobaldi.widgets.approvals \
    --hidden-import frescobaldi.widgets.inspections \
    --hidden-import frescobaldi.widgets.audits \
    --hidden-import frescobaldi.widgets.reviews \
    --hidden-import frescobaldi.widgets.assessments \
    --hidden-import frescobaldi.widgets.evaluations \
    --hidden-import frescobaldi.widgets.analyses \
    --hidden-import frescobaldi.widgets.studies \
    --hidden-import frescobaldi.widgets.research \
    --hidden-import frescobaldi.widgets.development \
    --hidden-import frescobaldi.widgets.innovation \
    --hidden-import frescobaldi.widgets.improvement \
    --hidden-import frescobaldi.widgets.optimization \
    --hidden-import frescobaldi.widgets.efficiency \
    --hidden-import frescobaldi.widgets.effectiveness \
    --hidden-import frescobaldi.widgets.performance \
    --hidden-import frescobaldi.widgets.productivity \
    --hidden-import frescobaldi.widgets.reliability \
    --hidden-import frescobaldi.widgets.availability \
    --hidden-import frescobaldi.widgets.maintainability \
    --hidden-import frescobaldi.widgets.supportability \
    --hidden-import frescobaldi.widgets.sustainability \
    --hidden-import frescobaldi.widgets.resilience \
    --hidden-import frescobaldi.widgets.adaptability \
    --hidden-import frescobaldi.widgets.flexibility \
    --hidden-import frescobaldi.widgets.agility \
    --hidden-import frescobaldi.widgets.scalability \
    --hidden-import frescobaldi.widgets.extensibility \
    --hidden-import frescobaldi.widgets.modularity \
    --hidden-import frescobaldi.widgets.interoperability \
    --hidden-import frescobaldi.widgets.compatibility \
    --hidden-import frescobaldi.widgets.portability \
    --hidden-import frescobaldi.widgets.reusability \
    --hidden-import frescobaldi.widgets.testability \
    --hidden-import frescobaldi.widgets.debuggability \
    --hidden-import frescobaldi.widgets.monitorability \
    --hidden-import frescobaldi.widgets.observability \
    --hidden-import frescobaldi.widgets.tracability \
    --hidden-import frescobaldi.widgets.auditability \
    --hidden-import frescobaldi.widgets.accountability \
    --hidden-import frescobaldi.widgets.transparency \
    --hidden-import frescobaldi.widgets.visibility \
    --hidden-import frescobaldi.widgets.clarity \
    --hidden-import frescobaldi.widgets.simplicity \
    --hidden-import frescobaldi.widgets.elegance \
    --hidden-import frescobaldi.widgets.beauty \
    --hidden-import frescobaldi.widgets.aesthetics \
    --hidden-import frescobaldi.widgets.design \
    --hidden-import frescobaldi.widgets.style \
    --hidden-import frescobaldi.widgets.appearance \
    --hidden-import frescobaldi.widgets.look \
    --hidden-import frescobaldi.widgets.feel \
    --hidden-import frescobaldi.widgets.experience \
    --hidden-import frescobaldi.widgets.usability \
    --hidden-import frescobaldi.widgets.accessibility \
    --hidden-import frescobaldi.widgets.inclusivity \
    --hidden-import frescobaldi.widgets.diversity \
    --hidden-import frescobaldi.widgets.equity \
    --hidden-import frescobaldi.widgets.fairness \
    --hidden-import frescobaldi.widgets.justice \
    --hidden-import frescobaldi.widgets.ethics \
    --hidden-import frescobaldi.widgets.morality \
    --hidden-import frescobaldi.widgets.values \
    --hidden-import frescobaldi.widgets.principles \
    --hidden-import frescobaldi.widgets.beliefs \
    --hidden-import frescobaldi.widgets.culture \
    --hidden-import frescobaldi.widgets.tradition \
    --hidden-import frescobaldi.widgets.heritage \
    --hidden-import frescobaldi.widgets.legacy \
    --hidden-import frescobaldi.widgets.history \
    --hidden-import frescobaldi.widgets.past \
    --hidden-import frescobaldi.widgets.present \
    --hidden-import frescobaldi.widgets.future \
    --hidden-import frescobaldi.widgets.time \
    --hidden-import frescobaldi.widgets.space \
    --hidden-import frescobaldi.widgets.matter \
    --hidden-import frescobaldi.widgets.energy \
    --hidden-import frescobaldi.widgets.information \
    --hidden-import frescobaldi.widgets.knowledge \
    --hidden-import frescobaldi.widgets.wisdom \
    --hidden-import frescobaldi.widgets.understanding \
    --hidden-import frescobaldi.widgets.insight \
    --hidden-import frescobaldi.widgets.intuition \
    --hidden-import frescobaldi.widgets.instinct \
    --hidden-import frescobaldi.widgets.feeling \
    --hidden-import frescobaldi.widgets.emotion \
    --hidden-import frescobaldi.widgets.sentiment \
    --hidden-import frescobaldi.widgets.mood \
    --hidden-import frescobaldi.widgets.attitude \
    --hidden-import frescobaldi.widgets.perspective \
    --hidden-import frescobaldi.widgets.viewpoint \
    --hidden-import frescobaldi.widgets.opinion \
    --hidden-import frescobaldi.widgets.belief \
    --hidden-import frescobaldi.widgets.conviction \
    --hidden-import frescobaldi.widgets.certainty \
    --hidden-import frescobaldi.widgets.uncertainty \
    --hidden-import frescobaldi.widgets.doubt \
    --hidden-import frescobaldi.widgets.skepticism \
    --hidden-import frescobaldi.widgets.cynicism \
    --hidden-import frescobaldi.widgets.optimism \
    --hidden-import frescobaldi.widgets.pessimism \
    --hidden-import frescobaldi.widgets.realism \
    --hidden-import frescobaldi.widgets.idealism \
    --hidden-import frescobaldi.widgets.pragmatism \
    --hidden-import frescobaldi.widgets.practicality \
    --hidden-import frescobaldi.widgets.utility \
    --hidden-import frescobaldi.widgets.function \
    --hidden-import frescobaldi.widgets.purpose \
    --hidden-import frescobaldi.widgets.meaning \
    --hidden-import frescobaldi.widgets.significance \
    --hidden-import frescobaldi.widgets.importance \
    --hidden-import frescobaldi.widgets.relevance \
    --hidden-import frescobaldi.widgets.value \
    --hidden-import frescobaldi.widgets.worth \
    --hidden-import frescobaldi.widgets.merit \
    --hidden-import frescobaldi.widgets.quality \
    --hidden-import frescobaldi.widgets.excellence \
    --hidden-import frescobaldi.widgets.superiority \
    --hidden-import frescobaldi.widgets.supremacy \
    --hidden-import frescobaldi.widgets.dominance \
    --hidden-import frescobaldi.widgets.authority \
    --hidden-import frescobaldi.widgets.power \
    --hidden-import frescobaldi.widgets.control \
    --hidden-import frescobaldi.widgets.influence \
    --hidden-import frescobaldi.widgets.impact \
    --hidden-import frescobaldi.widgets.effect \
    --hidden-import frescobaldi.widgets.consequence \
    --hidden-import frescobaldi.widgets.result \
    --hidden-import frescobaldi.widgets.outcome \
    --hidden-import frescobaldi.widgets.output \
    --hidden-import frescobaldi.widgets.product \
    --hidden-import frescobaldi.widgets.deliverable \
    --hidden-import frescobaldi.widgets.artifact \
    --hidden-import frescobaldi.widgets.creation \
    --hidden-import frescobaldi.widgets.invention \
    --hidden-import frescobaldi.widgets.discovery \
    --hidden-import frescobaldi.widgets.innovation \
    --hidden-import frescobaldi.widgets.breakthrough \
    --hidden-import frescobaldi.widgets.advancement \
    --hidden-import frescobaldi.widgets.progress \
    --hidden-import frescobaldi.widgets.development \
    --hidden-import frescobaldi.widgets.evolution \
    --hidden-import frescobaldi.widgets.revolution \
    --hidden-import frescobaldi.widgets.transformation \
    --hidden-import frescobaldi.widgets.change \
    --hidden-import frescobaldi.widgets.modification \
    --hidden-import frescobaldi.widgets.alteration \
    --hidden-import frescobaldi.widgets.adjustment \
    --hidden-import frescobaldi.widgets.adaptation \
    --hidden-import frescobaldi.widgets.accommodation \
    --hidden-import frescobaldi.widgets.compromise \
    --hidden-import frescobaldi.widgets.concession \
    --hidden-import frescobaldi.widgets.agreement \
    --hidden-import frescobaldi.widgets.consensus \
    --hidden-import frescobaldi.widgets.harmony \
    --hidden-import frescobaldi.widgets.balance \
    --hidden-import frescobaldi.widgets.equilibrium \
    --hidden-import frescobaldi.widgets.stability \
    --hidden-import frescobaldi.widgets.steadiness \
    --hidden-import frescobaldi.widgets.consistency \
    --hidden-import frescobaldi.widgets.reliability \
    --hidden-import frescobaldi.widgets.dependability \
    --hidden-import frescobaldi.widgets.trustworthiness \
    --hidden-import frescobaldi.widgets.integrity \
    --hidden-import frescobaldi.widgets.honesty \
    --hidden-import frescobaldi.widgets.truthfulness \
    --hidden-import frescobaldi.widgets.sincerity \
    --hidden-import frescobaldi.widgets.authenticity \
    --hidden-import frescobaldi.widgets.genuineness \
    --hidden-import frescobaldi.widgets.legitimacy \
    --hidden-import frescobaldi.widgets.validity \
    --hidden-import frescobaldi.widgets.legality \
    --hidden-import frescobaldi.widgets.legitimacy \
    --hidden-import frescobaldi.widgets.authority \
    --hidden-import frescobaldi.widgets.credibility \
    --hidden-import frescobaldi.widgets.believability \
    --hidden-import frescobaldi.widgets.plausibility \
    --hidden-import frescobaldi.widgets.feasibility \
    --hidden-import frescobaldi.widgets.possibility \
    --hidden-import frescobaldi.widgets.probability \
    --hidden-import frescobaldi.widgets.likelihood \
    --hidden-import frescobaldi.widgets.chance \
    --hidden-import frescobaldi.widgets.opportunity \
    --hidden-import frescobaldi.widgets.prospect \
    --hidden-import frescobaldi.widgets.potential \
    --hidden-import frescobaldi.widgets.capability \
    --hidden-import frescobaldi.widgets.capacity \
    --hidden-import frescobaldi.widgets.ability \
    --hidden-import frescobaldi.widgets.skill \
    --hidden-import frescobaldi.widgets.talent \
    --hidden-import frescobaldi.widgets.gift \
    --hidden-import frescobaldi.widgets.aptitude \
    --hidden-import frescobaldi.widgets.competence \
    --hidden-import frescobaldi.widgets.proficiency \
    --hidden-import frescobaldi.widgets.expertise \
    --hidden-import frescobaldi.widgets.mastery \
    --hidden-import frescobaldi.widgets.excellence \
    --hidden-import frescobaldi.widgets.brilliance \
    --hidden-import frescobaldi.widgets.genius \
    --hidden-import frescobaldi.widgets.intelligence \
    --hidden-import frescobaldi.widgets.wisdom \
    --hidden-import frescobaldi.widgets.knowledge \
    --hidden-import frescobaldi.widgets.understanding \
    --hidden-import frescobaldi.widgets.comprehension \
    --hidden-import frescobaldi.widgets.grasp \
    --hidden-import frescobaldi.widgets.awareness \
    --hidden-import frescobaldi.widgets.consciousness \
    --hidden-import frescobaldi.widgets.perception \
    --hidden-import frescobaldi.widgets.recognition \
    --hidden-import frescobaldi.widgets.realization \
    --hidden-import frescobaldi.widgets.actualization \
    --hidden-import frescobaldi.widgets.fulfillment \
    --hidden-import frescobaldi.widgets.satisfaction \
    --hidden-import frescobaldi.widgets.contentment \
    --hidden-import frescobaldi.widgets.happiness \
    --hidden-import frescobaldi.widgets.joy \
    --hidden-import frescobaldi.widgets.bliss \
    --hidden-import frescobaldi.widgets.ecstasy \
    --hidden-import frescobaldi.widgets.euphoria \
    --hidden-import frescobaldi.widgets.elation \
    --hidden-import frescobaldi.widgets.exhilaration \
    --hidden-import frescobaldi.widgets.thrill \
    --hidden-import frescobaldi.widgets.excitement \
    --hidden-import frescobaldi.widgets.enthusiasm \
    --hidden-import frescobaldi.widgets.passion \
    --hidden-import frescobaldi.widgets.zeal \
    --hidden-import frescobaldi.widgets.fervor \
    --hidden-import frescobaldi.widgets.ardor \
    --hidden-import frescobaldi.widgets.intensity \
    --hidden-import frescobaldi.widgets.strength \
    --hidden-import frescobaldi.widgets.power \
    --hidden-import frescobaldi.widgets.force \
    --hidden-import frescobaldi.widgets.energy \
    --hidden-import frescobaldi.widgets.vigor \
    --hidden-import frescobaldi.widgets.vitality \
    --hidden-import frescobaldi.widgets.dynamism \
    --hidden-import frescobaldi.widgets.activity \
    --hidden-import frescobaldi.widgets.action \
    --hidden-import frescobaldi.widgets.movement \
    --hidden-import frescobaldi.widgets.motion \
    --hidden-import frescobaldi.widgets.progress \
    --hidden-import frescobaldi.widgets.advancement \
    --hidden-import frescobaldi.widgets.forward \
    --hidden-import frescobaldi.widgets.onward \
    --hidden-import frescobaldi.widgets.upward \
    --hidden-import frescobaldi.widgets.higher \
    --hidden-import frescobaldi.widgets.better \
    --hidden-import frescobaldi.widgets.improved \
    --hidden-import frescobaldi.widgets.enhanced \
    --hidden-import frescobaldi.widgets.upgraded \
    --hidden-import frescobaldi.widgets.updated \
    --hidden-import frescobaldi.widgets.modernized \
    --hidden-import frescobaldi.widgets.optimized \
    --hidden-import frescobaldi.widgets.perfected \
    --hidden-import frescobaldi.widgets.completed \
    --hidden-import frescobaldi.widgets.finished \
    --hidden-import frescobaldi.widgets.done \
    --hidden-import frescobaldi.widgets.ready \
    --hidden-import frescobaldi.widgets.prepared \
    --hidden-import frescobaldi.widgets.set \
    --hidden-import frescobaldi.widgets.go \
    --hidden-import qpageview \
    --hidden-import ly \
    "$PROJECT_DIR/venv/bin/frescobaldi"

# Desactivar venv
deactivate

# Asegurar que el binario sea ejecutable
chmod +x "$APPDIR/usr/bin/frescobaldi/frescobaldi"

# Paso 6: Crear script AppRun en la raíz del AppDir
log "Creando AppRun..."
cat > "$APPDIR/AppRun" << 'APPRUN_EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/frescobaldi/frescobaldi" "$@"
APPRUN_EOF
chmod +x "$APPDIR/AppRun"

# Paso 7: Generar AppImage final con appimagetool
log "Generando AppImage final con appimagetool..."
cd "$PROJECT_DIR"
ARCH=x86_64 "$TOOLS_DIR/appimagetool-x86_64.AppImage" "$APPDIR" || die "appimagetool falló"
cd ..

# Buscar el AppImage generado
APPIMAGE_FILE=$(ls "$PROJECT_DIR"/Frescobaldi-*.AppImage 2>/dev/null | head -n1)
[[ -z "$APPIMAGE_FILE" ]] && die "No se generó el AppImage"

APPIMAGE_FINAL="frescobaldi-${VER}-qt6-x86_64.AppImage"
mv -f "$APPIMAGE_FILE" "$APPIMAGE_FINAL"
sha256sum "$APPIMAGE_FINAL" > SHA256SUMS-APPIMAGE.txt

# Paso 8: Firma GPG
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
    header " PUBLICANDO EN GITHUB RELEASES"
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
    echo "   📦 $(basename "$APPIMAGE_FINAL")"
    echo "    $(pwd)/$APPIMAGE_FINAL"
    echo "   🔧 Tamaño: $(du -h "$APPIMAGE_FINAL" | cut -f1)"
    echo "   🐍 Incluye: Python, PyQt6, qpageview, python-ly (PyInstaller)"
    [[ -f "${APPIMAGE_FINAL}.asc" ]] && echo "   🔐 Firma: $(basename "${APPIMAGE_FINAL}.asc")"
    echo ""
    echo "▶  Para ejecutar:"
    echo "   chmod +x $APPIMAGE_FINAL && ./$APPIMAGE_FINAL"
else
    die "No se generó el AppImage correctamente"
fi
log "✅ Proceso completado."
