#!/bin/bash
# Install the FigCraft launchers and, optionally, figcraft-cli.
#
#   ./scripts/install.sh                 wrappers only, reuse an existing CLI
#   ./scripts/install.sh --with-cli      also download figcraft-cli
#   ./scripts/install.sh --version 0.18.1
#   ./scripts/install.sh --prefix ~/bin
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"
VERSION="${FIGCRAFT_CLI_VERSION:-0.18.1}"
WITH_CLI=0

usage() {
  cat <<'EOF'
Install the FigCraft launchers for DeepSeek Harness.

Options:
  --with-cli         Download figcraft-cli for macOS after installing wrappers.
  --version VERSION  FigCraft release to download (default: 0.18.1).
  --prefix DIR       Install wrappers here (default: ~/.local/bin).
  -h, --help         Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-cli)
      WITH_CLI=1
      ;;
    --version)
      [ "$#" -ge 2 ] || { printf 'Missing value for --version\n' >&2; exit 2; }
      VERSION="$2"
      shift
      ;;
    --version=*)
      VERSION="${1#*=}"
      ;;
    --prefix)
      [ "$#" -ge 2 ] || { printf 'Missing value for --prefix\n' >&2; exit 2; }
      PREFIX="$2"
      shift
      ;;
    --prefix=*)
      PREFIX="${1#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'dsh-figcraft supports macOS only (launchd and the macOS CLI build).\n' >&2
  exit 1
fi

mkdir -p "$PREFIX"
install -m 755 "$ROOT/bin/figcraft-mcp" "$PREFIX/figcraft-mcp"
install -m 755 "$ROOT/bin/figcraft-session" "$PREFIX/figcraft-session"
printf 'Installed launchers in %s\n' "$PREFIX"

find_cli() {
  local candidate

  if [ -n "${FIGCRAFT_CLI:-}" ] && [ -x "$FIGCRAFT_CLI" ]; then
    printf '%s\n' "$FIGCRAFT_CLI"
    return 0
  fi

  for candidate in \
    "$PREFIX/figcraft-cli" \
    "$HOME/.local/bin/figcraft-cli" \
    /opt/homebrew/bin/figcraft-cli \
    /usr/local/bin/figcraft-cli
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v figcraft-cli 2>/dev/null || true)"
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

if [ "$WITH_CLI" -eq 1 ]; then
  ZIP="figcraft-cli-$VERSION-macos-universal.zip"
  URL="https://github.com/storytold/figcraft/releases/download/v$VERSION"
  DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/figcraft-cli/$VERSION"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/dsh-figcraft.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT

  printf 'Downloading %s (about 90 MB)\n' "$ZIP"
  curl --fail --location --silent --show-error --retry 3 \
    "$URL/$ZIP" -o "$TMP/$ZIP"
  curl --fail --location --silent --show-error --retry 3 \
    "$URL/SHA256SUMS.txt" -o "$TMP/SHA256SUMS.txt"

  expected="$(awk -v name="$ZIP" '$2 == name { print $1; exit }' "$TMP/SHA256SUMS.txt")"
  if [ -z "$expected" ]; then
    printf 'No SHA-256 entry for %s in the release checksums.\n' "$ZIP" >&2
    exit 1
  fi

  actual="$(shasum -a 256 "$TMP/$ZIP" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    printf 'Checksum mismatch for %s\n' "$ZIP" >&2
    printf 'expected %s\nactual   %s\n' "$expected" "$actual" >&2
    exit 1
  fi

  unzip -q "$TMP/$ZIP" -d "$TMP"
  mkdir -p "$DATA_DIR"
  install -m 755 "$TMP/figcraft-cli-$VERSION-macos-universal/figcraft-cli" "$DATA_DIR/figcraft-cli"
  ln -sfn "$DATA_DIR/figcraft-cli" "$PREFIX/figcraft-cli"
  printf 'Installed figcraft-cli %s at %s\n' "$VERSION" "$DATA_DIR/figcraft-cli"
else
  if cli="$(find_cli)"; then
    printf 'Using existing figcraft-cli: %s\n' "$cli"
  else
    printf 'figcraft-cli not found. Re-run with --with-cli, or install it and add it to PATH.\n' >&2
  fi
fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dsh-figcraft"
mkdir -p "$CONFIG_DIR"
install -m 644 "$ROOT/shell/figcraft.zsh" "$CONFIG_DIR/aliases.zsh"
printf 'Aliases written to %s/aliases.zsh\n' "$CONFIG_DIR"

if [ "$PREFIX" != "$HOME/.local/bin" ]; then
  printf '\nNote: figcraft-mcp searches ~/.local/bin, Homebrew prefixes and PATH.\n'
  printf 'Put %s on PATH, or point FIGCRAFT_CLI at the binary.\n' "$PREFIX"
fi

printf '\nAdd the aliases to zsh:\n'
printf '  echo '\''source "%s/aliases.zsh"'\'' >> ~/.zshrc\n' "$CONFIG_DIR"
printf 'Then start FigCraft with: figon\n'
