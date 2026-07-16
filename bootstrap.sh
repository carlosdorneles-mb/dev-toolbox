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
set -euo pipefail

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\e[1m'; RESET=$'\e[0m'; CYAN=$'\e[36m'
else
  BOLD=""; RESET=""; CYAN=""
fi

REPO_URL="${DEV_TOOLBOX_REPO_URL:-https://github.com/carlosdorneles-mb/dev-toolbox.git}"
INSTALL_DIR="${DEV_TOOLBOX_DIR:-$HOME/.dev-toolbox}"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "${CYAN}↻${RESET} ${BOLD}dev-toolbox${RESET} já clonado em $INSTALL_DIR - atualizando..."
  git -C "$INSTALL_DIR" pull --quiet
else
  echo "${CYAN}⇣${RESET} clonando ${BOLD}dev-toolbox${RESET} em $INSTALL_DIR..."
  git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

if [[ "${1:-}" == "--all" ]]; then
  exec bash "$INSTALL_DIR/install.sh"
else
  exec bash "$INSTALL_DIR/install.sh" --interactive
fi
