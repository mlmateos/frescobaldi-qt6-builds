#!/usr/bin/env bash
#===============================================================================
# build-frescobaldi-deb.sh (v1.1-Corregido)
# Compila Frescobaldi desde fuente, genera paquete .deb (PyQt6 optimizado),
# firma y publica en GitHub Releases + Repositorio APT (ramas stable/alpha)
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
PKG_REVISION="1"
MAX_RETRIES=3
RETRY_DELAY=5
APT_REPO_URL="https://mlmateos.github.io/frescobaldi-qt6-builds"
APT_REPO_GITHUB="https://github.com/mlmateos/frescobaldi-qt6-builds"
KEEP_SOURCE=true
AUTO_CONFIRM=false

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
        --revision)       PKG_REVISION="$2"; shift 2 ;;
        --yes)            AUTO_CONFIRM=true; shift ;;
        --no-keep-source) KEEP_SOURCE=false; shift ;;
        --help|-h)
            echo "Uso: ./build-frescobaldi-deb.sh [OPCIONES]"
            echo "  --clean, --branch, --poppler, --sign, --publish, --gpg-key, --revision, --yes, --no-keep-source, --help"
            exit 0 ;;
        *) echo "❌ Argumento desconocido: $1" >&2; exit 1 ;;
    esac
done

#===============================================================================
# HELPERS
#===============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "\n${GREEN}✅ [$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "\n${YELLOW}⚠️  [$(date '+%H:%M:%S')]${NC} $*" >&2; }
die()  { echo -e "\n${RED}❌ [$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}ℹ️  [$(date '+%H:%M:%S')]${NC} $*"; }
header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"; }
check_cmd() { command -v "$1" >/dev/null 2>&1 || die "No se encontró '$1'. Instálalo primero."; }

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
# DEPENDENCIAS
#===============================================================================
header "🔧 VERIFICANDO DEPENDENCIAS"
for cmd in python3 git dpkg-buildpackage wget; do check_cmd "$cmd"; done
if [[ "$SIGN" == true ]]; then check_cmd gpg; fi
if [[ "$PUBLISH" == true ]]; then check_cmd gh; fi

#===============================================================================
# PREPARACIÓN & CLONADO
#===============================================================================
header "📥 PREPARANDO CÓDIGO FUENTE"
PROJECT_DIR="$(pwd)/frescobaldi-deb"
if [[ "$CLEAN_BUILD" == true ]]; then
    [[ "$KEEP_SOURCE" == true ]] && rm -rf "$PROJECT_DIR/debian" "$PROJECT_DIR"/*.deb || rm -rf "$PROJECT_DIR"
fi

if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    log "Clonando repositorio (rama: $BRANCH)..."
    git_with_retry "git clone" git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$PROJECT_DIR" || die "No se pudo clonar tras $MAX_RETRIES intentos."
else
    cd "$PROJECT_DIR" && git fetch origin "$BRANCH" && git checkout -f "$BRANCH" && git reset --hard "origin/$BRANCH" && cd - >/dev/null
fi
rm -rf "$PROJECT_DIR/debian"

#===============================================================================
# DETECCIÓN DE VERSIÓN
#===============================================================================
header "🏷️ DETECTANDO VERSIÓN"
cd "$PROJECT_DIR"
VER_GIT=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//') || VER_GIT="4.0.7"
VER=$(echo "$VER_GIT" | sed -E 's/alpha([0-9]+)/-alpha\1/; s/beta([0-9]+)/-beta\1/; s/rc([0-9]+)/-rc\1/')
DEB_VER=$(echo "$VER" | sed 's/-alpha/~alpha/g; s/-beta/~beta/g; s/-rc/~rc/g')
log "Versión final para .deb: ${DEB_VER}-${PKG_REVISION}"
cd ..

#===============================================================================
# PARCHE: CRÉDITOS EN EL DIÁLOGO ABOUT
#===============================================================================
header "🔧 APLICANDO PARCHE PERSONALIZADO"
log "Añadiendo créditos al diálogo About..."
ABOUT_FILE="$PROJECT_DIR/frescobaldi/about.py"

if [[ -f "$ABOUT_FILE" ]]; then
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
        log "✅ Créditos añadidos al diálogo About"
    else
        log "ℹ️  Créditos ya presentes"
    fi
else
    warn "⚠️ No se encontró $ABOUT_FILE"
fi

#===============================================================================
# COMPILACIÓN PYTHON Y OPTIMIZACIÓN
#===============================================================================
header "🔨 COMPILANDO WHEEL Y OPTIMIZANDO"
cd "$PROJECT_DIR"
python3 -m pip install --user --break-system-packages build hatchling
python3 -m build --wheel
cd ..

header "📦 GENERANDO ESTRUCTURA DEBIAN"
mkdir -p "$PROJECT_DIR/debian/source"
mkdir -p "$PROJECT_DIR/debian/frescobaldi/usr/lib/python3/dist-packages"

WHEEL_FILE=$(ls "$PROJECT_DIR/dist/"*.whl | head -n1)
TARGET_DIR="$PROJECT_DIR/debian/frescobaldi/usr/lib/python3/dist-packages"

log "Instalando wheel en el directorio de destino..."
python3 -m pip install --target="$TARGET_DIR" --no-deps "$WHEEL_FILE"

# OPTIMIZACIÓN DINÁMICA (Corrección del error de ruta)
log "✂️ Optimizando: Poda de localizaciones..."
LOCALES_TO_KEEP="es_ES|es_MX|en_US|en_GB|fr_FR"
# Buscar el directorio real del paquete (puede ser frescobaldi_app o frescobaldi)
PKG_DIR=$(find "$TARGET_DIR" -maxdepth 1 -type d -name "frescobaldi*" | grep -v dist-info | head -n 1)

if [[ -n "$PKG_DIR" && -d "$PKG_DIR" ]]; then
    log "   📂 Directorio encontrado: $PKG_DIR"
    find "$PKG_DIR/locale" -type f -name "*.mo" 2>/dev/null | grep -vE "$LOCALES_TO_KEEP" | xargs rm -f || true
    
    log "⚡ Optimizando: Bytecode Python sin docstrings (-OO)..."
    python3 -OO -m compileall "$PKG_DIR"
    find "$PKG_DIR" -name "*.py" -delete || true
else
    warn "⚠️ No se encontró el directorio del paquete Python para optimizar."
fi

# debian/control
cat <<EOF > "$PROJECT_DIR/debian/control"
Source: frescobaldi
Section: editors
Priority: optional
Maintainer: Manuel Mateos <manuel@mateos.dev>
Build-Depends: debhelper-compat (= 13), python3-build, hatchling
Standards-Version: 4.6.2
Homepage: https://www.frescobaldi.org/
Rules-Requires-Root: no

Package: frescobaldi
Architecture: all
Depends: python3, python3-pyqt6, python3-pyqt6.qtwebengine, python3-ly, python3-qpageview, $( [[ "$ENABLE_POPPLER" == true ]] && echo "poppler-utils, " )lilypond (>= 2.24)
Recommends: lilypond
Description: LilyPond sheet music text editor (Optimized PyQt6 Build)
 Frescobaldi is an advanced text editor for LilyPond music scores.
 .
 This is a custom optimized build:
 * Built for PyQt6 / Qt 6.8.x LTS
 * Locale pruning (es, en, fr only)
 * Python bytecode optimized (-OO) for smaller footprint
EOF

# debian/rules
cat << 'EOF' > "$PROJECT_DIR/debian/rules"
#!/usr/bin/make -f
export DH_VERBOSE = 1
%:
	dh $@
override_dh_auto_build:
	# Ya compilado manualmente para control total de optimización
override_dh_auto_install:
	# Ya instalado manualmente en el directorio debian/frescobaldi
override_dh_strip:
	dh_strip --no-automatic-dbgsym
EOF
chmod +x "$PROJECT_DIR/debian/rules"

# debian/changelog
FECHA=$(date -R)
cat <<EOF > "$PROJECT_DIR/debian/changelog"
frescobaldi (${DEB_VER}-${PKG_REVISION}) unstable; urgency=medium

  * Custom optimized build from upstream tag ${VER_GIT}.
  * PyQt6, locale pruning, and Python -OO bytecode optimization.

 -- Manuel Mateos <manuel@mateos.dev>  ${FECHA}
EOF
echo "3.0 (quilt)" > "$PROJECT_DIR/debian/source/format"

#===============================================================================
# EMPAQUETADO .DEB
#===============================================================================
header "📦 EMPAQUETANDO .DEB"
cd "$PROJECT_DIR"
log "Empaquetando (ignorando build-deps ya pre-compilados con la bandera -d)..."
# La bandera -d es CRUCIAL aquí para que no falle por python3-build/hatchling de apt
dpkg-buildpackage -b -us -uc -d 2>&1 | tee ../build-deb.log || die "Compilación fallida. Revisa ../build-deb.log"
cd ..

DEB_FILE=$(ls frescobaldi_${DEB_VER}-${PKG_REVISION}_*.deb 2>/dev/null | head -n1)
[[ -z "$DEB_FILE" ]] && die "No se generó el .deb"
DEB_FINAL="frescobaldi-${VER}-qt6-all.deb"
mv -f "$DEB_FILE" "$DEB_FINAL"
sha256sum "$DEB_FINAL" > SHA256SUMS-DEB
