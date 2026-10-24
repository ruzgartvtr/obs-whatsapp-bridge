#!/usr/bin/env bash
# macOS'ta OBS WhatsApp Bridge + OBS Bridge Mic derlemesi.
# Gereksinimler: Xcode CLT, CMake 3.28+, OBS Studio (kaynak veya libobs).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
OBS_PATH="${OBS_PATH:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Bu script yalnızca macOS'ta çalışır (şu an: $(uname -s))." >&2
  echo "Kaynak kod hazır; derlemeyi bir Mac'te yapın." >&2
  exit 1
fi

if [[ -z "$OBS_PATH" ]]; then
  for cand in \
    "$HOME/obs-studio/build/libobs" \
    /opt/homebrew/opt/obs \
    /usr/local/opt/obs \
    "/Applications/OBS.app/Contents/Frameworks"; do
    if [[ -e "$cand" ]]; then
      OBS_PATH="$cand"
      break
    fi
  done
fi

cmake_args=(
  -S "$ROOT"
  -B "$BUILD"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_AUDIO_DRIVER=ON
)

if [[ -n "${OBS_PATH}" ]]; then
  cmake_args+=(-DCMAKE_PREFIX_PATH="$OBS_PATH")
fi

# Prefer obs-deps / official plugin template layout if present
if [[ -n "${OBS_DEPS:-}" ]]; then
  cmake_args+=(-DCMAKE_PREFIX_PATH="${OBS_DEPS};${OBS_PATH}")
fi

echo "==> cmake ${cmake_args[*]}"
if ! cmake "${cmake_args[@]}"; then
  cat <<'EOF' >&2

libobs bulunamadı. Şunlardan biri:

  1) OBS kaynak + build:
       git clone --recursive https://github.com/obsproject/obs-studio
       # resmi macOS build talimatlarını izleyin
       export OBS_PATH=$HOME/obs-studio/build
       ./scripts/build-macos.sh

  2) Yalnızca sanal mikrofon (BlackHole yedeği):
       brew install blackhole-2ch
       # OBS eklentisini yine de OBS SDK ile derlemeniz gerekir

EOF
  exit 1
fi

cmake --build "$BUILD" --config Release -j "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo
echo "Çıktılar $BUILD altında."
echo "  ./scripts/install-audio-driver.sh"
echo "  ./scripts/install-obs-plugin.sh"
echo "  ./scripts/enable-whatsapp.sh"
