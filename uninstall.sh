#!/usr/bin/env bash
# Remove os aliases do dev-toolbox instalados a partir DESTE clone (inverso
# do install.sh). Uso comum: antes de mover/apagar o clone, ou pra evitar
# aliases duplicados quando o clone muda de path.
#
# Uso:
#   ./uninstall.sh
#
# Ou via curl, sem clone local (usa $DEV_TOOLBOX_DIR, padrão ~/.dev-toolbox):
#   curl -fsSL https://raw.githubusercontent.com/carlosdorneles-mb/dev-toolbox/main/uninstall.sh | bash
#
# Remove:
# - o "include.path" do ~/.gitconfig que aponta pro git/aliases.local.gitconfig
#   deste clone
# - a linha de source do ~/.bashrc/~/.zshrc que aponta pro
#   shell/aliases.local.sh deste clone
# - os arquivos gerados (git/aliases.local.gitconfig, shell/aliases.local.sh)
#   e o .installed (estado de seleção)
#
# Idempotente - pode rodar de novo sem erro se já tiver sido desinstalado.
# Só afeta entradas apontando pra este clone (este $ROOT) - se você já rodou
# o install.sh a partir de outros clones/paths (ou de um path antigo que já
# não existe mais), rode ./uninstall.sh a partir de cada um deles, ou remova
# a mão a linha correspondente do ~/.gitconfig/~/.bashrc/~/.zshrc.
set -euo pipefail

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  GREEN=$'\e[32m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""
fi

# Rodando via "curl | bash", BASH_SOURCE[0] não aponta pra um arquivo real -
# nesse caso cai pro clone padrão do bootstrap.sh ($DEV_TOOLBOX_DIR).
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  ROOT="${DEV_TOOLBOX_DIR:-$HOME/.dev-toolbox}"
fi
GIT_CONFIG_GENERATED="$ROOT/git/aliases.local.gitconfig"
SHELL_CONFIG_GENERATED="$ROOT/shell/aliases.local.sh"

# escapa metacaracteres de regex ERE (usados no --unset-all do git config)
_regex_escape() {
  printf '%s' "$1" | sed -e 's/[.[\*^$\\]/\\&/g'
}

# --- git: remove o include.path deste clone do ~/.gitconfig ---
if git config --global --get-all include.path 2>/dev/null | grep -qxF "$GIT_CONFIG_GENERATED"; then
  git config --global --unset-all include.path "^$(_regex_escape "$GIT_CONFIG_GENERATED")$"
  echo "${GREEN}✔${RESET} include.path removido do ~/.gitconfig"
else
  echo "${DIM}- nenhum include.path deste clone no ~/.gitconfig (nada a remover)${RESET}"
fi

# --- shell: remove a linha de source do ~/.bashrc/~/.zshrc ---
# grep -v com match exato (sem regex) - mais simples e portavel que sed -i
# entre GNU/BSD, que tem sintaxe incompativel pro "-i"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || continue
  if grep -qF "$SHELL_CONFIG_GENERATED" "$rc"; then
    tmp="$(mktemp)"
    grep -vF "$SHELL_CONFIG_GENERATED" "$rc" > "$tmp"
    mv "$tmp" "$rc"
    echo "${GREEN}✔${RESET} linha de source removida de $rc"
  else
    echo "${DIM}- nenhuma linha deste clone em $rc (nada a remover)${RESET}"
  fi
done

# --- arquivos gerados + estado local (gitignored, seguro remover) ---
rm -f "$GIT_CONFIG_GENERATED" "$SHELL_CONFIG_GENERATED" "$ROOT/.installed"

echo ""
echo "${BOLD}${GREEN}✔ dev-toolbox desinstalado deste clone.${RESET}"
echo "${DIM}abra um novo shell (ou 'source ~/.zshrc') pros aliases sumirem da sessão atual também.${RESET}"
