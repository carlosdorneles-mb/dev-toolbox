#!/usr/bin/env bash
# Instala/atualiza os aliases do dev-toolbox (git + shell).
#
# Uso:
#   ./install.sh                # instala/atualiza tudo (não interativo)
#   ./install.sh --interactive  # deixa escolher quais itens instalar
#   ./install.sh --update       # reaplica a seleção salva em .installed (+ itens novos do catalog), sem forçar tudo - usado pelo comando "update"
#   ./install.sh -q | --quiet   # some junto com qualquer flag acima - silencia a saída informativa (erros continuam aparecendo)
#   ./install.sh --skip-deps    # some junto com qualquer flag acima - pula a checagem/instalação de dependências (jq/gum/glow/gh)
#
# Idempotente - roda de novo a qualquer momento (ex: após "git pull") pra
# sincronizar itens novos do catalog.json. A seleção feita no modo interativo
# fica salva em .installed e é reaproveitada como padrão da próxima vez.
set -euo pipefail

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  GREEN=$'\e[32m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="$ROOT/catalog.json"
STATE_FILE="$ROOT/.installed"
INTERACTIVE=0
UPDATE_MODE=0
QUIET=0
SKIP_DEPS=0
for arg in "$@"; do
  case "$arg" in
    --interactive) INTERACTIVE=1 ;;
    --update) UPDATE_MODE=1 ;;
    -q|--quiet) QUIET=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
  esac
done

_log() { (( QUIET )) && return; printf '%s\n' "$*"; }

if (( SKIP_DEPS )); then
  _log "${DIM}pulando checagem de dependências (--skip-deps)${RESET}"
elif (( QUIET )); then
  bash "$ROOT/deps.sh" >/dev/null
else
  bash "$ROOT/deps.sh"
  echo ""
fi

mapfile -t ids < <(jq -r '.[].id' "$CATALOG")
mapfile -t types < <(jq -r '.[].type' "$CATALOG")
mapfile -t paths < <(jq -r '.[].path' "$CATALOG")
mapfile -t entries < <(jq -r '.[].entry' "$CATALOG")
mapfile -t descs < <(jq -r '.[].description' "$CATALOG")

# modo padrao (sem flag): instala/atualiza TUDO, sempre.
# --update: reaproveita a selecao salva em .installed (respeita o que foi
# desmarcado antes) e soma automaticamente qualquer item novo do catalog.json
# que ainda nao apareca no arquivo - assim um item novo (ex: apos "git pull")
# entra sozinho, mas um item desmarcado continua desmarcado.
# --interactive: usa .installed so como pre-selecao pro checklist (abaixo).
declare -A selected
for id in "${ids[@]}"; do selected["$id"]=1; done

if (( UPDATE_MODE )) && [[ -f "$STATE_FILE" ]]; then
  selected=()
  while read -r id; do
    [[ -z "$id" ]] && continue
    selected["$id"]=1
  done < "$STATE_FILE"
  for id in "${ids[@]}"; do
    grep -qxF "$id" "$STATE_FILE" || selected["$id"]=1
  done
fi

if (( INTERACTIVE )) && [[ -f "$STATE_FILE" ]]; then
  selected=()
  while read -r id; do
    [[ -z "$id" ]] && continue
    selected["$id"]=1
  done < "$STATE_FILE"
fi

_select_with_gum() {
  local -a display_lines chosen
  local i max_id=0 line id

  for i in "${!ids[@]}"; do
    (( ${#ids[$i]} > max_id )) && max_id=${#ids[$i]}
  done
  for i in "${!ids[@]}"; do
    display_lines+=("$(printf '%-*s  %s' "$max_id" "${ids[$i]}" "${descs[$i]}")")
  done

  mapfile -t chosen < <(
    printf '%s\n' "${display_lines[@]}" | gum choose --no-limit \
      --header='espaço marca/desmarca | enter confirma | esc mantém seleção anterior'
  ) || true

  (( ${#chosen[@]} == 0 )) && return

  selected=()
  for line in "${chosen[@]}"; do
    for i in "${!display_lines[@]}"; do
      if [[ "${display_lines[$i]}" == "$line" ]]; then
        selected["${ids[$i]}"]=1
        break
      fi
    done
  done
}

(( INTERACTIVE )) && _select_with_gum

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

_log "${GREEN}✔${RESET} git aliases ${GREEN}ok${RESET} ${DIM}-> $GIT_CONFIG_GENERATED (via include.path no ~/.gitconfig)${RESET}"

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

_log "${GREEN}✔${RESET} shell aliases ${GREEN}ok${RESET} ${DIM}-> $SHELL_CONFIG_GENERATED (sourced no ~/.bashrc/~/.zshrc)${RESET}"

if ! (( QUIET )); then
  echo ""
  echo "${BOLD}Comandos instalados:${RESET}"
  echo "${DIM}git:${RESET}"
  for i in "${!ids[@]}"; do
    [[ "${types[$i]}" == "git" && -n "${selected[${ids[$i]}]+x}" ]] || continue
    printf "  %-15s %s\n" "git ${entries[$i]}" "${descs[$i]}"
  done
  echo "${DIM}shell:${RESET}"
  for i in "${!ids[@]}"; do
    [[ "${types[$i]}" == "shell" && -n "${selected[${ids[$i]}]+x}" ]] || continue
    printf "  %-15s %s\n" "${entries[$i]}" "${descs[$i]}"
  done
fi

_log ""
_log "${GREEN}${BOLD}✔ dev-toolbox instalado/atualizado.${RESET}"
_log "${DIM}abra um novo shell (ou 'source ~/.zshrc') pra aliases de shell valerem.${RESET}"
