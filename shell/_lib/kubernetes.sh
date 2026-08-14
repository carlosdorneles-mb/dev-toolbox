# Biblioteca compartilhada de checagens Kubernetes dos scripts do
# dev-toolbox. NAO e item instalavel (fora do catalog.json) - sourced via
# {{ROOT}}/caminho relativo pelos scripts que precisam (ex:
# shell/devstack-users/impl.sh). Depende de dtb_log_err (shell/_lib/log.sh)
# ja estar sourced antes. Guard evita redefinicao caso mais de um script
# sourced na mesma sessao o faca.
#
# Uso:
#   dtb_check_kubectl_installed || exit 1
#   dtb_check_cluster "gke_mb-dev-277014_us-east4-a_mb-dev-gke" "gcloud container clusters get-credentials mb-dev-gke --zone us-east4-a --project mb-dev-277014" || exit 1
#   dtb_check_namespace_exists "$NAMESPACE" || exit 1
if [[ -z "${_DTB_KUBERNETES_LOADED:-}" ]]; then
  _DTB_KUBERNETES_LOADED=1

  dtb_check_kubectl_installed() {
    if ! command -v kubectl &> /dev/null; then
      dtb_log_err "kubectl não está instalado. Instruções: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
      return 1
    fi
  }

  # $1 = context exigido; $2 = comando sugerido pra trocar/obter credenciais
  dtb_check_cluster() {
    local required_context="$1" fix_hint="$2"
    local current_context
    current_context=$(kubectl config current-context)
    if [ "$current_context" != "$required_context" ]; then
      dtb_log_err "Cluster incorreto. Execute: $fix_hint"
      return 1
    fi
  }

  # $1 = namespace
  dtb_check_namespace_exists() {
    local namespace="$1"
    if ! kubectl get namespace "$namespace" &> /dev/null; then
      dtb_log_err "Namespace $namespace não existe. Verifique o nome do ambiente."
      return 1
    fi
  }

  # Espera um PID em background mostrando um spinner gum (gum spin não
  # repassa o stdout do comando real pro caller - poll leve de 0.1s no PID
  # resolve isso sem precisar redirecionar a saída do comando de dentro do
  # gum spin). Fora de terminal interativo ou sem gum, só dá wait direto.
  # $1 = titulo do spinner; $2 = PID
  dtb_wait_gum_pid() {
    local title="$1" pid="$2"
    if [ -t 1 ] && command -v gum >/dev/null 2>&1; then
      gum spin --spinner dot --title "$title" -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 0.1; done"
    fi
    wait "$pid" 2>/dev/null
  }

  # Busca os namespaces do cluster (kubectl em background, com spinner gum
  # via dtb_wait_gum_pid) e imprime a lista (espaço-separada) em stdout.
  # Não filtra/seleciona nada - quem chama decide a UI de seleção e a
  # mensagem de erro se vier vazio (kubectl falhou ou cluster sem
  # namespaces). $1 = titulo do spinner.
  dtb_list_namespaces() {
    local title="${1:-Buscando namespaces do cluster...}"
    local tmp list
    tmp="$(mktemp)"
    { kubectl get namespaces --request-timeout=10s -o jsonpath='{.items[*].metadata.name}' > "$tmp" 2>/dev/null & } 2>/dev/null
    dtb_wait_gum_pid "$title" "$!"
    list="$(cat "$tmp")"
    rm -f "$tmp"
    [ -z "$list" ] && return 1
    echo "$list"
  }
fi
