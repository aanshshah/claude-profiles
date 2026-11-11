#!/usr/bin/env bash
# Links bin/claude-profile into $PREFIX (default ~/.local/bin) and prints the shell setup line.
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/bin}"
SRC="$(cd "$(dirname "$0")" && pwd -P)/bin/claude-profile"
DEST="$PREFIX/claude-profile"

for dep in jq git claude; do
  command -v "$dep" >/dev/null 2>&1 || echo "warning: $dep not found on PATH; claude-profile needs it" >&2
done

mkdir -p "$PREFIX"
if [[ -e "$DEST" && ! -L "$DEST" ]]; then
  mv "$DEST" "$DEST.bak"
  echo "Moved existing $DEST to $DEST.bak"
fi
ln -sfn "$SRC" "$DEST"
echo "Linked $DEST -> $SRC"

case ":$PATH:" in *":$PREFIX:"*) ;; *) echo "warning: $PREFIX is not on PATH" >&2 ;; esac

cat <<EOF

Add this line to ~/.zshrc or ~/.bashrc, then open a new shell:

  eval "\$(claude-profile shell-init)"
EOF
