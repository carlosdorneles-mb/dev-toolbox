# Comando "devstack-rollout-crash-pods": reinicia (rollout restart) os
# deployments de um namespace que tenham pods em crash/erro, ou pods
# "Running" com READY incompleto (ex: 0/1 em vez de 1/1).
#
# Uso: devstack-rollout-crash-pods [ambiente]
# Uso: devstack-rollout-crash-pods -n <ambiente>
# Uso: devstack-rollout-crash-pods -h | --help
_dtb_help_devstack_rollout_crash_pods() {
  cat <<'EOF'
devstack-rollout-crash-pods - reinicia deployments com pods em crash ou READY incompleto num namespace

Uso:
  devstack-rollout-crash-pods [ambiente]
  devstack-rollout-crash-pods -n <ambiente>

Descrição:
  Varre o namespace por pods fora de Running/Terminating/PodInitializing/
  Completed/ContainerCreating (crash/erro) e por pods Running com READY
  diferente do total (ex: 0/1). Junta os deployments únicos encontrados,
  confirma e roda "kubectl rollout restart" em cada um; ao final, oferece
  entrar em modo watch pra acompanhar o rollout.

Opções:
  -n, --namespace <ns>   namespace do Kubernetes (alternativa ao posicional)
  -h                      mostra esta ajuda
EOF
}

# Deployments com pod fora dos estados "saudáveis" (crash/erro) - nome do
# deployment derivado removendo o sufixo "-<replicaset>-<pod>" do pod.
_dtb_devstack_rollout_crash_pods_get_crash() {
  local namespace="$1"
  kubectl get pods -n "$namespace" --no-headers 2>/dev/null \
    | grep -v -E "(Running|Terminating|PodInitializing|Completed|ContainerCreating)" \
    | awk '{ d = $1; sub(/-[^-]*-[^-]*$/, "", d); print d }' \
    | sort -u
}

# Deployments com pod Running mas READY diferente do total (ex: 0/1 em vez
# de 1/1) - candidatos a rollout mesmo sem estarem tecnicamente em crash.
_dtb_devstack_rollout_crash_pods_get_ready_mismatch() {
  local namespace="$1"
  kubectl get pods -n "$namespace" --no-headers 2>/dev/null | awk '
    $3 == "Running" && $2 ~ /\// {
      split($2, ready, "/")
      if (ready[1] == ready[2] || ready[1] == "" || ready[2] == "") next
      d = $1
      sub(/-[^-]*-[^-]*$/, "", d)
      print d
    }' | sort -u
}

devstack-rollout-crash-pods() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help) _dtb_help_devstack_rollout_crash_pods; return 0 ;;
    esac
  done

  source "{{ROOT}}/shell/_lib/log.sh"
  source "{{ROOT}}/shell/_lib/kubernetes.sh"

  local _dtb_arg_namespace="" _dtb_positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--namespace) _dtb_arg_namespace="$2"; shift 2 ;;
      *) _dtb_positional+=("$1"); shift ;;
    esac
  done

  dtb_check_kubectl_installed || return 1
  dtb_check_cluster "gke_mb-dev-277014_us-east4-a_mb-dev-gke" \
    "gcloud container clusters get-credentials mb-dev-gke --zone us-east4-a --project mb-dev-277014" || return 1

  local NAMESPACE="${_dtb_arg_namespace:-${_dtb_positional[0]:-}}"
  if [ -z "$NAMESPACE" ] && [ -t 1 ] && command -v gum >/dev/null 2>&1; then
    NAMESPACE=$(gum input --header="Ambiente (namespace) do Kubernetes:" --placeholder="ex: staging")
  fi
  if [ -z "$NAMESPACE" ]; then
    dtb_log_err "O nome do ambiente (namespace) é obrigatório."
    echo "Uso: devstack-rollout-crash-pods [ambiente]"
    return 1
  fi

  dtb_check_namespace_exists "$NAMESPACE" || return 1

  local deployments_crash deployments_ready_mismatch deployments_to_restart
  deployments_crash="$(_dtb_devstack_rollout_crash_pods_get_crash "$NAMESPACE")"
  deployments_ready_mismatch="$(_dtb_devstack_rollout_crash_pods_get_ready_mismatch "$NAMESPACE")"
  deployments_to_restart="$(printf '%s\n%s\n' "$deployments_crash" "$deployments_ready_mismatch" | grep -v '^$' | sort -u)"

  if [ -z "$deployments_to_restart" ]; then
    dtb_log_ok "Nenhum pod em crash e nenhum Running com READY incompleto em '$NAMESPACE'."
    return 0
  fi

  echo -e "\n${_DTB_RED}Deployments encontrados com problema:${_DTB_RESET}"
  echo "$deployments_to_restart"
  if [ -n "$deployments_ready_mismatch" ]; then
    echo -e "\n${_DTB_YELLOW}Incluídos: pod(s) Running com READY ≠ total (ex: não 1/1):${_DTB_RESET}"
    echo "$deployments_ready_mismatch"
  fi

  echo
  local confirm
  read -r -p "Confirmar rollout restart dos deployments acima em '$NAMESPACE'? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operação cancelada."
    return 0
  fi

  dtb_log_step "Iniciando rollout dos deployments..."
  local dep grep_filter=""
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    if kubectl rollout restart "deployment/$dep" -n "$NAMESPACE" &> /dev/null; then
      dtb_log_ok "Deployment $dep reiniciado."
      grep_filter="${grep_filter:+$grep_filter|}$dep"
    else
      dtb_log_err "Falha ao reiniciar deployment $dep (deployment inexistente? nome derivado errado?)."
    fi
  done <<< "$deployments_to_restart"

  if [ -z "$grep_filter" ]; then
    dtb_log_err "Nenhum deployment foi reiniciado com sucesso."
    return 1
  fi

  echo
  if ! command -v watch >/dev/null 2>&1; then
    dtb_log_skip "Comando 'watch' não encontrado - pulando modo de acompanhamento."
    return 0
  fi

  local watch_choice
  read -r -p "Entrar em modo watch pra acompanhar o rollout? [y/N]: " watch_choice
  if [[ "$watch_choice" =~ ^[Yy]$ ]]; then
    watch "kubectl get pods -n $NAMESPACE | grep -E '($grep_filter)'"
  fi
}
