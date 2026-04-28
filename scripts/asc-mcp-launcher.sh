#!/bin/bash
# asc-mcp launcher with auto-update from GitHub Releases
# - Checks for new release at most once per TTL_HOURS
# - Falls through to exec immediately if offline / API down

set -e

REPO="conversun/asc-mcp"
BIN="$HOME/.mint/bin/asc-mcp"
STAMP="$HOME/.cache/asc-mcp.lastcheck"
TTL_HOURS=24

mkdir -p "$(dirname "$STAMP")"

needs_check() {
  [ ! -x "$BIN" ] && return 0
  [ ! -f "$STAMP" ] && return 0
  [ -z "$(find "$STAMP" -mmin -$((TTL_HOURS * 60)) 2>/dev/null)" ] && return 0
  return 1
}

if needs_check; then
  LATEST=$(curl -fsSL --max-time 3 \
    "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)

  if [ -n "$LATEST" ]; then
    INSTALLED=$(cat "$HOME/.cache/asc-mcp.version" 2>/dev/null || echo "")
    if [ "$INSTALLED" != "$LATEST" ] || [ ! -x "$BIN" ]; then
      echo "[asc-mcp] updating ${INSTALLED:-none} -> $LATEST" >&2
      if command -v mint >/dev/null 2>&1; then
        mint install "$REPO@$LATEST" --force >&2 \
          && echo "$LATEST" > "$HOME/.cache/asc-mcp.version"
      else
        echo "[asc-mcp] mint not found, skipping update" >&2
      fi
    fi
    touch "$STAMP"
  fi
fi

if [ ! -x "$BIN" ]; then
  echo "[asc-mcp] binary missing at $BIN; run: mint install $REPO@latest" >&2
  exit 127
fi

exec "$BIN" "$@"
