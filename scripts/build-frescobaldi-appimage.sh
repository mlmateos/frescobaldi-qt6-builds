#!/usr/bin/env bash
#===============================================================================
# build-frescobaldi-appimage.sh (v1.0)
# Genera AppImage de Frescobaldi optimizado (PyQt6)
#===============================================================================
set -euo pipefail

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean) CLEAN_BUILD=true; shift ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --poppler) ENABLE_POPPLER=true; shift ;;
        --sign) SIGN=true; shift ;;
        --publish) PUBLISH=true; shift ;;
        --gpg-key) GPG_KEY="$2"; shift 2 ;;
        --yes) AUTO_CONFIRM=true; shift ;;
        --no-keep-source) KEEP_SOURCE=false; shift ;;
        --help|-h) echo "Uso: ./build-frescobaldi-appimage.sh [OPCIONES]"; exit 0 ;;
        *) echo "❌ Argumento desconocido: $1" >&2; exit 1 ;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "\n${GREEN}✅ [$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "\n${YELLOW}⚠️  [$(date '+%H:%M:%S')]${NC} $*" >&2; }
die()  { echo -e "\n${RED}❌ [$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}ℹ️  [$(date '+%H:%M:%S')]${NC} $*"; }
header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}\n${BLUE}  $*${NC}\n${BLUE}═══════════════════════════════════════════════════${NC}"; }
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

header "🔧 VERIFICANDO DEPENDENCIAS"
for cmd in python3 git appimage-builder; do check_cmd "$cmd"; done
if [[ "$SIGN" == true ]]; then check_cmd gpg; fi
if [[ "$PUBLISH" == true ]]; then check_cmd gh; fi

header "📥 PREPARANDO ENTORNO"
PROJECT_DIR="$(pwd)/frescobaldi-appimage"
[[ "$CLEAN_BUILD" == true ]] && rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

git clone --branch "$BRANCH" --depth 1 "$REPO_URL" src
cd src
VER_GIT=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//') || VER_GIT="4.0.7"
VER=$(echo "$VER_GIT" | sed -E 's/alpha([0-9]+)/-alpha\1/; s/beta([0-9]+)/-beta\1/; s/rc([0-9]+)/-rc\1/')
cd ..

#===============================================================================
# PARCHE: AÑADIR CRÉDITOS AL DIÁLOGO ABOUT
#===============================================================================
header "🔧 APLICANDO PARCHE PERSONALIZADO"
log "Añadiendo créditos al diálogo About..."
ABOUT_FILE="$PROJECT_DIR/src/frescobaldi/about.py"

if [[ -f "$ABOUT_FILE" ]]; then
    if ! grep -q "Custom PyQt6 / Qt 6.8.x LTS Build" "$ABOUT_FILE"; then
        python3 - "$ABOUT_FILE" << 'PYTHON'
import sys, re
about_file_path = sys.argv[1]

with open(about_file_path, 'r') as f:
    content = f.read()

custom_credits = '''<br>
<p><b>Custom PyQt6 / Qt 6.8.x LTS Build</b><br>
Compiled by Manuel L&oacute;pez Mateos<br>
AI assistance provided by Qwen (Alibaba Group).<br>
<a href="https://github.com/mlmateos/frescobaldi-qt6-builds">https://github.com/mlmateos/frescobaldi-qt6-builds</a></p>'''

new_content = re.sub(
    r'(</div></body>)',
    custom_credits + r'\n\1',
    content
)

if new_content != content:
    with open(about_file_path, 'w') as f:
        f.write(new_content)
    print("✅ About dialog patched successfully.")
else:
    print("⚠️ Could not patch About dialog.")
PYTHON
        log "✅ Créditos añadidos al diálogo About"
    else
        log "ℹ️  Créditos ya presentes"
    fi
else
    warn "⚠️ No se encontró $ABOUT_FILE"
fi

# Guardar copia del código fuente parcheado
log "Guardando copia del código fuente parcheado..."
BACKUP_DIR="$(pwd)/patched-source-backup-appimage"
mkdir -p "$BACKUP_DIR"
cp -r "$PROJECT_DIR/src/frescobaldi" "$BACKUP_DIR/"
log "✅ Copia guardada en $BACKUP_DIR/frescobaldi/"

header "📝 GENERANDO RECETA APPIMAGE-BUILDER"
cat <<EOF > appimage-builder.yml
version: 1
script:
  - rm -rf AppDir || true
  - mkdir -p AppDir/usr/src
  - python3 -m venv AppDir/usr/src/venv
  - source AppDir/usr/src/venv/bin/activate
  - pip install --upgrade pip build hatchling
  - cd src && python3 -m build --wheel && cd ..
  - pip install src/dist/*.whl
  # ✂️ Optimización: Solo bytecode -OO (MANTENEMOS TODOS LOS IDIOMAS)
log "⚡ Optimizando: Bytecode Python sin docstrings (-OO)..."
PKG_DIR=$(find "$APPDIR/usr/lib" -maxdepth 1 -type d -name "frescobaldi*" | grep -v dist-info | head -n 1)
if [[ -n "$PKG_DIR" ]] && [[ -d "$PKG_DIR" ]]; then
	log "   📂 Directorio encontrado: $PKG_DIR"
	python3 -OO -m compileall "$PKG_DIR"
	find "$PKG_DIR" -name "*.py" -delete || true
	log "✅ Optimización -OO completada (todos los idiomas conservados)"
else
	warn "⚠️ No se encontró el directorio del paquete para optimizar"
fi
  # ⚡ Optimización: Bytecode sin docstrings
  - python3 -OO -m compileall AppDir/usr/src/venv/lib/python3.*/site-packages/frescobaldi_app
  - find AppDir/usr/src/venv/lib/python3.*/site-packages/frescobaldi_app -name "*.py" -delete || true

AppDir:
  path: ./AppDir
  app_info:
    id: org.frescobaldi.Frescobaldi
    name: Frescobaldi
    icon: frescobaldi
    version: ${VER}
    exec: usr/src/venv/bin/frescobaldi
    exec_args: "\$@"
  runtime:
    env:
      PYTHONHOME: "\${APPDIR}/usr/src/venv"
      QT_QPA_PLATFORMTHEME: "qt6ct"
  apt:
    arch: amd64
    allow_unauthenticated: true
    sources:
      - sourceline: deb http://archive.ubuntu.com/ubuntu/ jammy main universe
    include:
      - python3-pyqt6
      - python3-pyqt6.qtwebengine
      - python3-ly
      - python3-qpageview
      $( [[ "$ENABLE_POPPLER" == true ]] && echo "- poppler-utils" )
    exclude:
      - adwaita-icon-theme
      - humanity-icon-theme
      - "*-doc"
      - "*-dev"
      - "*-locale"
  files:
    exclude:
      - usr/share/man
      - usr/share/doc/*/README.*
      - usr/share/doc/*/changelog.*
EOF

header "🚀 CONSTRUYENDO APPIMAGE"
appimage-builder --recipe appimage-builder.yml --skip-test

GENERATED_APPIMAGE=$(ls -1 *.AppImage 2>/dev/null | head -n 1)
[[ -z "$GENERATED_APPIMAGE" ]] && die "No se generó la AppImage"

APPIMAGE_FINAL="frescobaldi-${VER}-qt6-x86_64.AppImage"
mv "$GENERATED_APPIMAGE" "$APPIMAGE_FINAL"
sha256sum "$APPIMAGE_FINAL" > SHA256SUMS-APPIMAGE.txt

if [[ "$SIGN" == true ]]; then
    header "🔐 FIRMANDO CON GPG"
    [[ -z "$GPG_KEY" ]] && GPG_KEY=$(gpg --list-secret-keys --keyid-format long | grep "^sec" | head -n1 | awk '{print $2}' | cut -d'/' -f2)
    gpg --default-key "$GPG_KEY" --yes --detach-sign --armor "$APPIMAGE_FINAL"
    log "✅ Firma generada: ${APPIMAGE_FINAL}.asc"
fi

if [[ "$PUBLISH" == true ]]; then
    header "🌐 PUBLICANDO EN GITHUB"
    gh auth status >/dev/null 2>&1 || die "No autenticado en GitHub CLI"
    FULL_REPO="${GITHUB_USER}/${REPO_NAME}"
    UPLOAD_FILES=("$APPIMAGE_FINAL" "SHA256SUMS-APPIMAGE.txt")
    [[ -f "${APPIMAGE_FINAL}.asc" ]] && UPLOAD_FILES+=("${APPIMAGE_FINAL}.asc")
    
    gh release upload "v${VER}" --clobber --repo "$FULL_REPO" "${UPLOAD_FILES[@]}" 2>/dev/null || \
    gh release create "v${VER}" --repo "$FULL_REPO" --title "Frescobaldi ${VER} (PyQt6 Optimized)" --notes "Optimized AppImage build." "${UPLOAD_FILES[@]}"
    log "✅ Publicado en https://github.com/$FULL_REPO/releases/tag/v${VER}"
fi

log "🎉 ¡ÉXITO! AppImage lista: $APPIMAGE_FINAL ($(du -h "$APPIMAGE_FINAL" | cut -f1))"
log "📍 Código fuente parcheado: $BACKUP_DIR/frescobaldi/"
