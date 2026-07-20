#!/usr/bin/env bash
# Instala/atualiza os aliases do dev-toolbox (git + shell).
#
# Uso:
#   ./install.sh                # instala/atualiza tudo (não interativo)
#   ./install.sh --interactive  # deixa escolher quais itens instalar
#
# Idempotente - roda de novo a qualquer momento (ex: após "git pull") pra
# sincronizar itens novos do MANIFEST.json. A seleção feita no modo interativo
# fica salva em .installed e é reaproveitada como padrão da próxima vez.
set -euo pipefail

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  GREEN=$'\e[32m'; CYAN=$'\e[36m'; YELLOW=$'\e[33m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; CYAN=""; YELLOW=""
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$ROOT/MANIFEST.json"
STATE_FILE="$ROOT/.installed"
INTERACTIVE=0
[[ "${1:-}" == "--interactive" ]] && INTERACTIVE=1

bash "$ROOT/deps.sh"
echo ""

mapfile -t ids < <(jq -r '.[].id' "$MANIFEST")
mapfile -t types < <(jq -r '.[].type' "$MANIFEST")
mapfile -t paths < <(jq -r '.[].path' "$MANIFEST")
mapfile -t entries < <(jq -r '.[].entry' "$MANIFEST")
mapfile -t descs < <(jq -r '.[].description' "$MANIFEST")

# modo nao-interativo instala/atualiza TUDO, sempre - .installed so serve de
# pre-selecao pro checklist do --interactive (respeita o que foi desmarcado
# antes), nunca pra restringir uma rodada sem --interactive. Sem isso, um
# item novo no MANIFEST.json (ex: apos "git pull") nunca seria instalado sozinho
# pra quem ja tinha um .installed de uma selecao anterior.
declare -A selected
for id in "${ids[@]}"; do selected["$id"]=1; done

if (( INTERACTIVE )) && [[ -f "$STATE_FILE" ]]; then
  selected=()
  while read -r id; do
    [[ -z "$id" ]] && continue
    selected["$id"]=1
  done < "$STATE_FILE"
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
  echo "${BOLD}${CYAN}dev-toolbox${RESET} - itens disponíveis:"
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
      echo "${YELLOW}⚠ aviso:${RESET} '$n' ignorado (não é um número válido)" >&2
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

echo "${GREEN}✔${RESET} git aliases ${GREEN}ok${RESET} ${DIM}-> $GIT_CONFIG_GENERATED (via include.path no ~/.gitconfig)${RESET}"

# --- shell (bash + zsh) - concatena itens shell selecionados num unico
# arquivo gerado (mesmo padrao do git acima). O .bashrc/.zshrc so sourca
# esse arquivo gerado (uma linha fixa, adicionada uma vez) - desmarcar um
# item some do arquivo gerado sozinho, sem precisar tocar no rc de novo.
SHELL_CONFIG_GENERATED="$ROOT/shell/aliases.local.sh"
mkdir -p "$ROOT/shell"
{
  for i in "${!ids[@]}"; do
    [[ "${types[$i]}" == "shell" && -n "${selected[${ids[$i]}]+x}" ]] || continue
    # unalias defensivo: se o shell do usuario (oh-my-zsh, rc antigo, etc)
    # ja tiver um alias com o mesmo nome, "nome() { ... }" quebra com
    # "defining function based on alias" - unalias silencioso evita isso.
    printf 'unalias %s 2>/dev/null\n' "${entries[$i]}"
    sed "s#{{ROOT}}#$ROOT#g" "$ROOT/${paths[$i]}"
    echo ""
  done
} > "$SHELL_CONFIG_GENERATED"

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || continue
  grep -qF "$SHELL_CONFIG_GENERATED" "$rc" || \
    printf '\n[ -f "%s" ] && source "%s"\n' "$SHELL_CONFIG_GENERATED" "$SHELL_CONFIG_GENERATED" >> "$rc"
done

echo "${GREEN}✔${RESET} shell aliases ${GREEN}ok${RESET} ${DIM}-> $SHELL_CONFIG_GENERATED (sourced no ~/.bashrc/~/.zshrc)${RESET}"

echo ""
echo "${GREEN}${BOLD}✔ dev-toolbox instalado/atualizado.${RESET}"
echo "${DIM}abra um novo shell (ou 'source ~/.zshrc') pra aliases de shell valerem.${RESET}"
