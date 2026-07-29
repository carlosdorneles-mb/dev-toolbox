#!/usr/bin/env bash
# Entrypoint pra instalação via curl:
#
#   curl -fsSL https://raw.githubusercontent.com/<org>/dev-toolbox/main/bootstrap.sh | bash
#
# Clona (ou atualiza) o dev-toolbox em $DEV_TOOLBOX_DIR (padrão ~/.dev-toolbox)
# e chama install.sh em modo interativo, deixando escolher quais aliases
# instalar. Reexecutar o mesmo comando depois só atualiza (git pull) e
# reabre a seleção, com o que já estava instalado pré-marcado.
#
# Pra instalar tudo direto, sem menu interativo (ex: provisionamento
# automatizado), passe --all depois do "--" do bash:
#
#   curl -fsSL https://raw.githubusercontent.com/<org>/dev-toolbox/main/bootstrap.sh | bash -s -- --all
#
# Pra atualizar sem menu, reaplicando a seleção já instalada (usado pelo
# comando "update"), passe --update:
#
#   curl -fsSL https://raw.githubusercontent.com/<org>/dev-toolbox/main/bootstrap.sh | bash -s -- --update
#
# --quiet some junto com --all/--update - silencia a saída informativa
# (própria e do install.sh; erros continuam aparecendo):
#
#   curl -fsSL https://raw.githubusercontent.com/<org>/dev-toolbox/main/bootstrap.sh | bash -s -- --update --quiet
set -euo pipefail

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\e[1m'; RESET=$'\e[0m'; CYAN=$'\e[36m'
else
  BOLD=""; RESET=""; CYAN=""
fi

REPO_URL="${DEV_TOOLBOX_REPO_URL:-https://github.com/carlosdorneles-mb/dev-toolbox.git}"
INSTALL_DIR="${DEV_TOOLBOX_DIR:-$HOME/.dev-toolbox}"

MODE="interactive"
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --all) MODE="all" ;;
    --update) MODE="update" ;;
    -q|--quiet) QUIET=1 ;;
  esac
done

if [[ -d "$INSTALL_DIR/.git" ]]; then
  (( QUIET )) || echo "${CYAN}↻${RESET} ${BOLD}dev-toolbox${RESET} já clonado em $INSTALL_DIR - atualizando..."
  git -C "$INSTALL_DIR" pull --quiet
else
  (( QUIET )) || echo "${CYAN}⇣${RESET} clonando ${BOLD}dev-toolbox${RESET} em $INSTALL_DIR..."
  git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

case "$MODE" in
  all)
    if (( QUIET )); then exec bash "$INSTALL_DIR/install.sh" --quiet; else exec bash "$INSTALL_DIR/install.sh"; fi
    ;;
  update)
    if (( QUIET )); then exec bash "$INSTALL_DIR/install.sh" --update --quiet; else exec bash "$INSTALL_DIR/install.sh" --update; fi
    ;;
  *)
    exec bash "$INSTALL_DIR/install.sh" --interactive
    ;;
esac
