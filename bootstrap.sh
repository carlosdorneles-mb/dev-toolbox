#!/usr/bin/env bash
# Entrypoint pra instalação via curl:
#
#   curl -fsSL https://raw.githubusercontent.com/<org>/dev-toolbox/main/bootstrap.sh | bash
#
# Clona (ou atualiza) o dev-toolbox em $DEV_TOOLBOX_DIR (padrão ~/.dev-toolbox)
# e chama install.sh em modo interativo, deixando escolher quais aliases
# instalar. Reexecutar o mesmo comando depois só atualiza (git pull) e
# reabre a seleção, com o que já estava instalado pré-marcado.
set -euo pipefail

REPO_URL="${DEV_TOOLBOX_REPO_URL:-https://github.com/carlosdorneles-mb/dev-toolbox.git}"
INSTALL_DIR="${DEV_TOOLBOX_DIR:-$HOME/.dev-toolbox}"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "dev-toolbox já clonado em $INSTALL_DIR - atualizando..."
  git -C "$INSTALL_DIR" pull --quiet
else
  echo "clonando dev-toolbox em $INSTALL_DIR..."
  git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

exec bash "$INSTALL_DIR/install.sh" --interactive
