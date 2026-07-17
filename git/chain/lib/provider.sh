#!/bin/bash
# dispatcher de provider de PR (GitHub hoje, GitLab/outros no futuro).
# Interface generica usada pelo script principal - so ela, nunca "gh"/"jq"
# direto - pra suportar outro host de PR sem tocar script.sh:
#   pr_provider_available            -> bool
#   pr_provider_deps_hint            -> mensagem em stderr do que falta
#   pr_provider_fetch_pr_info <b>    -> popula as arrays pr_* pra branch b
#   pr_provider_resolve_pr_branch <n> -> numero de PR -> nome da branch
#   pr_provider_label                -> nome do provider p/ mensagens (ex: "GitHub CLI")
#
# Adicionar um novo provider:
#   1. criar lib/providers/<nome>.sh com as funcoes <nome>_available,
#      <nome>_deps_hint, <nome>_fetch_pr_info, <nome>_resolve_pr_branch,
#      seguindo a mesma assinatura do lib/providers/github.sh
#   2. adicionar o "source" abaixo e um caso no PR_PROVIDER (deteccao
#      automatica por remote, ou variavel de ambiente GIT_CHAIN_PROVIDER)

_provider_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers"

source "$_provider_lib_dir/github.sh"

# hoje so existe o provider github - quando houver mais de um, decidir aqui
# (ex: por host do remote, ou GIT_CHAIN_PROVIDER=gitlab explicito)
PR_PROVIDER="${GIT_CHAIN_PROVIDER:-github}"

pr_provider_available() {
  case "$PR_PROVIDER" in
    github) github_available ;;
    *) return 1 ;;
  esac
}

pr_provider_deps_hint() {
  case "$PR_PROVIDER" in
    github) github_deps_hint ;;
  esac
}

pr_provider_fetch_pr_info() {
  case "$PR_PROVIDER" in
    github) github_fetch_pr_info "$1" ;;
  esac
}

pr_provider_resolve_pr_branch() {
  case "$PR_PROVIDER" in
    github) github_resolve_pr_branch "$1" ;;
  esac
}

pr_provider_label() {
  case "$PR_PROVIDER" in
    github) echo "$github_name_label" ;;
    *) echo "$PR_PROVIDER" ;;
  esac
}
