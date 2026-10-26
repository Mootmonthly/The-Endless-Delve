#!/usr/bin/env bash
# Installs the official Godot 4.5 stable Linux editor binary to /opt/godot/godot
# (or $GODOT_INSTALL_DIR). Used by the cloud environment setup script and by
# anyone who wants the exact engine version the project is built against.
#
# Usage: bash tools/install_godot.sh
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.5-stable}"
INSTALL_DIR="${GODOT_INSTALL_DIR:-/opt/godot}"
ASSET="Godot_v${GODOT_VERSION}_linux.x86_64"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ASSET}.zip"

if [ -x "${INSTALL_DIR}/godot" ] && "${INSTALL_DIR}/godot" --version 2>/dev/null | grep -q "^${GODOT_VERSION%-stable}"; then
	echo "Godot ${GODOT_VERSION} already installed at ${INSTALL_DIR}/godot"
	exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
echo "Downloading ${URL}"
curl -fsSL --retry 3 -o "${TMP}/godot.zip" "${URL}"
unzip -oq "${TMP}/godot.zip" -d "${TMP}"
mkdir -p "${INSTALL_DIR}"
mv "${TMP}/${ASSET}" "${INSTALL_DIR}/godot"
chmod +x "${INSTALL_DIR}/godot"
echo "Installed: $("${INSTALL_DIR}/godot" --version)"
