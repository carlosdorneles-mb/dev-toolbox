# Comando "kinfo": mostra detalhes de um deployment/pod no Kubernetes
# (namespace, env, versão, quem/quando fez o último deploy). Com fzf
# instalado e o nome do app omitido, abre um seletor com os deployments do
# namespace.
#
# Uso: kinfo <ambiente> [nome-do-app]
# Uso: kinfo -h | --help
kinfo() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Uso: kinfo <ambiente> [nome-do-app]"
    echo ""
    echo "  <ambiente>     namespace do Kubernetes (fallback: \$K_ENV)"
    echo "  [nome-do-app]  nome do deployment (fallback: \$K_APP; sem os"
    echo "                 dois, abre seletor fzf se instalado)"
    return 0
  fi

  local ENV=${1:-${K_ENV}}
  local APP=${2:-${K_APP}}

  # Cores (desligadas se stdout não for terminal, ou com NO_COLOR setado -
  # mesma convenção do resto do dev-toolbox)
  local RED="" GREEN="" YELLOW="" BLUE="" NC=""
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}Erro: 'kubectl' não encontrado - instale-o antes de usar o kinfo.${NC}"
    return 1
  fi

  # 1. Validação do Ambiente
  if [ -z "$ENV" ]; then
    echo -e "${RED}Erro: O nome do ambiente (namespace) é obrigatório.${NC}"
    echo -e "Uso: kinfo <ambiente> [nome-do-app]"
    return 1
  fi

  local KCTX
  KCTX="$(kubectl config current-context 2>/dev/null)"
  [ -n "$KCTX" ] && echo -e "${BLUE}Context:${NC} $KCTX"

  # 2. Lógica do App e Alerta do fzf
  if [ -z "$APP" ]; then
    if command -v fzf >/dev/null 2>&1; then
      echo -e "${BLUE}Buscando apps no namespace '$ENV'...${NC}"
      local lista
      lista="$(kubectl get deployments -n "$ENV" --request-timeout=10s -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
      if [ -z "$lista" ]; then
        echo -e "${RED}Nenhum deployment encontrado no namespace '$ENV'.${NC}"
        return 1
      fi
      APP=$(echo "$lista" | tr ' ' '\n' | fzf --height 40% --reverse --border --header="Selecione o App [$ENV]:")
      [ -z "$APP" ] && { echo "Operação cancelada."; return 0; }
    else
      # Alerta de instalação
      echo -e "${RED}--------------------------------------------------------"
      echo -e "AVISO: Nome do app não informado e 'fzf' não detectado."
      echo -e "--------------------------------------------------------${NC}"
      echo -e "Para selecionar apps visualmente, instale o ${GREEN}fzf${NC}:"
      echo -e "  • ${YELLOW}macOS${NC}:  brew install fzf"
      echo -e "  • ${YELLOW}Ubuntu${NC}: sudo apt install fzf"
      echo -e ""
      echo -e "Ou informe o app manualmente: ${BLUE}kinfo $ENV <nome-app>${NC}"
      echo -e "${RED}--------------------------------------------------------${NC}"
      return 1
    fi
  fi

  # 3. Coleta de dados
  local DATA_RAW
  DATA_RAW="$(kubectl get deployment "$APP" -n "$ENV" --request-timeout=10s -o jsonpath='{.metadata.name}{"|"}{.metadata.namespace}{"|"}{.spec.template.spec.containers[0].env[?(@.name=="OTEL_APP_ENV")].value}{"|"}{.spec.template.spec.containers[0].env[?(@.name=="OTEL_APP_VERSION")].value}{"|"}{.metadata.annotations.last_deploy_by}' 2>/dev/null)"

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
