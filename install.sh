#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${CLAUDE_HOME:-$HOME/.claude}"
force=0

if [[ "${1:-}" == "--force" ]]; then
  force=1
fi

install_file() {
  local src="$1" dest="$2"
  if [[ -e "$dest" && $force -eq 0 ]]; then
    echo "esiste già: $dest (usa --force per sovrascrivere)" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "installato: $dest"
}

status=0
install_file "$root/commands/octopus.md" "$target/commands/octopus.md" || status=1
for agent in "$root"/agents/*.md; do
  install_file "$agent" "$target/agents/$(basename "$agent")" || status=1
done

exit "$status"
