# Biblioteca compartilhada de cores/log dos scripts de shell do dev-toolbox.
# NÃO é um item instalável (fora do catalog.json) - é sourced via {{ROOT}} pelos
# scripts que precisam ("source '{{ROOT}}/shell/_lib/log.sh'" dentro da
# função, {{ROOT}} vira path absoluto na hora do install.sh). Guard evita
# redefinição caso mais de um script sourced na mesma sessão o faça.
#
# Convenção de cor (mesma em todo o dev-toolbox): desliga cores se stdout
# não for terminal ou se NO_COLOR estiver setado.
if [[ -z "${_DTB_LOG_LOADED:-}" ]]; then
  _DTB_LOG_LOADED=1

  _DTB_RED="" _DTB_GREEN="" _DTB_YELLOW="" _DTB_BLUE="" _DTB_CYAN="" _DTB_GRAY="" _DTB_BOLD="" _DTB_RESET=""
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    _DTB_RED=$'\033[0;31m'
    _DTB_GREEN=$'\033[0;32m'
    _DTB_YELLOW=$'\033[0;33m'
    _DTB_BLUE=$'\033[0;34m'
    _DTB_CYAN=$'\033[1;36m'
    _DTB_GRAY=$'\033[1;90m'
    _DTB_BOLD=$'\033[1m'
    _DTB_RESET=$'\033[0m'
  fi

  # dtb_log_step "Atualizando X..."   -> cabeçalho de etapa (bold cyan)
  dtb_log_step()   { echo -e "${_DTB_CYAN}> $*${_DTB_RESET}"; }
  # dtb_log_ok "X atualizado."        -> sucesso (green)
  dtb_log_ok()     { echo -e "${_DTB_GREEN}$*${_DTB_RESET}"; }
  # dtb_log_warn "X pendente."        -> alerta (yellow)
  dtb_log_warn()   { echo -e "${_DTB_YELLOW}$*${_DTB_RESET}"; }
  # dtb_log_skip "Pulando X."         -> etapa pulada (gray)
  dtb_log_skip()   { echo -e "${_DTB_GRAY}$*${_DTB_RESET}"; }
  # dtb_log_err "Falha em X."         -> erro (red)
  dtb_log_err()    { echo -e "${_DTB_RED}$*${_DTB_RESET}"; }
  # dtb_log_banner "Concluído!"       -> banner inicial/final (bold, sem cor)
  dtb_log_banner() { echo -e "${_DTB_BOLD}$*${_DTB_RESET}"; }
fi
