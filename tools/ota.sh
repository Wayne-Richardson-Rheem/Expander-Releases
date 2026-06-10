#!/bin/bash
set -euo pipefail

BIN="expander"

RUNTIME="$HOME/Dev/Expander/runtime"
BIN_DIR="$RUNTIME/bin"
OTA_DIR="$RUNTIME/ota"
KEY_DIR="$OTA_DIR/keys"

BASE_URL="https://raw.githubusercontent.com/Wayne-Richardson-Rheem/Expander-Releases/main/releases"

mkdir -p "$OTA_DIR"
cd "$OTA_DIR"

if [[ ! -x "$BIN_DIR/$BIN" ]]; then
  echo "[OTA] ERROR: $BIN_DIR/$BIN does not exist or is not executable"
  exit 1
fi

CURRENT_VERSION="$("$BIN_DIR/$BIN" --version | tr -d '\n\r')"
echo "[OTA] Current version: $CURRENT_VERSION"

echo "[OTA] Checking for update..."
LATEST_VERSION="$(curl -fsSL "$BASE_URL/../latest.txt" | tr -d '\n\r')"
echo "[OTA] Latest available version: $LATEST_VERSION"

if [[ "$LATEST_VERSION" == "$CURRENT_VERSION" ]]; then
  echo "[OTA] Already up to date ($CURRENT_VERSION)"
  exit 0
fi

VERSION="$LATEST_VERSION"
BIN_FILE="$BIN-$VERSION"
VERSION_DIR="$BASE_URL/v$VERSION"

echo "[OTA] Downloading v$VERSION..."
curl -fsSLO "$VERSION_DIR/$BIN_FILE"
curl -fsSLO "$VERSION_DIR/$BIN_FILE.sha256"
curl -fsSLO "$VERSION_DIR/$BIN_FILE.sha256.asc"

echo "[OTA] Verifying signature..."
gpg --batch --no-default-keyring \
  --keyring "$OTA_DIR/ota-keyring.gpg" \
  --import "$KEY_DIR/expander_ota_pubkey.asc" >/dev/null 2>&1 || true

gpg --batch --no-default-keyring \
  --keyring "$OTA_DIR/ota-keyring.gpg" \
  --verify "$BIN_FILE.sha256.asc" "$BIN_FILE.sha256"

echo "[OTA] Verifying checksum..."
awk -v bin="$BIN_FILE" '{print $1 "  " bin}' "$BIN_FILE.sha256" | sha256sum -c -

echo "[OTA] Saving rollback version..."
echo "$CURRENT_VERSION" > "$OTA_DIR/last-good"

echo "[OTA] Installing new binary..."
install -m 755 "$BIN_FILE" "$BIN_DIR/$BIN_FILE"

echo "[OTA] Switching symlink..."
ln -sfn "$BIN_FILE" "$BIN_DIR/$BIN"

echo "[OTA] Running smoke test..."
NEW_VERSION="$("$BIN_DIR/$BIN" --version | tr -d '\n\r')" || true

if [[ "$NEW_VERSION" != "$VERSION" ]]; then
  echo "[OTA] Smoke test failed — rolling back"
  OLD_VERSION="$(cat "$OTA_DIR/last-good")"
  ln -sfn "$BIN-$OLD_VERSION" "$BIN_DIR/$BIN"
  exit 1
fi

echo "[OTA] Update successful ($VERSION)"
