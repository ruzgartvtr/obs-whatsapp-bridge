#!/usr/bin/env bash
# Derlenmiş OBS eklentisini kullanıcı eklenti klasörüne kopyalar.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="${1:-}"

if [[ -z "$PLUGIN" ]]; then
  for cand in \
    "$ROOT/build/obs-whatsapp-bridge.plugin" \
    "$ROOT/dist/obs-whatsapp-bridge.plugin"; do
    if [[ -d "$cand" ]]; then
      PLUGIN="$cand"
      break
    fi
  done
fi

if [[ -z "${PLUGIN}" || ! -d "$PLUGIN" ]]; then
  echo "obs-whatsapp-bridge.plugin bulunamadı. Önce: ./scripts/build-macos.sh" >&2
  exit 1
fi

DEST="${HOME}/Library/Application Support/obs-studio/plugins/obs-whatsapp-bridge.plugin"
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -R "$PLUGIN" "$DEST"

# locale + enable script yanına
DATA_DEST="${HOME}/Library/Application Support/obs-studio/plugin_config/obs-whatsapp-bridge"
mkdir -p "$DATA_DEST"
cp -R "$ROOT/data/locale" "$DATA_DEST/" 2>/dev/null || true
cp "$ROOT/scripts/enable-whatsapp.sh" "$DATA_DEST/" 2>/dev/null || true
chmod +x "$DATA_DEST/enable-whatsapp.sh" 2>/dev/null || true

# OBS module data path: also copy into plugin Resources if present
RES="$DEST/Contents/Resources"
mkdir -p "$RES"
cp -R "$ROOT/data/locale" "$RES/" 2>/dev/null || true
cp "$ROOT/scripts/enable-whatsapp.sh" "$RES/" 2>/dev/null || true

echo "Kuruldu: $DEST"
echo "OBS Studio'yu yeniden başlatın → Tools → WhatsApp Bridge"
