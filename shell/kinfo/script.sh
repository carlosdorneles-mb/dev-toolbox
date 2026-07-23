# Comando "kinfo": mostra detalhes de um deployment/pod no Kubernetes
# (namespace, env, versão, quem/quando fez o último deploy). Com gum
# instalado: ambiente omitido pede via "gum input"; app omitido abre um
# seletor ("gum filter") com os deployments do namespace.
#
# Uso: kinfo <ambiente> [nome-do-app]
# Uso: kinfo -h | --help
_dtb_help_kinfo() {
  cat <<'EOF'
kinfo - mostra detalhes de um deployment/pod no Kubernetes

Uso:
  kinfo <ambiente> [nome-do-app]

Descrição:
  Verifica credenciais/conectividade do cluster ("kubectl cluster-info")
  antes de qualquer coisa. Mostra namespace, env, versão e quem/quando
  fez o último deploy. Com gum instalado e o nome do app omitido, abre
  um seletor com os deployments do namespace.

Opções:
  <ambiente>     namespace do Kubernetes (fallback: $K_ENV; sem os dois,
                 com gum instalado pede via prompt "gum input")
  [nome-do-app]  nome do deployment (fallback: $K_APP; sem os dois, abre
                 seletor gum se instalado)
  -h             mostra esta ajuda
EOF
}

# espera um PID em background mostrando um spinner (gum so "vigia" um
# comando externo, nao um PID direto - poll leve de 0.1s resolve isso sem
# precisar redirecionar a saida do comando real por dentro do gum spin,
# que exigiria escapar o jsonpath dentro de um bash -c aninhado)
_dtb_kinfo_wait_gum() {
  local title="$1" pid="$2"
  if [ -t 1 ] && command -v gum >/dev/null 2>&1; then
    gum spin --spinner dot --title "$title" -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 0.1; done"
  fi
  wait "$pid" 2>/dev/null
}

kinfo() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help) _dtb_help_kinfo; return 0 ;;
    esac
  done

  # kinfo roda dentro do shell interativo do usuario (funcao sourced, nao
  # subshell) - com job control ligado (padrao em shell interativo), o "&"
  # em background concorrendo com o "gum spin" (rodando em foreground,
  # fazendo poll do PID) faz o bash notificar "[N] PID"/"[N]+ Done|Exit" a
  # qualquer momento (nao so na linha do "wait" - redirecionar so a saida
  # do "wait"/do lancamento do "&" nao e suficiente). "-m" (monitor) sozinho
  # nao basta - "-b" (notificacao assincrona de job) tambem precisa ir,
  # senao o aviso ainda escapa. Nenhum dos dois recursos e usado aqui (sem
  # fg/bg/suspend) - desliga os dois so durante a chamada.
  #
  # Restaura via wrapper (chama _dtb_kinfo_impl e recupera o "set" depois),
  # NAO via "trap ... RETURN": a mera presenca de um RETURN trap faz o bash
  # voltar a emitir o aviso mesmo com "-b" desligado (comportamento
  # observado, nao documentado) - o wrapper evita isso porque os vários
  # "return" de dentro da função só saem dela, nunca de "kinfo" direto.
  local _dtb_had_monitor=0 _dtb_had_notify=0
  case "$-" in *m*) _dtb_had_monitor=1 ;; esac
  case "$-" in *b*) _dtb_had_notify=1 ;; esac
  if [ -n "$ZSH_VERSION" ]; then
    unsetopt monitor notify
  else
    set +mb
  fi
  _dtb_kinfo_impl "$@"
  local _dtb_kinfo_rc=$?
  if [ -n "$ZSH_VERSION" ]; then
    (( _dtb_had_monitor )) && setopt monitor
    (( _dtb_had_notify )) && setopt notify
  else
    (( _dtb_had_monitor )) && set -m
    (( _dtb_had_notify )) && set -b
  fi
  return "$_dtb_kinfo_rc"
}

_dtb_kinfo_impl() {
  local ENV=${1:-${K_ENV}}
  local APP=${2:-${K_APP}}

  # Cores (desligadas se stdout não for terminal, ou com NO_COLOR setado -
  # mesma convenção do resto do dev-toolbox, ver shell/_lib/log.sh)
  source "{{ROOT}}/shell/_lib/log.sh"
  local RED="$_DTB_RED" GREEN="$_DTB_GREEN" YELLOW="$_DTB_YELLOW" BLUE="$_DTB_BLUE" NC="$_DTB_RESET"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}Erro: 'kubectl' não encontrado - instale-o antes de usar o kinfo.${NC}"
    return 1
  fi

  # 0. Verifica credenciais/conectividade antes de pedir qualquer coisa -
  # sem cluster acessível, nao ha sentido em perguntar ambiente/app
  local ci_tmp
  ci_tmp="$(mktemp)"
  { kubectl cluster-info --request-timeout=10s > "$ci_tmp" 2>&1 & } 2>/dev/null
  if ! _dtb_kinfo_wait_gum "Verificando credenciais do cluster..." "$!"; then
    echo -e "${RED}Erro: não foi possível conectar ao cluster (credenciais/kubeconfig inválidos?).${NC}"
    cat "$ci_tmp"
    rm -f "$ci_tmp"
    return 1
  fi
  rm -f "$ci_tmp"

  # 1. Validação do Ambiente - sem ele (nem argumento, nem $K_ENV), com gum
  # instalado abre um prompt pra digitar em vez de só erro/uso
  if [ -z "$ENV" ] && [ -t 1 ] && command -v gum >/dev/null 2>&1; then
    ENV=$(gum input --header="Ambiente (namespace) do Kubernetes:" --placeholder="ex: staging")
    [ -n "$ENV" ] && echo -e "${BLUE}Ambiente:${NC} $ENV"
  fi
  if [ -z "$ENV" ]; then
    echo -e "${RED}Erro: O nome do ambiente (namespace) é obrigatório.${NC}"
    echo -e "Uso: kinfo <ambiente> [nome-do-app]"
    return 1
  fi

  local KCTX
  KCTX="$(kubectl config current-context 2>/dev/null)"
  [ -n "$KCTX" ] && echo -e "${BLUE}Context:${NC} $KCTX"

  # 2. Lógica do App e Alerta do gum
  if [ -z "$APP" ]; then
    if [ -t 1 ] && command -v gum >/dev/null 2>&1; then
      local lista_tmp lista
      lista_tmp="$(mktemp)"
      { kubectl get deployments -n "$ENV" --request-timeout=10s -o jsonpath='{.items[*].metadata.name}' > "$lista_tmp" 2>/dev/null & } 2>/dev/null
      _dtb_kinfo_wait_gum "Buscando apps no namespace '$ENV'..." "$!"
      lista="$(cat "$lista_tmp")"
      rm -f "$lista_tmp"
      if [ -z "$lista" ]; then
        echo -e "${RED}Nenhum deployment encontrado no namespace '$ENV'.${NC}"
        return 1
      fi
      APP=$(echo "$lista" | tr ' ' '\n' | gum filter --height 15 --header="Selecione o App [$ENV]:")
      [ -z "$APP" ] && { echo "Operação cancelada."; return 0; }
    else
      # Alerta de instalação
      echo -e "${RED}--------------------------------------------------------"
      echo -e "AVISO: Nome do app não informado, e não dá pra abrir seletor"
      echo -e "('gum' ausente ou sem terminal interativo)."
      echo -e "--------------------------------------------------------${NC}"
      echo -e "Sem 'gum', instale de novo via: curl -fsSL https://raw.githubusercontent.com/carlosdorneles-mb/dev-toolbox/main/bootstrap.sh | bash"
      echo -e ""
      echo -e "Ou informe o app manualmente: ${BLUE}kinfo $ENV <nome-app>${NC}"
      echo -e "${RED}--------------------------------------------------------${NC}"
      return 1
    fi
  fi

  # 3. Coleta de dados
  local DATA_RAW data_tmp
  data_tmp="$(mktemp)"
  { kubectl get deployment "$APP" -n "$ENV" --request-timeout=10s -o jsonpath='{.metadata.name}{"|"}{.metadata.namespace}{"|"}{.spec.template.spec.containers[0].env[?(@.name=="OTEL_APP_ENV")].value}{"|"}{.spec.template.spec.containers[0].env[?(@.name=="OTEL_APP_VERSION")].value}{"|"}{.metadata.annotations.last_deploy_by}' > "$data_tmp" 2>/dev/null & } 2>/dev/null
  _dtb_kinfo_wait_gum "Buscando detalhes do deployment '$APP'..." "$!"
  DATA_RAW="$(cat "$data_tmp")"
  rm -f "$data_tmp"

  if [ -z "$DATA_RAW" ]; then
    echo -e "${RED}Erro ao buscar detalhes do app '$APP' no namespace '$ENV'.${NC}"
    return 1
  fi

  # Parsing dos campos - 1 split só, em vez de 5 subshells de "cut"
  local D_NAME D_NS D_ENV D_VER D_DEPLOYER_FULL
  IFS='|' read -r D_NAME D_NS D_ENV D_VER D_DEPLOYER_FULL <<< "$DATA_RAW"
  D_ENV="${D_ENV:-<não configurado>}"
  D_VER="${D_VER:-<não configurado>}"

  # 4. Tratamento do Deployer e Data (Ex: jefferson.silva-2026-03-12T19:49:17+0000)
  # Extrai o que vem antes da data (nome) e o que é a data em si
  local USER_NAME RAW_DATE
  USER_NAME="$(sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}T.*//' <<< "$D_DEPLOYER_FULL")"
  RAW_DATE="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}' <<< "$D_DEPLOYER_FULL")"

  # Conversão de Data para PT-BR
  local FORMATED_DATE=""
  if [ -n "$RAW_DATE" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      FORMATED_DATE=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$RAW_DATE" "+%d/%m/%Y %H:%M:%S" 2>/dev/null)
    else
      FORMATED_DATE=$(date -d "$RAW_DATE" "+%d/%m/%Y %H:%M:%S" 2>/dev/null)
    fi
  fi
  [ -z "$FORMATED_DATE" ] && FORMATED_DATE=$RAW_DATE

  # 5. Output formatado
  echo -e "\n${BLUE}========== Detalhes do Deployment ==========${NC}"
  echo -e "${GREEN}App:${NC}        $D_NAME"
  echo -e "${GREEN}Namespace:${NC}  $D_NS"
  echo -e "${GREEN}Env:${NC}        $D_ENV"
  echo -e "${GREEN}Version:${NC}    $D_VER"
  echo -e "--------------------------------------------"
  echo -e "${YELLOW}Deployer:${NC}   $USER_NAME"
  echo -e "${YELLOW}Data/Hora:${NC}  $FORMATED_DATE (BRT)"
  echo -e "${BLUE}============================================${NC}\n"
}
