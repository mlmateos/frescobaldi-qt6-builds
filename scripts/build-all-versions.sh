#!/usr/bin/env bash
#===============================================================================
# build-all-versions.sh (Revisado)
# Orquestador simple para compilar .deb y AppImage de Frescobaldi en secuencia
#===============================================================================
set -euo pipefail

VERSION="4.0.7"
FLAGS="--clean --poppler --sign --publish"

echo "═══════════════════════════════════════════════════"
echo "  ORQUESTADOR DE COMPILACIÓN: FRESCOBALDI Qt6"
echo "═══════════════════════════════════════════════════"
echo ""
echo "🎯 Versión objetivo: $VERSION"
echo "🚩 Banderas aplicadas: $FLAGS"
echo ""
read -p "¿Deseas compilar .deb y AppImage en secuencia? (s/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "❌ Cancelado por el usuario"
    exit 0
fi

START_TIME=$(date +%s)

echo ""
echo "═══════════════════════════════════════════════════"
echo "  🔨 PASO 1: Compilando paquete .deb"
echo "═══════════════════════════════════════════════════"
./build-frescobaldi-deb.sh --branch "$VERSION" $FLAGS

echo ""
echo "═══════════════════════════════════════════════════"
echo "  🔨 PASO 2: Compilando AppImage"
echo "═══════════════════════════════════════════════════"
./build-frescobaldi-appimage.sh --branch "$VERSION" $FLAGS

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo ""
echo "═══════════════════════════════════════════════════"
echo "  🎉 PROCESO COMPLETADO"
echo "═══════════════════════════════════════════════════"
echo "⏱️  Tiempo total: $((TOTAL_DURATION / 60))m $((TOTAL_DURATION % 60))s"
echo "📦 Releases en GitHub: https://github.com/mlmateos/frescobaldi-qt6-builds/releases"
echo ""