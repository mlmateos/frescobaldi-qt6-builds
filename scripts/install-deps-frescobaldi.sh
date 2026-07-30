#!/usr/bin/env bash
#===============================================================================
# install-deps-frescobaldi.sh
# Instala dependencias para compilar Frescobaldi (Python/PyQt6) optimizado
# Compatible con Debian Trixie, Ubuntu 22.04+ y derivados
#===============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
die()  { echo -e "${RED}❌ ERROR: $*${NC}" >&2; exit 1; }
header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}\n${BLUE}  $*${NC}\n${BLUE}═══════════════════════════════════════════════════${NC}\n"; }

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

header "📦 ACTUALIZANDO REPOSITORIOS"
$SUDO apt update

header "🔨 HERRAMIENTAS DE COMPILACIÓN Y EMPAQUETADO"
# Nota: 'hatchling' se llama 'python3-hatchling' en los repositorios de Debian
$SUDO apt install -y build-essential git wget curl pkg-config dpkg-dev debhelper devscripts fakeroot python3 python3-pip python3-venv python3-build python3-hatchling desktop-file-utils libfuse2

header "🎨 DEPENDENCIAS PYTHON / PYQT6"
$SUDO apt install -y python3-pyqt6 python3-pyqt6.qtwebengine python3-ly python3-qpageview poppler-utils || warn "⚠️ Algunos paquetes Python/Qt6 podrían requerir configuración adicional"

header "🌐 GITHUB CLI & GPG"
if ! command -v gh >/dev/null 2>&1; then
    $SUDO mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    $SUDO apt update
    $SUDO apt install -y gh
    log "GitHub CLI instalado"
fi

if ! command -v gpg >/dev/null 2>&1; then
    $SUDO apt install -y gnupg2
    log "GPG instalado"
fi

header "📦 APPIMAGE-BUILDER (Opcional, solo para AppImage)"
if ! command -v appimage-builder >/dev/null 2>&1; then
    warn "⚠️ appimage-builder no encontrado en APT (común en Debian Trixie). Intentando instalar vía pip..."
    # Fallback a pip, ya que el paquete apt a veces falla por la deprecación de apt-key en Trixie
    python3 -m pip install --break-system-packages appimage-builder || warn "⚠️ No se pudo instalar appimage-builder. Podrás compilar el .deb, pero no el AppImage."
    log "Proceso de appimage-builder finalizado"
fi

header "✅ VERIFICACIÓN FINAL"
for cmd in python3 git dpkg-buildpackage gh gpg; do
    command -v "$cmd" >/dev/null 2>&1 && log "$cmd está listo" || warn "$cmd falta"
done

if command -v appimage-builder >/dev/null 2>&1; then
    log "appimage-builder está listo"
else
    warn "appimage-builder no está disponible (solo compilación .deb habilitada)"
fi

log "¡Dependencias de Frescobaldi instaladas correctamente!"
