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

# seleção via fzf (checklist navegável, TAB marca/desmarca, ENTER confirma) -
# so usada se `fzf` estiver instalado; senao cai no prompt numerico simples.
# mesma binaria fzf funciona em mac e linux (brew/apt/pacman), sem diferenca
# de comportamento entre os dois.
_select_with_fzf() {
  local -a chosen
  local line id

  mapfile -t chosen < <(
    for i in "${!ids[@]}"; do
      printf '%s\t%s\n' "${ids[$i]}" "${descs[$i]}"
    done | fzf --multi \
                --delimiter='\t' \
                --with-nth=1,2 \
                --prompt='dev-toolbox> ' \
                --header='TAB: marca/desmarca | CTRL-A: marca tudo | CTRL-D: desmarca tudo | ENTER: confirma | ESC: mantem selecao atual' \
                --bind='ctrl-a:select-all,ctrl-d:deselect-all' \
                --height='~60%' \
                --layout=reverse \
      | cut -f1
  ) || true

  (( ${#chosen[@]} == 0 )) && return

  selected=()
  for id in "${chosen[@]}"; do selected["$id"]=1; done
}

# fallback sem dependencia externa - lista enumerada + prompt de numeros
# separados por virgula.
_select_with_prompt() {
  local i choice n idx k
  local -A new_selected

  echo ""
  echo "dev-toolbox - itens disponíveis:"
  echo ""

  for i in "${!ids[@]}"; do
    printf "  %2d) %-10s %s\n" "$((i+1))" "${ids[$i]}" "${descs[$i]}"
  done

  echo ""
  choice=""
  read -r -p "Números dos itens que deseja instalar (separados por vírgula): " choice < /dev/tty || true

  [[ -z "$choice" ]] && return

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
}

if (( INTERACTIVE )); then
  if command -v fzf &>/dev/null; then
    _select_with_fzf
  else
    _select_with_prompt
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
