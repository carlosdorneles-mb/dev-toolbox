# Biblioteca compartilhada de checagem de clientes de banco (psql/mysql)
# dos scripts do dev-toolbox. NAO e item instalavel (fora do catalog.json)
# - sourced via {{ROOT}}/caminho relativo pelos scripts que precisam (ex:
# shell/devstack-users/impl.sh). Depende de dtb_log_err (shell/_lib/log.sh)
# ja estar sourced antes. Guard evita redefinicao caso mais de um script
# sourced na mesma sessao o faca.
#
# Uso:
#   dtb_check_psql_installed || exit 1
#   dtb_check_mysql_installed || exit 1
if [[ -z "${_DTB_DB_CLIENTS_LOADED:-}" ]]; then
  _DTB_DB_CLIENTS_LOADED=1

  dtb_check_psql_installed() {
    if ! command -v psql &> /dev/null; then
      dtb_log_err "psql não está instalado. Execute:"
      if [[ "$(uname)" == "Darwin" ]]; then
        dtb_log_err "  brew install libpq && brew link --force libpq"
      else
        dtb_log_err "  sudo apt-get install -y postgresql-client"
      fi
      return 1
    fi
  }

  dtb_check_mysql_installed() {
    if ! command -v mysql &> /dev/null; then
      dtb_log_err "mysql não está instalado. Execute:"
      if [[ "$(uname)" == "Darwin" ]]; then
        dtb_log_err "  brew install mysql-client && echo 'export PATH=\"\$(brew --prefix mysql-client)/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
      else
        dtb_log_err "  sudo apt-get install -y mysql-client"
      fi
      return 1
    fi
  }
fi
