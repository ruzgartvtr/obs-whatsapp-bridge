#!/usr/bin/env bash
# OBS WhatsApp Bridge — tek komutla kurulum (macOS)
#
#   curl -fsSL https://raw.githubusercontent.com/ruzgartvtr/obs-whatsapp-bridge/main/install.sh | bash
#
# veya repoyu indirdikten sonra:
#   ./install.sh

set -euo pipefail

REPO_URL="https://github.com/ruzgartvtr/obs-whatsapp-bridge"
RAW_BASE="https://raw.githubusercontent.com/ruzgartvtr/obs-whatsapp-bridge/main"
REPO_DIR_NAME="obs-whatsapp-bridge"
OBS_SUPPORT="${HOME}/Library/Application Support/obs-studio"
SCRIPTS_DIR="${OBS_SUPPORT}/scripts"
PLUGIN_DIR="${OBS_SUPPORT}/plugins"

RED=$'\033[31m'
GRN=$'\033[32m'
YLW=$'\033[33m'
BLD=$'\033[1m'
RST=$'\033[0m'

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s!%s %s\n' "$YLW" "$RST" "$*"; }
die()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

need_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "Bu kurulum yalnızca macOS içindir."
}

have() { command -v "$1" >/dev/null 2>&1; }

ensure_homebrew() {
  if have brew; then
    ok "Homebrew hazır"
    return
  fi
  say "Homebrew kuruluyor (Apple’ın paket yöneticisi)…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  have brew || die "Homebrew kurulamadı. https://brew.sh adresinden elle kurup tekrar deneyin."
  ok "Homebrew kuruldu"
}

ensure_blackhole() {
  if system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole"; then
    ok "BlackHole sanal mikrofonu zaten var"
    return
  fi
  # Cihaz listesinde yoksa yine de brew ile kur / yükselt
  say "Sanal mikrofon (BlackHole 2ch) kuruluyor — OBS sesi WhatsApp’a buradan gider…"
  if brew list --cask blackhole-2ch &>/dev/null || brew list blackhole-2ch &>/dev/null; then
    ok "BlackHole paketi zaten kurulu"
  else
    brew install blackhole-2ch || brew install --cask blackhole-2ch || \
      die "BlackHole kurulamadı. Elle: brew install blackhole-2ch"
  fi
  warn "BlackHole yeni kurulduysa Sistem Ayarları → Ses içinde görünmesi için bir kez çıkış yapmanız veya Mac’i yeniden başlatmanız gerekebilir."
  ok "BlackHole kurulumu tamam"
}

resolve_workdir() {
  # Script repo içinden çalışıyorsa orayı kullan; değilse geçici klon
  local self
  self="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [[ -n "$self" && -f "$self/scripts/enable-whatsapp.sh" && -f "$self/obs-scripts/whatsapp-bridge.lua" ]]; then
    WORKDIR="$self"
    return
  fi
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/obs-whatsapp-bridge.XXXXXX")"
  say "Kaynak indiriliyor → $WORKDIR"
  if have git; then
    git clone --depth 1 "$REPO_URL.git" "$WORKDIR/$REPO_DIR_NAME"
    WORKDIR="$WORKDIR/$REPO_DIR_NAME"
  else
    curl -fsSL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar -xz -C "$WORKDIR"
    WORKDIR="$(find "$WORKDIR" -maxdepth 1 -type d -name 'obs-whatsapp-bridge-*' | head -1)"
  fi
  [[ -d "$WORKDIR" ]] || die "Kaynak indirilemedi. İnternet bağlantınızı kontrol edin."
}

install_obs_script() {
  mkdir -p "$SCRIPTS_DIR"
  local src="$WORKDIR/obs-scripts/whatsapp-bridge.lua"
  [[ -f "$src" ]] || die "whatsapp-bridge.lua bulunamadı ($src)"
  cp "$src" "$SCRIPTS_DIR/whatsapp-bridge.lua"
  ok "OBS script kopyalandı → $SCRIPTS_DIR/whatsapp-bridge.lua"
}

install_native_plugin_if_possible() {
  # İsteğe bağlı: kullanıcıda OBS SDK + cmake varsa native .plugin de derlenir
  if [[ ! -f "$WORKDIR/scripts/build-macos.sh" ]]; then
    return
  fi
  if ! have cmake; then
    warn "cmake yok — native eklenti atlandı (Lua script yeterli)."
    return
  fi
  if [[ -z "${OBS_PATH:-}" ]]; then
    warn "OBS_PATH tanımlı değil — native eklenti atlandı. Ses köprüsü Lua script ile çalışır."
    return
  fi
  say "Native OBS eklentisi derleniyor…"
  if (cd "$WORKDIR" && ./scripts/build-macos.sh); then
    "$WORKDIR/scripts/install-obs-plugin.sh" || true
    if [[ -d "$WORKDIR/build/OBSBridgeMic.driver" ]]; then
      "$WORKDIR/scripts/install-audio-driver.sh" || true
    fi
    ok "Native eklenti kuruldu (Tools → WhatsApp Bridge)"
  else
    warn "Native derleme olmadı; Lua script ile devam."
  fi
}

enable_whatsapp() {
  local script="$WORKDIR/scripts/enable-whatsapp.sh"
  [[ -f "$script" ]] || die "enable-whatsapp.sh yok"
  chmod +x "$script"
  say ""
  say "${BLD}WhatsApp sanal kamera erişimi${RST}"
  say "Yönetici şifresi sorulacak. WhatsApp’ta OBS kamerasının listede çıkması için gerekli."
  say ""
  if [[ -d /Applications/WhatsApp.app ]] || \
     [[ -d "$HOME/Applications/WhatsApp.app" ]]; then
    "$script" || warn "WhatsApp imzası uygulanamadı — sonra elle: $script"
    ok "WhatsApp sanal kamera ayarı uygulandı"
  else
    warn "WhatsApp.app bulunamadı. WhatsApp’ı kurduktan sonra çalıştırın:"
    say "  $script"
  fi
}

check_obs() {
  if [[ -d /Applications/OBS.app ]]; then
    ok "OBS Studio bulundu"
  else
    warn "OBS.app /Applications altında yok. https://obsproject.com adresinden kurun; script yine de yüklendi."
  fi
}

print_next_steps() {
  cat <<EOF

${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}
${BLD}Kurulum bitti. Şimdi OBS + WhatsApp’ta şunu yapın:${RST}
${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}

1) OBS Studio’yu açın (açıksa tamamen kapatıp yeniden açın).

2) Menü: ${BLD}Tools → Scripts${RST}
   → sol altta ${BLD}+${RST}
   → şu dosyayı seçin:
     ${SCRIPTS_DIR}/whatsapp-bridge.lua

3) Scripts penceresinde ${BLD}WhatsApp Bridge${RST} seçiliyken
   ${BLD}Ses köprüsünü aç${RST} düğmesine basın
   (mikrofon cihazı: BlackHole 2ch / OBS Bridge Mic).

4) OBS’te ${BLD}Start Virtual Camera${RST}’ya basın.

5) WhatsApp’ı Force Quit ile kapatıp açın.
   Görüntülü aramada:
     • Kamera  → ${BLD}OBS Virtual Camera${RST}
     • Mikrofon → ${BLD}BlackHole 2ch${RST} (veya OBS Bridge Mic)

Yardım: ${REPO_URL}
EOF
}

main() {
  say ""
  say "${BLD}OBS WhatsApp Bridge${RST} — macOS kurulum"
  say "Kaynak: $REPO_URL"
  say ""

  need_macos
  ensure_homebrew
  ensure_blackhole
  resolve_workdir
  install_obs_script
  install_native_plugin_if_possible
  check_obs
  enable_whatsapp
  print_next_steps
}

main "$@"
