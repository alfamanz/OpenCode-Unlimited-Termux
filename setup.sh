#!/usr/bin/env bash
# One-shot Termux setup for OpenCode-Unlimited-Termux.
# Checks opencode first, then opencode2, asks which to install if neither exists.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/alfamanz/OpenCode-Unlimited-Termux/main/setup.sh)
#   bash setup.sh            # from a checkout
set -euo pipefail

REPO_URL="https://github.com/alfamanz/OpenCode-Unlimited-Termux.git"
SRC="${OCU_SRC:-$HOME/.local/share/ocu-src}"

say()  { printf '[*] %s\n' "$*"; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*"; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

[ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] || die "jalankan di Termux asli, bukan proot/chroot"
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) die "butuh aarch64, ini $(uname -m)" ;;
esac

self_dir=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$self_dir" ] && [ -f "$self_dir/ocu" ]; then
  ROOT="$self_dir"
  say "pakai checkout lokal: $ROOT"
else
  command -v git >/dev/null 2>&1 || { say "install git"; pkg install -y git; }
  rm -rf "$SRC"
  say "clone $REPO_URL"
  git clone --depth 1 "$REPO_URL" "$SRC"
  ROOT="$SRC"
fi

have_v1=0
have_v2=0
command -v opencode  >/dev/null 2>&1 && have_v1=1
command -v opencode2 >/dev/null 2>&1 && have_v2=1

if [ "$have_v1" -eq 1 ]; then
  say "opencode v1: $(opencode --version 2>/dev/null | tail -1)"
  if [ "$have_v2" -eq 0 ]; then
    warn "plugin ocu cuma jalan di opencode2 (v2) — v1 nggak load plugin"
  fi
elif [ "$have_v2" -eq 1 ]; then
  say "opencode2: $(opencode2 --version 2>/dev/null | tail -1)"
else
  echo
  echo "OpenCode belum terpasang. Pilih yang mau dipasang:"
  echo "  1) OpenCode v1  (stable,  binary: opencode)"
  echo "  2) OpenCode v2  (preview, binary: opencode2 — dibutuhkan plugin ocu)"
  echo
  choice="${OCU_OPENCODE:-}"
  if [ -z "$choice" ]; then
    printf 'Pilih [1/2]: '
    read -r choice </dev/tty || choice=2
  fi
  case "$choice" in
    1) bash "$ROOT/setup/install-opencode.sh" ;;
    2) bash "$ROOT/setup/install-opencode.sh" --v2 ;;
    *) die "pilihan tidak valid: $choice" ;;
  esac
fi

say "install ocu"
bash "$ROOT/ocu" install

echo
ok "selesai"
if command -v opencode2 >/dev/null 2>&1; then
  say "cek: ocu status"
  say "pakai: ocu test -live"
else
  warn "opencode2 belum ada — plugin belum aktif. Install v2 kapan saja:"
  say "bash $ROOT/setup/install-opencode.sh --v2"
fi
