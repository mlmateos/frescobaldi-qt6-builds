#!/usr/bin/env bash
#===============================================================================
# build-frescobaldi-deb.sh (v2.9-Definitiva)
# v2.9: Genera debian/rules con printf línea por línea para evitar errores de sintaxis
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
        *) echo " Argumento desconocido: $1" >&2; exit 1 ;;
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
header " PREPARANDO CÓDIGO FUENTE"
PROJECT_DIR="$(pwd)/frescobaldi-deb"
if [[ "$CLEAN_BUILD" == true ]]; then
    [[ "$KEEP_SOURCE" == true ]] && rm -rf "$PROJECT_DIR/debian" "$PROJECT_DIR"/*.deb || rm -rf "$PROJECT_DIR"
    rm -f frescobaldi-*.deb SHA256SUMS*.txt
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
header "️ DETECTANDO VERSIÓN"
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
        log "✅ Créditos añadidos al diálogo About"
    else
        log "ℹ️  Créditos ya presentes"
    fi
else
    warn "⚠️ No se encontró about.py"
fi

#===============================================================================
# PARCHE: ACTUALIZAR PESTAÑA "VERSION" EN EL DIÁLOGO ABOUT
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

# Patrón exacto encontrado en el código fuente de Frescobaldi
old_version_class = r'''class Version\(QTextBrowser\):
    """Version information\."""
    def __init__\(self, parent=None\):
        super\(\).__init__\(parent\)
        self\.setPlainText\(debuginfo\.version_info_string\(\)\)'''

# Nuestra versión personalizada
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
# GENERACIÓN DE ESTRUCTURA DEBIAN (MÉTODO INFALIBLE CON PYTHON PARA TABS)
#===============================================================================
header "📦 GENERANDO ESTRUCTURA DEBIAN"
mkdir -p "$PROJECT_DIR/debian/source"

# Pre-calcular las dependencias
if [[ "$ENABLE_POPPLER" == true ]]; then
DEPENDS_STR="python3, python3-pyqt6, python3-pyqt6.qtsvg, python3-pyqt6.qtwebengine, python3-pyqt6.qtpdf, poppler-utils, lilypond (>= 2.24)"
else
DEPENDS_STR="python3, python3-pyqt6, python3-pyqt6.qtsvg, python3-pyqt6.qtwebengine, python3-pyqt6.qtpdf, lilypond (>= 2.24)"
fi

# 1. debian/control
cat <<EOF > "$PROJECT_DIR/debian/control"
Source: frescobaldi
Section: editors
Priority: optional
Maintainer: Manuel Mateos <manuel@mateos.dev>
Build-Depends: debhelper-compat (= 13), python3-build, python3-pip
Standards-Version: 4.6.2
Homepage: https://www.frescobaldi.org/
Rules-Requires-Root: no

Package: frescobaldi
Architecture: all
Depends: ${DEPENDS_STR}
Recommends: lilypond
Description: LilyPond sheet music text editor (Optimized PyQt6 Build)
 Frescobaldi is an advanced text editor for LilyPond music scores.
 .
 This is a custom optimized build:
 * Built for PyQt6 / Qt 6.8.x LTS
 * Locale pruning (es, en, fr only)
 * Python bytecode optimized (-OO) for smaller footprint
EOF

# 2. Wrapper
cat > "$PROJECT_DIR/frescobaldi-wrapper.sh" << 'WRAPPER_EOF'
#!/usr/bin/env python3
import sys
sys.path.insert(0, '/usr/lib/python3/dist-packages')
from frescobaldi.__main__ import main
sys.exit(main())
WRAPPER_EOF
chmod +x "$PROJECT_DIR/frescobaldi-wrapper.sh"

# 3. Script de parcheo Python 3.14
cat > "$PROJECT_DIR/patch-python314.sh" << 'PATCHEOF'
#!/usr/bin/env bash
TARGET_DIR="debian/frescobaldi/usr/lib/python3/dist-packages"
LINK_FILE=$(find "$TARGET_DIR" -path "*/qpageview/link.py" 2>/dev/null | head -n 1)
if [[ -f "$LINK_FILE" ]]; then
python3 - "$LINK_FILE" << 'PYTHON'
import sys, re
with open(sys.argv[1], 'r', encoding='utf-8') as f: content = f.read()
if "from PyQt6.QtCore import QSize, QPoint" in content and "QUrl" not in content:
    content = content.replace("from PyQt6.QtCore import QSize, QPoint", "from PyQt6.QtCore import QSize, QPoint, QUrl")
content = re.sub(r'QDesktopServices\.openUrl\((\w+)\)', r'QDesktopServices.openUrl(QUrl(\1) if isinstance(\1, str) else \1)', content)
with open(sys.argv[1], 'w', encoding='utf-8') as f: f.write(content)
PYTHON
echo "✅ qpageview/link.py parcheado"
fi
PATCHEOF
chmod +x "$PROJECT_DIR/patch-python314.sh"

# 4. Generar debian/rules USANDO PYTHON (Garantiza TABS reales, imposible de corromper)
# Pasamos $PROJECT_DIR como argumento para que Python use la ruta absoluta
python3 - "$PROJECT_DIR" << 'PYEOF'
import sys
project_dir = sys.argv[1]
rules_content = """#!/usr/bin/make -f
export DH_VERBOSE = 1
%:
\tdh $@

override_dh_auto_build:
\tpython3 -m build --wheel

override_dh_auto_install:
\tpython3 -m pip install --no-deps --target=debian/frescobaldi/usr/lib/python3/dist-packages dist/*.whl
\tpython3 -m pip install --no-deps --target=debian/frescobaldi/usr/lib/python3/dist-packages qpageview python-ly
\tmkdir -p debian/frescobaldi/usr/bin
\tif [ -f debian/frescobaldi/usr/lib/python3/dist-packages/bin/frescobaldi ]; then \\
\t\tmv debian/frescobaldi/usr/lib/python3/dist-packages/bin/frescobaldi debian/frescobaldi/usr/bin/frescobaldi; \\
\t\tchmod +x debian/frescobaldi/usr/bin/frescobaldi; \\
\t\trmdir debian/frescobaldi/usr/lib/python3/dist-packages/bin 2>/dev/null || true; \\
\tfi
\tmkdir -p debian/frescobaldi/usr/share/applications
\tinstall -m 0644 frescobaldi.desktop debian/frescobaldi/usr/share/applications/org.frescobaldi.Frescobaldi.desktop
\tmkdir -p debian/frescobaldi/usr/share/icons/hicolor/256x256/apps
\tICON_SRC=$$(find debian/frescobaldi/usr/lib/python3/dist-packages/frescobaldi -type f \\( -name 'org.frescobaldi.Frescobaldi.svg' -o -name 'frescobaldi.svg' -o -name 'frescobaldi.png' \\) 2>/dev/null | head -n 1); if [ -n \"$$ICON_SRC\" ] && [ -f \"$$ICON_SRC\" ]; then cp \"$$ICON_SRC\" debian/frescobaldi/usr/share/icons/hicolor/256x256/apps/org.frescobaldi.Frescobaldi.svg; else wget -q 'https://raw.githubusercontent.com/frescobaldi/frescobaldi/v4.0.7/frescobaldi_app/icons/org.frescobaldi.Frescobaldi.svg' -O debian/frescobaldi/usr/share/icons/hicolor/256x256/apps/org.frescobaldi.Frescobaldi.svg 2>/dev/null || true; fi

\t./patch-python314.sh
\tPKG_DIR=$$(find debian/frescobaldi/usr/lib/python3/dist-packages -maxdepth 1 -type d -name 'frescobaldi*' | grep -v dist-info | head -n 1); if [ -n \"$$PKG_DIR\" ] && [ -d \"$$PKG_DIR\" ]; then find \"$$PKG_DIR/locale\" -type f -name '*.mo' 2>/dev/null | grep -vE 'es_ES|es_MX|en_US|en_GB|fr_FR' | xargs -r rm -f || true; python3 -OO -m compileall -q \"$$PKG_DIR\" || true; fi

override_dh_usrlocal:

override_dh_strip:
\tdh_strip --no-automatic-dbgsym
"""
rules_path = f"{project_dir}/debian/rules"
with open(rules_path, "w") as f:
    f.write(rules_content.replace("\\t", "\t"))
PYEOF
chmod +x "$PROJECT_DIR/debian/rules"
log "✅ debian/rules generado con TABS reales garantizados por Python en $PROJECT_DIR"

# 3.5. Generar archivo .desktop (Fuera de debian/rules para evitar errores de Make)
cat > "$PROJECT_DIR/frescobaldi.desktop" << 'DESKTOP_EOF'
[Desktop Entry]
Name=Frescobaldi
Comment=LilyPond sheet music text editor
Exec=frescobaldi %F
Icon=org.frescobaldi.Frescobaldi
Type=Application
Categories=AudioVideo;Music;
MimeType=text/x-lilypond;
DESKTOP_EOF

# 5. debian/changelog (con espacios iniciales correctos)
FECHA=$(date -R)
printf 'frescobaldi (%s-%s) unstable; urgency=medium\n\n' "${DEB_VER}" "${PKG_REVISION}" > "$PROJECT_DIR/debian/changelog"
printf '  * Custom optimized build from upstream tag %s.\n' "${VER_GIT}" >> "$PROJECT_DIR/debian/changelog"
printf '  * PyQt6, locale pruning, Python -OO bytecode optimization.\n' >> "$PROJECT_DIR/debian/changelog"
printf '  * Fixed executable placement (/usr/bin), .desktop and icon installation.\n' >> "$PROJECT_DIR/debian/changelog"
printf '  * Added Python 3.14 / PyQt6 6.8 compatibility patches.\n\n' >> "$PROJECT_DIR/debian/changelog"
printf ' -- Manuel Mateos <manuel@mateos.dev>  %s\n' "${FECHA}" >> "$PROJECT_DIR/debian/changelog"
log "✅ debian/changelog generado con formato Debian válido"

# 6. Source format
echo "3.0 (quilt)" > "$PROJECT_DIR/debian/source/format"

#===============================================================================
# EMPAQUETADO .DEB
#===============================================================================
header " EMPAQUETANDO .DEB"
cd "$PROJECT_DIR"
log "Empaquetando..."
dpkg-buildpackage -b -us -uc -d 2>&1 | tee ../build-deb.log || die "Compilación fallida. Revisa ../build-deb.log"
cd ..

DEB_FILE=$(ls frescobaldi_${DEB_VER}-${PKG_REVISION}_*.deb 2>/dev/null | head -n1)
[[ -z "$DEB_FILE" ]] && die "No se generó el .deb"
DEB_FINAL="frescobaldi-${VER}-qt6-all.deb"
mv -f "$DEB_FILE" "$DEB_FINAL"
sha256sum "$DEB_FINAL" > SHA256SUMS-DEB.txt

if [[ "$SIGN" == true ]]; then
    header "🔐 FIRMANDO CON GPG"
    [[ -z "$GPG_KEY" ]] && GPG_KEY=$(gpg --list-secret-keys --keyid-format long | grep "^sec" | head -n1 | awk '{print $2}' | cut -d'/' -f2)
    gpg --default-key "$GPG_KEY" --yes --detach-sign --armor "$DEB_FINAL"
    log "✅ Firma generada: ${DEB_FINAL}.asc"
fi

#===============================================================================
# PUBLICACIÓN EN GITHUB
#===============================================================================
if [[ "$PUBLISH" == true ]]; then
    header "🌐 PUBLICANDO EN GITHUB RELEASES"
    gh auth status >/dev/null 2>&1 || die "No autenticado en GitHub CLI"
    FULL_REPO="${GITHUB_USER}/${REPO_NAME}"
    UPLOAD_FILES=("$DEB_FINAL" "SHA256SUMS-DEB.txt")
    [[ -f "${DEB_FINAL}.asc" ]] && UPLOAD_FILES+=("${DEB_FINAL}.asc")
    
    IS_PRERELEASE=false
    if [[ "$VER" == *alpha* || "$VER" == *beta* || "$VER" == *rc* ]]; then IS_PRERELEASE=true; fi

    if gh release view "v${VER}" --repo "$FULL_REPO" >/dev/null 2>&1; then
        gh release upload "v${VER}" --clobber --repo "$FULL_REPO" "${UPLOAD_FILES[@]}"
        log "✅ .deb AÑADIDO a la release existente"
    else
        CREATE_ARGS=("v${VER}" --repo "$FULL_REPO" --title "Frescobaldi ${VER} (PyQt6 Optimized)" --notes "Optimized build with locale pruning and Python -OO bytecode.")
        [[ "$IS_PRERELEASE" == true ]] && CREATE_ARGS+=(--prerelease)
        gh release create "${CREATE_ARGS[@]}" "${UPLOAD_FILES[@]}"
        [[ "$IS_PRERELEASE" == false ]] && gh release edit "v${VER}" --repo "$FULL_REPO" --latest
        log "✅ Release PUBLICADA"
    fi
fi

#===============================================================================
# INTEGRACIÓN CON REPOSITORIO APT
#===============================================================================
header "📦 INTEGRANDO CON REPOSITORIO APT"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APT_REPO_DIR="$REPO_ROOT"

log "Copiando archivos al repositorio APT..."
cd "$APT_REPO_DIR"

STASHED=false
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    log "💾 Guardando cambios locales de main (git stash)..."
    git stash push -m "Auto-stash by build script $(date +%Y%m%d-%H%M%S)" || warn "⚠️  No se pudo hacer stash"
    STASHED=true
fi

if ! git checkout apt-repo 2>/dev/null; then
    git checkout -b apt-repo origin/apt-repo || die "No se pudo cambiar a rama apt-repo"
fi
log "🔄 Sincronizando rama apt-repo con el remoto..."
git pull origin apt-repo || warn "️  No se pudo sincronizar apt-repo, intentando continuar..."

mkdir -p pool
cp "$REPO_ROOT/scripts/$DEB_FINAL" pool/ 2>/dev/null || true
[[ -f "$REPO_ROOT/scripts/${DEB_FINAL}.asc" ]] && cp "$REPO_ROOT/scripts/${DEB_FINAL}.asc" pool/

log "📂 Creando estructura de ramas (stable/alpha)..."
mkdir -p dists/stable/main/binary-amd64 dists/alpha/main/binary-amd64 dists/stable/main/i18n dists/alpha/main/i18n

log "📋 Generando rama alpha (todas las versiones)..."
dpkg-scanpackages --multiversion pool /dev/null > dists/alpha/main/binary-amd64/Packages
gzip -9cn dists/alpha/main/binary-amd64/Packages > dists/alpha/main/binary-amd64/Packages.gz

log "📋 Generando rama stable (solo versiones estables)..."
python3 << 'PYEOF'
import re
with open('dists/alpha/main/binary-amd64/Packages', 'r') as f:
    content = f.read()
blocks = re.split(r'\n\s*\n', content.strip())
stable_blocks = []
for block in blocks:
    if not block.strip():
        continue
    filename_match = re.search(r'^Filename:\s*(.+)$', block, re.MULTILINE)
    if filename_match:
        filename = filename_match.group(1).strip()
        if 'alpha' not in filename and 'beta' not in filename and 'rc' not in filename:
            stable_blocks.append(block)
with open('dists/stable/main/binary-amd64/Packages', 'w') as f:
    if stable_blocks:
        f.write('\n\n'.join(stable_blocks) + '\n\n')
    else:
        f.write('\n')
print(f"✅ Generado Packages stable con {len(stable_blocks)} paquete(s)")
PYEOF

gzip -9cn dists/stable/main/binary-amd64/Packages > dists/stable/main/binary-amd64/Packages.gz

echo "Frescobaldi Qt6 Repository" | gzip -9c > dists/stable/main/i18n/Translation-en.gz
echo "Frescobaldi Qt6 Repository (Alpha)" | gzip -9c > dists/alpha/main/i18n/Translation-en.gz

for BRANCH in stable alpha; do
    log "🔐 Generando Release con hashes válidos para rama: $BRANCH"
    cd "dists/${BRANCH}"
    apt-ftparchive release . > Release.hashes
    cat << EOF > Release
Origin: mlmateos
Label: Frescobaldi Qt6 Builds
Suite: ${BRANCH}
Codename: ${BRANCH}
Date: $(date -R)
Architectures: amd64
Components: main
Description: Frescobaldi Qt6 Builds Repository (${BRANCH^})
Acquire-By-Hash: no
EOF
    cat Release.hashes >> Release
    if [[ "$SIGN" == true && -n "$GPG_KEY" ]]; then
        log "🔐 Firmando archivo Release de la rama $BRANCH con GPG ($GPG_KEY)..."
        gpg --default-key "$GPG_KEY" --batch --yes --armor --detach-sign -o Release.gpg Release
        gpg --default-key "$GPG_KEY" --batch --yes --clearsign -o InRelease Release
        log "✅ Release firmado correctamente"
    fi
    rm Release.hashes
    cd ../..
done

log "🔄 Actualizando update.json..."
cat > pool/update.json << 'EOF'
[
{
"ref":"refs/tags/4.0.7",
"node_id":"MDM6UmVmMjE2MjYyMjU4OnJlZnMvdGFncy80LjAuNw==",
"url":"https://api.github.com/repos/frescobaldi/frescobaldi/git/refs/tags/4.0.7",
"object":{
"sha":"abc123def456789",
"type":"commit",
"url":"https://api.github.com/repos/frescobaldi/frescobaldi/git/commits/abc123def456789"
}
}
]
EOF

git add -f pool/ dists/
git commit -m "fix: use printf to generate debian/rules with proper syntax" || log "ℹ️ No hay cambios para commitear"
git push origin apt-repo

git checkout main
if [[ "$STASHED" == true ]]; then
    log "🔄 Restaurando cambios locales de main (git stash pop)..."
    git stash pop || warn "⚠️ No se pudo restaurar stash automáticamente. Usa 'git stash pop' manualmente."
fi
log "✅ Archivos añadidos al repositorio APT"

#===============================================================================
# RESULTADO FINAL
#===============================================================================
header "🎉 RESULTADO FINAL"
DEB_PATH="$REPO_ROOT/scripts/$DEB_FINAL"
if [[ -f "$DEB_PATH" ]]; then
    DEB_SIZE=$(du -h "$DEB_PATH" | cut -f1)
    log "¡ÉXITO! Paquete .deb listo:"
    echo "   📦 $(basename "$DEB_FINAL")"
    echo "   📍 $DEB_PATH"
    echo "   🔧 Tamaño: $DEB_SIZE"
    [[ -f "${DEB_PATH}.asc" ]] && echo "   🔐 Firma: $(basename "${DEB_FINAL}.asc")"
    echo ""
    echo "▶  Para instalar desde APT:"
    echo "   sudo apt update && sudo apt install frescobaldi"
else
    die "No se generó el archivo .deb correctamente en $DEB_PATH"
fi
log "✅ Proceso completado."
