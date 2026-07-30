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
fi
