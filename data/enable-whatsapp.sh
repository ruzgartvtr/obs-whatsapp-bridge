#!/usr/bin/env bash
# WhatsApp Desktop'ta OBS / NDI sanal kamerasının listede görünmesi için
# library-validation'ı kapatacak şekilde yeniden imzalar.
#
# Kullanım:
#   ./scripts/enable-whatsapp.sh
#   ./scripts/enable-whatsapp.sh /Applications/WhatsApp.app
#
# veya:
#   curl -fsSL https://raw.githubusercontent.com/ruzgartvtr/obs-whatsapp-bridge/main/scripts/enable-whatsapp.sh | bash
#
# Not: WhatsApp güncellenince imza geri gelir; script'i tekrar çalıştırın.

set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/ruzgartvtr/obs-whatsapp-bridge/main/scripts/enable-whatsapp.sh"
WA="${1:-/Applications/WhatsApp.app}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Yönetici gerekli — macOS şifreniz sorulacak." >&2
  SCRIPT_PATH="${BASH_SOURCE[0]:-}"
  if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
    exec sudo bash "$SCRIPT_PATH" "$@"
  fi
  # curl | bash: script dosya değil; içeriği yeniden çekip root olarak çalıştır
  exec sudo bash -c "$(curl -fsSL "$RAW_URL")" bash "$@"
fi

if [[ ! -d "$WA" ]]; then
  # Yaygın alternatif konum
  if [[ -d "${HOME}/Applications/WhatsApp.app" ]]; then
    WA="${HOME}/Applications/WhatsApp.app"
  else
    echo "WhatsApp bulunamadı: $WA" >&2
    echo "WhatsApp’ı kurduktan sonra tekrar çalıştırın." >&2
    exit 1
  fi
fi

ENT="$(mktemp -t wa-ent)"
trap 'rm -f "$ENT"' EXIT

cat >"$ENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
EOF

echo "==> Yeniden imzalanıyor: $WA"
codesign --entitlements "$ENT" -f -s - "$WA"

for helper in \
  "WhatsApp Helper" \
  "WhatsApp Helper (GPU)" \
  "WhatsApp Helper (Plugin)" \
  "WhatsApp Helper (Renderer)"; do
  P="$WA/Contents/Frameworks/${helper}.app"
  if [[ -d "$P" ]]; then
    echo "==> Helper: $helper"
    codesign --entitlements "$ENT" -f -s - "$P"
  fi
done

# Kamera iznini sıfırla; kullanıcı WhatsApp'ı açınca tekrar sorulur
tccutil reset Camera net.whatsapp.WhatsApp 2>/dev/null || true
tccutil reset Microphone net.whatsapp.WhatsApp 2>/dev/null || true

echo
echo "Tamam. WhatsApp'ı Force Quit ile kapatıp yeniden açın."
echo "Görüntülü aramada:"
echo "  Kamera  → OBS Virtual Camera  (veya NDI Video)"
echo "  Mikrofon → BlackHole 2ch     (veya OBS Bridge Mic)"
