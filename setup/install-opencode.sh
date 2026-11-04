#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  OpenCode for Termux — auto installer
#  Upstream: https://github.com/guysoft/opencode-termux
#  Target  : Termux aarch64 (Android 7+)
#
#  Usage:
#    bash install-opencode.sh              # v1 stable
#    bash install-opencode.sh --v2         # v2 pre-release (experimental)
#    bash install-opencode.sh --uninstall  # hapus
#    bash install-opencode.sh --help
#
#  JANGAN dijalankan di dalam proot/chroot.
# ============================================================
set -euo pipefail

REPO="guysoft/opencode-termux"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPBASE="${TMPDIR:-/tmp}"
TS="$(date +%Y%m%d-%H%M%S)"

# ---------- warna ----------
if [ -t 1 ]; then
  R=$'\033[0m'; B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; E=$'\033[31m'; C=$'\033[36m'
else
  R=""; B=""; G=""; Y=""; E=""; C=""
fi

say()  { printf '%s[*]%s %s\n' "$C" "$R" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$G" "$R" "$*"; }
warn() { printf '%s[!]%s %s\n' "$Y" "$R" "$*"; }
die()  { printf '%s[x]%s %s\n' "$E" "$R" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------- argumen ----------
MODE="v1"
ACTION="install"
for a in "$@"; do
  case "$a" in
    --v2)        MODE="v2" ;;
    --uninstall) ACTION="uninstall" ;;
    --help|-h)
      cat <<EOF
OpenCode for Termux — installer

  bash install-opencode.sh              # pasang OpenCode v1 (stable)
  bash install-opencode.sh --v2         # pasang OpenCode v2 (pre-release)
  bash install-opencode.sh --uninstall  # hapus OpenCode
  bash install-opencode.sh --help

Butuh Termux asli (bukan proot/chroot), aarch64.
Sumber: https://github.com/guysoft/opencode-termux
EOF
      exit 0 ;;
    *) die "argumen tidak dikenal: $a (pakai --help)" ;;
  esac
done

# ---------- sanity check ----------
[ -d "$PREFIX" ] || die "\$PREFIX tidak ditemukan ($PREFIX). Jalankan di dalam Termux."

# proot/chroot guard: Termux asli -> uname -o = Android
OS_KERNEL="$(uname -o 2>/dev/null || echo unknown)"
if [ "$OS_KERNEL" != "Android" ]; then
  die "Ini bukan Termux Android (uname -o = $OS_KERNEL). Jalankan di Termux asli, bukan proot/chroot."
fi
if grep -qa "PRoot" /proc/version 2>/dev/null || [ -n "${PROOT_TMP_DIR:-}" ] || [ -n "${PROOT_LOADER:-}" ]; then
  die "Terdeteksi proot/chroot. Jalankan script ini di Termux asli (bukan di proot-distro)."
fi

ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] || die "Arsitektur $ARCH tidak didukung (butuh aarch64)."

if [ "$(id -u)" -eq 0 ]; then
  warn "Kamu root. Installer ini tidak butuh root — sebaiknya jalankan sebagai user Termux biasa."
fi

# ---------- paket dependency ----------
install_pkg() {
  local p="$1" bin="${2:-$1}"
  need_cmd "$bin" && return 0
  say "Memasang paket: $p"
  pkg install -y "$p" >/dev/null 2>&1 || pkg install -y "$p" || die "gagal memasang $p"
}

# ============================================================
#  UNINSTALL
# ============================================================
do_uninstall() {
  say "Menghapus OpenCode..."
  rm -f  "$PREFIX/bin/opencode" "$PREFIX/bin/opencode2"
  rm -rf "$PREFIX/libexec/opencode" "$PREFIX/libexec/opencode2"
  rm -f  "$PREFIX/lib/libtagfix.so" "$PREFIX/lib/libopentui.so"
  # libc++_shared.so bisa dipakai paket lain — hanya hapus kalau tidak ada referensi lain
  if [ -f "$PREFIX/lib/libc++_shared.so" ]; then
    if ! grep -Rqs "libc++_shared" "$PREFIX/bin" 2>/dev/null; then
      rm -f "$PREFIX/lib/libc++_shared.so"
    else
      warn "libc++_shared.so dibiarkan (dipakai paket lain)."
    fi
  fi
  ok "OpenCode dihapus. (File unduhan di \$TMPDIR sudah dibersihkan otomatis.)"
  exit 0
}

# ============================================================
#  RESOLVE RELEASE
# ============================================================
resolve_release() {
  local pattern="$1" json tag url

  json="$(curl -fsSL --connect-timeout 20 -H 'Accept: application/vnd.github+json' \
          "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null || true)"

  tag="$(printf '%s' "$json" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/' || true)"
  url="$(printf '%s' "$json" | grep -oE "https://[^\"]*${pattern}" | head -1 || true)"

  # fallback kalau API kena rate-limit / diblokir
  if [ -z "$url" ]; then
    warn "GitHub API tidak bisa dipakai, fallback ke halaman release..."
    tag="$(curl -fsSI --connect-timeout 20 "https://github.com/$REPO/releases/latest" 2>/dev/null \
           | tr -d '\r' | sed -n 's|^[Ll]ocation: .*/tag/\(.*\)$|\1|p' || true)"
    [ -n "$tag" ] || die "Gagal menemukan release terbaru. Cek koneksi internet."

    local page
    page="$(curl -fsSL --connect-timeout 20 "https://github.com/$REPO/releases/expanded_assets/$tag" 2>/dev/null || true)"
    local rel
    rel="$(printf '%s' "$page" | grep -oE "/$REPO/releases/download/[^\"]*${pattern}" | head -1 || true)"
    [ -n "$rel" ] || die "Asset ${pattern} tidak ditemukan di release $tag."
    url="https://github.com${rel}"
  fi

  printf '%s\n%s\n' "$tag" "$url"
}

# v2 tidak ada di "latest release" (latest malah nunjuk ke v0.2.1 / OpenCode 1.x),
# jadi kita scan daftar release dan ambil asset opencode2 terbaru.
resolve_release_v2() {
  local json urls url tag
  json="$(curl -fsSL --connect-timeout 20 -H 'Accept: application/vnd.github+json' \
          "https://api.github.com/repos/$REPO/releases?per_page=30" 2>/dev/null || true)"

  urls="$(printf '%s' "$json" | tr ',' '\n' | grep '"browser_download_url"' \
          | grep -oE 'https://[^"]*opencode2-[^"]*android-aarch64\.zip' || true)"

  # utamakan rilis stabil (tanpa -rc), fallback ke rc terbaru
  url="$(printf '%s\n' "$urls" | grep -v -- '-rc' | head -1 || true)"
  [ -n "$url" ] || url="$(printf '%s\n' "$urls" | head -1 || true)"

  if [ -z "$url" ]; then
    warn "API release tidak tersedia, pakai rilis v2 terakhir yang diketahui (v1.0.3)."
    tag="v1.0.3"
    url="https://github.com/$REPO/releases/download/$tag/opencode2-1.0.3-android-aarch64.zip"
  else
    tag="$(printf '%s' "$url" | sed -E 's|.*/download/([^/]+)/.*|\1|')"
  fi

  printf '%s\n%s\n' "$tag" "$url"
}

# ============================================================
#  DOWNLOAD + VERIFY
# ============================================================
download_asset() {
  local url="$1" dest="$2" tag="$3"
  say "Mengunduh: $(basename "$url")"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --progress-bar -o "$dest" "$url"

  # verifikasi SHA256 bila tersedia
  if need_cmd sha256sum; then
    local sums
    sums="$(curl -fsSL --connect-timeout 20 \
            "https://github.com/$REPO/releases/download/$tag/SHA256SUMS" 2>/dev/null || true)"
    if [ -n "$sums" ]; then
      local want got
      want="$(printf '%s\n' "$sums" | awk -v f="$(basename "$url")" '$2==f {print $1; exit}')"
      if [ -n "$want" ]; then
        got="$(sha256sum "$dest" | awk '{print $1}')"
        if [ "$want" = "$got" ]; then
          ok "Checksum SHA256 cocok."
        else
          die "Checksum tidak cocok! unduhan korup / dimodifikasi."
        fi
      else
        warn "Checksum untuk file ini tidak ada di SHA256SUMS — dilewati."
      fi
    fi
  else
    warn "sha256sum tidak tersedia — verifikasi checksum dilewati."
  fi
}

# ============================================================
#  INSTALL v1 (standalone zip)
# ============================================================
install_v1() {
  local tag url work zipdir wrapper main
  local resolved
  resolved="$(resolve_release 'android-aarch64\.zip')"
  tag="$(printf '%s' "$resolved" | sed -n '1p')"
  url="$(printf '%s' "$resolved" | sed -n '2p')"
  ok "Release: $tag"

  install_pkg unzip unzip
  install_pkg curl curl

  work="$(mktemp -d "$TMPBASE/opencode.XXXXXX")"
  trap 'rm -rf "$work"' EXIT

  download_asset "$url" "$work/pkg.zip" "$tag"

  say "Mengekstrak..."
  mkdir -p "$work/pkg"
  unzip -q "$work/pkg.zip" -d "$work/pkg"

  wrapper="$(find "$work/pkg" -maxdepth 3 -type f -name opencode | head -1)"
  main="$(find "$work/pkg" -maxdepth 3 -type f -name opencode.bin | head -1)"
  [ -n "$main" ] || die "opencode.bin tidak ada di dalam zip — format asset berubah."

  mkdir -p "$PREFIX/libexec/opencode" "$PREFIX/lib" "$PREFIX/bin"

  # backup instalasi lama
  if [ -e "$PREFIX/bin/opencode" ] || [ -e "$PREFIX/libexec/opencode/opencode.bin" ]; then
    say "Backup instalasi lama -> *.bak.$TS"
    [ -e "$PREFIX/bin/opencode" ] && cp -p "$PREFIX/bin/opencode" "$PREFIX/bin/opencode.bak.$TS"
    [ -e "$PREFIX/libexec/opencode/opencode.bin" ] && \
      cp -p "$PREFIX/libexec/opencode/opencode.bin" "$PREFIX/libexec/opencode/opencode.bin.bak.$TS"
  fi

  say "Memasang binary..."
  if [ -n "$wrapper" ]; then
    cp -f "$wrapper" "$PREFIX/bin/opencode"
  else
    cat > "$PREFIX/bin/opencode" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
export LD_LIBRARY_PATH="$PREFIX/lib:\${LD_LIBRARY_PATH:-}"
exec "$PREFIX/libexec/opencode/opencode.bin" "\$@"
EOF
  fi
  chmod 755 "$PREFIX/bin/opencode"

  cp -f "$main" "$PREFIX/libexec/opencode/opencode.bin"
  chmod 755 "$PREFIX/libexec/opencode/opencode.bin"

  local so
  while IFS= read -r so; do
    say "  lib: $(basename "$so")"
    cp -f "$so" "$PREFIX/lib/$(basename "$so")"
    chmod 644 "$PREFIX/lib/$(basename "$so")"
    # wrapper v1 bisa mencari lib di libexec/opencode juga
    cp -f "$so" "$PREFIX/libexec/opencode/$(basename "$so")"
    chmod 644 "$PREFIX/libexec/opencode/$(basename "$so")"
  done < <(find "$work/pkg" -maxdepth 3 -type f -name '*.so')

  install_pkg ripgrep rg

  ok "Terpasang: $PREFIX/bin/opencode"
}

# ============================================================
#  INSTALL v2 (standalone zip, layout libexec/opencode2)
# ============================================================
install_v2() {
  local tag url work wrapper main so resolved
  resolved="$(resolve_release_v2)"
  tag="$(printf '%s' "$resolved" | sed -n '1p')"
  url="$(printf '%s' "$resolved" | sed -n '2p')"
  ok "Release v2: $tag"

  install_pkg unzip unzip
  install_pkg curl curl

  work="$(mktemp -d "$TMPBASE/opencode2.XXXXXX")"
  trap 'rm -rf "$work"' EXIT

  download_asset "$url" "$work/pkg.zip" "$tag"

  say "Mengekstrak..."
  mkdir -p "$work/pkg"
  unzip -q "$work/pkg.zip" -d "$work/pkg"

  wrapper="$(find "$work/pkg" -maxdepth 3 -type f -name opencode2 | head -1)"
  main="$(find "$work/pkg" -maxdepth 3 -type f -name opencode2.bin | head -1)"
  [ -n "$main" ] || die "opencode2.bin tidak ada di dalam zip — format asset berubah."

  mkdir -p "$PREFIX/libexec/opencode2" "$PREFIX/bin"

  if [ -e "$PREFIX/bin/opencode2" ] || [ -e "$PREFIX/libexec/opencode2/opencode2.bin" ]; then
    say "Backup instalasi lama -> *.bak.$TS"
    [ -e "$PREFIX/bin/opencode2" ] && cp -p "$PREFIX/bin/opencode2" "$PREFIX/bin/opencode2.bak.$TS"
    [ -e "$PREFIX/libexec/opencode2/opencode2.bin" ] && \
      cp -p "$PREFIX/libexec/opencode2/opencode2.bin" "$PREFIX/libexec/opencode2/opencode2.bin.bak.$TS"
  fi

  say "Memasang binary..."
  if [ -n "$wrapper" ]; then
    cp -f "$wrapper" "$PREFIX/bin/opencode2"
  else
    cat > "$PREFIX/bin/opencode2" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
export PREFIX="\${PREFIX:-$PREFIX}"
export OPENTUI_LIB_PATH="$PREFIX/libexec/opencode2/libopentui.so"
export LD_LIBRARY_PATH="$PREFIX/libexec/opencode2:\${LD_LIBRARY_PATH:-}"
exec "$PREFIX/libexec/opencode2/opencode2.bin" "\$@"
EOF
  fi
  chmod 755 "$PREFIX/bin/opencode2"

  cp -f "$main" "$PREFIX/libexec/opencode2/opencode2.bin"
  chmod 755 "$PREFIX/libexec/opencode2/opencode2.bin"

  # wrapper v2 mencari libopentui.so di libexec/opencode2
  while IFS= read -r so; do
    say "  lib: $(basename "$so")"
    cp -f "$so" "$PREFIX/libexec/opencode2/$(basename "$so")"
    chmod 644 "$PREFIX/libexec/opencode2/$(basename "$so")"
  done < <(find "$work/pkg" -maxdepth 3 -type f -name '*.so')

  install_pkg ripgrep rg

  ok "Terpasang: $PREFIX/bin/opencode2"
}

# ============================================================
#  MAIN
# ============================================================
[ "$ACTION" = "uninstall" ] && do_uninstall

printf '%s\n' "${B}OpenCode for Termux — installer${R}"
say "Prefix : $PREFIX"
say "Arch   : $ARCH"
say "Mode   : $MODE"
echo

if [ "$MODE" = "v2" ]; then
  install_v2
  BIN="opencode2"
else
  install_v1
  BIN="opencode"
fi

echo
say "Uji jalan: $BIN --version"
if timeout 60 "$PREFIX/bin/$BIN" --version 2>/dev/null; then
  ok "Binary berjalan."
else
  warn "Binary belum bisa dijalankan otomatis. Coba manual: $BIN"
fi

cat <<EOF

${B}Selesai.${R}

  Jalankan : ${G}$BIN${R}
  Butuh API key provider, contoh:
    export ANTHROPIC_API_KEY="sk-..."
    export OPENAI_API_KEY="sk-..."
  Lalu jalankan lagi: $BIN

  Hapus    : bash $(basename "$0") --uninstall
  Upstream : https://github.com/guysoft/opencode-termux
EOF
