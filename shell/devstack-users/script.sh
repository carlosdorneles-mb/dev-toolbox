# Comando "devstack-users": navega usuários/subwallets/saldos do devstack
# via port-forward direto aos bancos do namespace Kubernetes (MySQL +
# PostgreSQL), em interface fzf interativa; permite editar dados do
# usuário e saldos.
#
# A lógica real mora em impl.sh, executado como PROCESSO SEPARADO (nao
# sourced) - script.sh (este arquivo) e concatenado literalmente no
# aliases.local.sh e roda dentro do shell interativo do usuario, entao nao
# pode ter "exit" nem "trap ... EXIT" (mataria o shell/ficaria pendurado -
# ver AGENTS.md). O impl.sh precisa dos dois: ele sobe dois
# "kubectl port-forward" em background por vários minutos (sessão fzf
# inteira) e conta com "trap cleanup EXIT" pra matá-los e limpar tmpfiles
# de qualquer jeito que o processo termine (fim normal, erro, Ctrl-C) -
# isso só funciona com semântica de processo real, "trap ... RETURN" não é
# portável pra zsh (testado: "trap: undefined signal: RETURN").
#
# Uso: devstack-users [namespace] [filtro]
# Uso: devstack-users -n <namespace> [-f <filtro>]
# Uso: devstack-users -h | --help
_dtb_help_devstack_users() {
  if command -v glow >/dev/null 2>&1; then
    glow -w 0 "{{ROOT}}/shell/devstack-users/README.md"
  else
    cat "{{ROOT}}/shell/devstack-users/README.md"
  fi
}

devstack-users() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help) _dtb_help_devstack_users; return 0 ;;
    esac
  done

  bash "{{ROOT}}/shell/devstack-users/impl.sh" "$@"
}
