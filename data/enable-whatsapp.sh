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

WA="${1:-/Applications/WhatsApp.app}"

if [[ ! -d "$WA" ]]; then
  echo "WhatsApp bulunamadı: $WA" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Yönetici gerekli — sudo ile çalıştırın." >&2
  exec sudo "$0" "$@"
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
echo "  Mikrofon → OBS Bridge Mic     (veya BlackHole 2ch)"
