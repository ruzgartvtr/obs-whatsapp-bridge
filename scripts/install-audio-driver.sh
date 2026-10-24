#!/usr/bin/env bash
# OBS Bridge Mic Audio Server Plugin kurulumunu yapar.
# Önce build edin: ./scripts/build-macos.sh
# veya hazır .driver paketini DRIVER_PATH ile verin.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER_PATH="${1:-}"

if [[ -z "$DRIVER_PATH" ]]; then
  for cand in \
    "$ROOT/build/OBSBridgeMic.driver" \
    "$ROOT/build/mac/OBSBridgeMic.driver" \
    "$ROOT/dist/OBSBridgeMic.driver"; do
    if [[ -d "$cand" ]]; then
      DRIVER_PATH="$cand"
      break
    fi
  done
fi

if [[ -z "${DRIVER_PATH}" || ! -d "$DRIVER_PATH" ]]; then
  echo "OBSBridgeMic.driver bulunamadı."
  echo
  echo "Seçenek A — bu projeyi Mac'te derleyin:"
  echo "  ./scripts/build-macos.sh"
  echo "  ./scripts/install-audio-driver.sh"
  echo
  echo "Seçenek B — hızlı yedek (Homebrew):"
  echo "  brew install blackhole-2ch"
  echo "  (OBS Bridge paneli BlackHole'u da otomatik tanır)"
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo "$0" "$DRIVER_PATH"
fi

DEST="/Library/Audio/Plug-Ins/HAL/OBSBridgeMic.driver"
echo "==> Kuruluyor: $DEST"
rm -rf "$DEST"
cp -R "$DRIVER_PATH" "$DEST"

echo "==> coreaudiod yeniden başlatılıyor…"
launchctl kickstart -k system/com.apple.audio.coreaudiod || \
  killall coreaudiod 2>/dev/null || true

sleep 1
echo "Tamam. Sistem Ayarları → Ses içinde “OBS Bridge Mic” görünmeli."
echo "OBS'i yeniden başlatın → Tools → WhatsApp Bridge → Ses köprüsünü aç."
