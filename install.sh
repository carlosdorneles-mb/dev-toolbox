#!/usr/bin/env bash
# Instala/atualiza os aliases do dev-toolbox (git + shell).
#
# Uso:
#   ./install.sh                # instala/atualiza tudo (não interativo)
#   ./install.sh --interactive  # deixa escolher quais itens instalar
#
# Idempotente - roda de novo a qualquer momento (ex: após "git pull") pra
# sincronizar itens novos do MANIFEST. A seleção feita no modo interativo
# fica salva em .installed e é reaproveitada como padrão da próxima vez.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$ROOT/MANIFEST"
STATE_FILE="$ROOT/.installed"
INTERACTIVE=0
[[ "${1:-}" == "--interactive" ]] && INTERACTIVE=1

ids=()
types=()
paths=()
descs=()

while IFS='|' read -r id type path _entry desc || [[ -n "$id" ]]; do
  [[ -z "$id" || "$id" == \#* ]] && continue

  ids+=("$id")
  types+=("$type")
  paths+=("$path")
  descs+=("$desc")
done < "$MANIFEST"

declare -A selected
if [[ -f "$STATE_FILE" ]]; then
  while read -r id; do
    [[ -z "$id" ]] && continue
    selected["$id"]=1
  done < "$STATE_FILE"
else
  for id in "${ids[@]}"; do selected["$id"]=1; done
fi

if (( INTERACTIVE )); then
  echo ""
  echo "dev-toolbox - selecione os itens (números separados por espaço/vírgula, 'a' = todos, enter = manter seleção atual):"
  echo ""

  for i in "${!ids[@]}"; do
    mark=" "
    [[ -n "${selected[${ids[$i]}]+x}" ]] && mark="x"
    printf "  [%s] %2d) %-10s %s\n" "$mark" "$((i+1))" "${ids[$i]}" "${descs[$i]}"
  done

  echo ""
  choice=""
  read -r -p "> " choice < /dev/tty || true

  if [[ -n "$choice" ]]; then
    if [[ "$choice" == "a" || "$choice" == "all" ]]; then
      for id in "${ids[@]}"; do selected["$id"]=1; done
    else
      declare -A new_selected
      choice="${choice//,/ }"
      for n in $choice; do
        if [[ ! "$n" =~ ^[0-9]+$ ]]; then
          echo "aviso: '$n' ignorado (não é um número válido)" >&2
          continue
        fi

        idx=$((n - 1))
        (( idx >= 0 && idx < ${#ids[@]} )) && new_selected["${ids[$idx]}"]=1
      done
      selected=()
      for k in "${!new_selected[@]}"; do selected["$k"]=1; done
    fi
  fi
fi

: > "$STATE_FILE"
for id in "${!selected[@]}"; do echo "$id" >> "$STATE_FILE"; done

# --- git: concatena fragments selecionados num único [alias] ---
GIT_CONFIG_GENERATED="$ROOT/git/aliases.local.gitconfig"
{
  echo "[alias]"
  for i in "${!ids[@]}"; do
    [[ "${types[$i]}" == "git" && -n "${selected[${ids[$i]}]+x}" ]] || continue
    sed "s#{{ROOT}}#$ROOT#g" "$ROOT/${paths[$i]}"
  done
} > "$GIT_CONFIG_GENERATED"

if ! grep -qF "$GIT_CONFIG_GENERATED" "$HOME/.gitconfig" 2>/dev/null; then
  git config --global --add include.path "$GIT_CONFIG_GENERATED"
fi

echo "git aliases ok -> $GIT_CONFIG_GENERATED (via include.path no ~/.gitconfig)"

# --- shell (bash + zsh) - dá source em cada arquivo shell selecionado ---
for i in "${!ids[@]}"; do
  [[ "${types[$i]}" == "shell" && -n "${selected[${ids[$i]}]+x}" ]] || continue

  f="$ROOT/${paths[$i]}"
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    grep -qF "$f" "$rc" || printf '\n[ -f "%s" ] && source "%s"\n' "$f" "$f" >> "$rc"
  done
done

echo "dev-toolbox instalado/atualizado."
echo "abra um novo shell (ou 'source ~/.zshrc') pra aliases de shell valerem."
