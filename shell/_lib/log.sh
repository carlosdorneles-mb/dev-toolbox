# Biblioteca compartilhada de cores/log dos scripts de shell do dev-toolbox.
# NÃO é um item instalável (fora do catalog.json) - é sourced via {{ROOT}} pelos
# scripts que precisam ("source '{{ROOT}}/shell/_lib/log.sh'" dentro da
# função, {{ROOT}} vira path absoluto na hora do install.sh). Guard evita
# redefinição caso mais de um script sourced na mesma sessão o faça.
#
# Convenção de cor (mesma em todo o dev-toolbox): desliga cores se stdout
# não for terminal ou se NO_COLOR estiver setado.
#
# gum e obrigatorio em terminal interativo pra quem de fato usa
# dtb_log_*/dtb_run_step (update, fix-network) - a checagem fica no
# proprio script que usa, nao aqui, porque scripts que so sourciam log.sh
# pelas cores (aliases, kinfo) nao devem travar por causa de gum quando
# nem chamam essas funcoes.
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

  _DTB_IS_TTY=0
  [[ -t 1 ]] && _DTB_IS_TTY=1

  # dtb_log_step "Atualizando X..."   -> cabeçalho de etapa (bold cyan)
  dtb_log_step()   { (( _DTB_IS_TTY )) && { gum log -l info "$*"; return; }; echo -e "${_DTB_CYAN}> $*${_DTB_RESET}"; }
  # dtb_log_ok "X atualizado."        -> sucesso (green)
  dtb_log_ok()     { (( _DTB_IS_TTY )) && { gum log -l info "$*"; return; }; echo -e "${_DTB_GREEN}$*${_DTB_RESET}"; }
  # dtb_log_warn "X pendente."        -> alerta (yellow)
  dtb_log_warn()   { (( _DTB_IS_TTY )) && { gum log -l warn "$*"; return; }; echo -e "${_DTB_YELLOW}$*${_DTB_RESET}"; }
  # dtb_log_skip "Pulando X."         -> etapa pulada (gray)
  dtb_log_skip()   { (( _DTB_IS_TTY )) && { gum log -l info "$*"; return; }; echo -e "${_DTB_GRAY}$*${_DTB_RESET}"; }
  # dtb_log_err "Falha em X."         -> erro (red)
  dtb_log_err()    { (( _DTB_IS_TTY )) && { gum log -l error "$*"; return; }; echo -e "${_DTB_RED}$*${_DTB_RESET}"; }
  # dtb_log_banner "Concluído!"       -> banner inicial/final (bold, sem cor,
  # nunca via gum log - e cabecalho de secao, nao mensagem de log)
  dtb_log_banner() { echo -e "${_DTB_BOLD}$*${_DTB_RESET}"; }

  # dtb_run_step "Titulo" <comando> [args...]  -> em terminal, spinner
  # (gum, obrigatorio - ver checagem no topo do arquivo) com o titulo
  # enquanto o comando roda, saida escondida (só aparece se falhar, via
  # --show-error); sem terminal, dtb_log_step + comando com saida visivel
  # de sempre. Uso: dtb_run_step "Atualizando X..." bash -c '...'
  dtb_run_step() {
    local title="$1"; shift
    if (( _DTB_IS_TTY )); then
      if gum spin --spinner dot --title "$title" --show-error -- "$@"; then
        dtb_log_ok "$title"
      else
        dtb_log_err "$title - falhou (ver saída acima)"
        return 1
      fi
    else
      dtb_log_step "$title"
      "$@"
    fi
  }
fi
