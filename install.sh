#!/bin/sh
# TierTask
# Copyright (C) 2026  Stefan Stark
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <https://www.gnu.org/licenses/>.

set -eu

APP_NAME="TierTask"
BINARY_NAME="tiertask"
APP_ID="de.akjir.tiertask"

if [ "$(id -u)" -eq 0 ]; then
  printf 'Error: Do not run %s as root. Run it in the user context.\n' "$0" >&2
  exit 1
fi

if [ -z "${HOME:-}" ]; then
  printf 'Error: HOME environment variable is not set.\n' >&2
  exit 1
fi

REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
LIBDIR="${LIBDIR:-$PREFIX/lib}"
DATADIR="${DATADIR:-${XDG_DATA_HOME:-$PREFIX/share}}"
DESTDIR="${DESTDIR:-}"

APP_DIR="$LIBDIR/$BINARY_NAME"
USER_DATA_DIR="$DATADIR/$BINARY_NAME"
DESKTOP_DIR="$DATADIR/applications"
ICON_DIR="$DATADIR/icons/hicolor"

print_usage() {
  cat <<EOF
Usage: ./install.sh [command]

Commands:
  all         Build and install $APP_NAME into the user context (default)
  build       Build the obfuscated Linux release bundle
  install     Install the release bundle, symlink, icons, and desktop entry
  uninstall   Remove the installed application files from the user context
  help        Show this help message

Environment variables:
  PREFIX      Installation prefix (default: \$HOME/.local)
  BINDIR      Executable directory (default: \$PREFIX/bin)
  LIBDIR      Application bundle directory (default: \$PREFIX/lib)
  DATADIR     Desktop/icon data directory (default: \$XDG_DATA_HOME or \$PREFIX/share)
  DESTDIR     Optional staging root directory
EOF
}

verify_safe_app_dir() {
  if [ -z "$APP_DIR" ] || [ "$APP_DIR" = "/" ] || [ "$APP_DIR" = "$HOME" ] || [ "$APP_DIR" = "$USER_DATA_DIR" ]; then
    printf 'Error: Unsafe application bundle directory "%s" (must not equal user data directory "%s").\n' "$APP_DIR" "$USER_DATA_DIR" >&2
    exit 1
  fi
}

resolve_bundle_dir() {
  if [ -x "$REPO_DIR/build/linux/x64/release/bundle/$BINARY_NAME" ]; then
    printf '%s\n' "$REPO_DIR/build/linux/x64/release/bundle"
    return 0
  fi
  if [ -x "$REPO_DIR/build/linux/arm64/release/bundle/$BINARY_NAME" ]; then
    printf '%s\n' "$REPO_DIR/build/linux/arm64/release/bundle"
    return 0
  fi
  return 1
}

build_app() {
  if ! command -v flutter >/dev/null 2>&1; then
    printf 'Error: flutter is not installed or not in PATH.\n' >&2
    exit 1
  fi

  printf 'Building %s in %s...\n' "$APP_NAME" "$REPO_DIR"
  (
    cd "$REPO_DIR"
    flutter pub get
    flutter gen-l10n
    flutter build linux --release --obfuscate --split-debug-info=build/symbols
  )
}

refresh_desktop_caches() {
  if [ -n "$DESTDIR" ]; then
    return 0
  fi
  if command -v update-desktop-database >/dev/null 2>&1 && [ -d "$DESKTOP_DIR" ]; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d "$ICON_DIR" ]; then
    gtk-update-icon-cache -f -t "$ICON_DIR" >/dev/null 2>&1 || true
  fi
}

install_app() {
  verify_safe_app_dir

  if ! BUNDLE_DIR="$(resolve_bundle_dir)"; then
    build_app
    if ! BUNDLE_DIR="$(resolve_bundle_dir)"; then
      printf 'Error: Release bundle not found after build.\n' >&2
      exit 1
    fi
  fi

  TARGET_APP_DIR="$DESTDIR$APP_DIR"
  TARGET_BINDIR="$DESTDIR$BINDIR"
  TARGET_DESKTOP_DIR="$DESTDIR$DESKTOP_DIR"
  TARGET_SVG_DIR="$DESTDIR$ICON_DIR/scalable/apps"
  TARGET_PNG_DIR="$DESTDIR$ICON_DIR/512x512/apps"

  printf 'Installing %s bundle to %s...\n' "$APP_NAME" "$TARGET_APP_DIR"
  rm -rf "$TARGET_APP_DIR"
  mkdir -p "$TARGET_APP_DIR"
  cp -R "$BUNDLE_DIR/." "$TARGET_APP_DIR/"
  chmod 755 "$TARGET_APP_DIR/$BINARY_NAME"

  printf 'Linking executable to %s/%s...\n' "$TARGET_BINDIR" "$BINARY_NAME"
  mkdir -p "$TARGET_BINDIR"
  ln -sfn "$APP_DIR/$BINARY_NAME" "$TARGET_BINDIR/$BINARY_NAME"

  printf 'Installing icons to %s...\n' "$DESTDIR$ICON_DIR"
  mkdir -p "$TARGET_SVG_DIR" "$TARGET_PNG_DIR"
  cp "$REPO_DIR/assets/logo/tiertask_logo.svg" "$TARGET_SVG_DIR/$APP_ID.svg"
  chmod 644 "$TARGET_SVG_DIR/$APP_ID.svg"
  cp "$REPO_DIR/assets/logo/tiertask_logo.png" "$TARGET_PNG_DIR/$APP_ID.png"
  chmod 644 "$TARGET_PNG_DIR/$APP_ID.png"

  printf 'Installing desktop entry to %s/%s.desktop...\n' "$TARGET_DESKTOP_DIR" "$APP_ID"
  mkdir -p "$TARGET_DESKTOP_DIR"
  cat > "$TARGET_DESKTOP_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=TierTask
Comment=Deterministic 6-tier task manager
Exec=$BINDIR/$BINARY_NAME
TryExec=$BINDIR/$BINARY_NAME
Icon=$APP_ID
Terminal=false
Categories=Utility;Office;ProjectManagement;
StartupWMClass=$APP_ID
StartupNotify=true
EOF
  chmod 644 "$TARGET_DESKTOP_DIR/$APP_ID.desktop"

  refresh_desktop_caches

  printf 'Installation complete: %s/%s\n' "$BINDIR" "$BINARY_NAME"
  case ":${PATH:-}:" in
    *":$BINDIR:"*) ;;
    *)
      printf 'Note: %s is not in your PATH. Add export PATH="%s:$PATH" to your shell profile.\n' "$BINDIR" "$BINDIR"
      ;;
  esac
}

uninstall_app() {
  verify_safe_app_dir

  TARGET_APP_DIR="$DESTDIR$APP_DIR"
  TARGET_BINDIR="$DESTDIR$BINDIR"
  TARGET_DESKTOP_DIR="$DESTDIR$DESKTOP_DIR"
  TARGET_SVG_DIR="$DESTDIR$ICON_DIR/scalable/apps"
  TARGET_PNG_DIR="$DESTDIR$ICON_DIR/512x512/apps"

  printf 'Removing %s application files from user context (preserving user data in %s)...\n' "$APP_NAME" "$USER_DATA_DIR"
  rm -f "$TARGET_BINDIR/$BINARY_NAME"
  rm -rf "$TARGET_APP_DIR"
  rm -f "$TARGET_DESKTOP_DIR/$APP_ID.desktop"
  rm -f "$TARGET_SVG_DIR/$APP_ID.svg"
  rm -f "$TARGET_PNG_DIR/$APP_ID.png"

  refresh_desktop_caches
  printf 'Uninstallation complete.\n'
}

COMMAND="${1:-all}"
case "$COMMAND" in
  all)
    build_app
    install_app
    ;;
  build)
    build_app
    ;;
  install)
    install_app
    ;;
  uninstall)
    uninstall_app
    ;;
  -h|--help|help)
    print_usage
    ;;
  *)
    printf 'Error: Unknown command "%s".\n\n' "$COMMAND" >&2
    print_usage >&2
    exit 1
    ;;
esac
