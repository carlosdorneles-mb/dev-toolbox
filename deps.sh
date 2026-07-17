#!/usr/bin/env bash
# Verifica/instala dependências externas exigidas pelos itens do dev-toolbox.
# Genérico - não conhece nomes de dependência nenhum: descobre tudo lendo
# arquivos "deps" (um por item, opcional) + um "deps" na raiz (dependências
# do próprio toolbox, não de um item específico - ex: fzf usado pelo
# install.sh). Detecta o que já está instalado e a versão; instala o que
# falta e atualiza o que estiver abaixo da versão mínima exigida.
#
# Uso:
#   ./deps.sh              # verifica e instala/atualiza o que for preciso
#   ./deps.sh --check-only # só reporta status (não instala nada), exit 1 se
#                           # algo faltar ou estiver desatualizado
#
# Suporta macOS (via brew) e Ubuntu/Debian (via apt-get). Chamado
# automaticamente pelo install.sh - rodar direto só é preciso pra depurar.
#
# Formato do arquivo "deps" (um por linha): bin|min_version|version_cmd
# (version_cmd deve imprimir algo que contenha a versão em X.Y(.Z) na saída)
set -euo pipefail

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  GREEN=$'\e[32m'; RED=$'\e[31m'; CYAN=$'\e[36m'; YELLOW=$'\e[33m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; RED=""; CYAN=""; YELLOW=""
fi

CHECK_ONLY=0
[[ "${1:-}" == "--check-only" ]] && CHECK_ONLY=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$ROOT/MANIFEST"

# --- descoberta das dependências (genérica, via arquivos "deps") -----------
DEPS=()

_collect_deps_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    DEPS+=("$line")
  done < "$file"
}

_collect_deps_file "$ROOT/deps"

if [[ -f "$MANIFEST" ]]; then
  while IFS='|' read -r id _type path _entry _desc || [[ -n "$id" ]]; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    _collect_deps_file "$ROOT/$(dirname "$path")/deps"
  done < "$MANIFEST"
fi

# dedupe por bin (primeiro campo) - mesmo bin pode ser exigido por >1 item
declare -A _seen_bin
_deduped=()
for entry in "${DEPS[@]}"; do
  bin="${entry%%|*}"
  [[ -n "${_seen_bin[$bin]+x}" ]] && continue
  _seen_bin["$bin"]=1
  _deduped+=("$entry")
done
DEPS=("${_deduped[@]}")

# --- detecção de SO ---------------------------------------------------------
OS=""
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)
    if [[ -f /etc/os-release ]] && grep -qEi 'ubuntu|debian' /etc/os-release; then
      OS="ubuntu"
    else
      OS="linux-desconhecido"
    fi
    ;;
  *) OS="desconhecido" ;;
esac

_extract_version() {
  # pega o primeiro X.Y(.Z) que aparecer na saída do comando de versão
  grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

_version_ge() {
  # retorna 0 (verdadeiro) se $1 >= $2. Comparação numérica campo a campo
  # (não usa "sort -V" - é extensão GNU, ausente no sort BSD do macOS).
  [[ "$1" == "$2" ]] && return 0

  local -a v1 v2
  IFS='.' read -ra v1 <<< "$1"
  IFS='.' read -ra v2 <<< "$2"

  local i max=${#v1[@]}
  (( ${#v2[@]} > max )) && max=${#v2[@]}

  for ((i = 0; i < max; i++)); do
    local a="${v1[i]:-0}" b="${v2[i]:-0}"
    (( 10#$a > 10#$b )) && return 0
    (( 10#$a < 10#$b )) && return 1
  done
  return 0
}

_install_or_upgrade() {
  local bin="$1" action="$2" # action: install | upgrade

  case "$OS" in
    macos)
      if ! command -v brew &>/dev/null; then
        echo "${RED}✘${RESET} homebrew não encontrado - instale em https://brew.sh antes de continuar." >&2
        return 1
      fi
      if [[ "$action" == "install" ]]; then
        brew install "$bin"
      else
        brew upgrade "$bin"
      fi
      ;;
    ubuntu)
      local sudo_cmd="sudo"
      if [[ "$(id -u)" == "0" ]]; then
        sudo_cmd=""
      elif ! command -v sudo &>/dev/null; then
        echo "${RED}✘${RESET} 'sudo' não encontrado e não estou rodando como root - instale '$bin' manualmente." >&2
        return 1
      fi

      if [[ "$bin" == "gh" ]] && ! apt-cache show gh &>/dev/null; then
        if ! command -v curl &>/dev/null; then
          echo "${RED}✘${RESET} 'curl' é necessário pra adicionar o repositório do GitHub CLI - instale-o primeiro." >&2
          return 1
        fi
        _add_gh_apt_repo "$sudo_cmd"
      fi
      $sudo_cmd apt-get update -qq
      $sudo_cmd apt-get install -y "$bin"
      ;;
    *)
      echo "${RED}✘${RESET} SO não suportado automaticamente ($OS) - instale '$bin' manualmente (mínimo exigido acima)." >&2
      return 1
      ;;
  esac
}

_add_gh_apt_repo() {
  # repo oficial do GitHub CLI - necessário em Ubuntu/Debian mais antigos, onde
  # 'gh' não está nos repos padrão (ver https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
  local sudo_cmd="${1:-sudo}"
  echo "${DIM}  adicionando repositório oficial do GitHub CLI (apt)...${RESET}"
  $sudo_cmd mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | $sudo_cmd tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  $sudo_cmd chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | $sudo_cmd tee /etc/apt/sources.list.d/github-cli.list > /dev/null
}

echo "${BOLD}${CYAN}dev-toolbox${RESET} - verificando dependências (SO detectado: ${BOLD}$OS${RESET})"
echo ""

if (( ${#DEPS[@]} == 0 )); then
  echo "${DIM}nenhuma dependência declarada (nem na raiz, nem em itens do MANIFEST).${RESET}"
  exit 0
fi

missing_or_outdated=0
install_failed=0

for entry in "${DEPS[@]}"; do
  IFS='|' read -r bin min_version version_cmd <<< "$entry"

  if ! command -v "$bin" &>/dev/null; then
    echo "${RED}✘${RESET} ${BOLD}$bin${RESET} não instalado ${DIM}(mínimo: $min_version)${RESET}"
    missing_or_outdated=1
    (( CHECK_ONLY )) && continue

    if _install_or_upgrade "$bin" install; then
      echo "${GREEN}✔${RESET} $bin instalado."
    else
      install_failed=1
    fi
    continue
  fi

  current_version="$($version_cmd 2>&1 | _extract_version || true)"
  if [[ -z "$current_version" ]]; then
    echo "${YELLOW}⚠${RESET} $bin instalado, mas não consegui detectar a versão - pulando checagem de versão."
    continue
  fi

  if _version_ge "$current_version" "$min_version"; then
    echo "${GREEN}✔${RESET} $bin ${DIM}$current_version${RESET} ${GREEN}ok${RESET} ${DIM}(mínimo: $min_version)${RESET}"
  else
    echo "${YELLOW}⚠${RESET} ${BOLD}$bin${RESET} desatualizado: ${DIM}$current_version${RESET} < $min_version"
    missing_or_outdated=1
    (( CHECK_ONLY )) && continue

    if _install_or_upgrade "$bin" upgrade; then
      echo "${GREEN}✔${RESET} $bin atualizado."
    else
      install_failed=1
    fi
  fi
done

echo ""
if (( install_failed )); then
  echo "${RED}✘ uma ou mais dependências não puderam ser instaladas/atualizadas (ver acima).${RESET}"
  exit 1
fi

if (( missing_or_outdated )); then
  if (( CHECK_ONLY )); then
    echo "${YELLOW}⚠ algumas dependências faltam ou estão desatualizadas (ver acima).${RESET}"
    exit 1
  fi
  echo "${GREEN}${BOLD}✔ dependências verificadas.${RESET}"
else
  echo "${GREEN}${BOLD}✔ todas as dependências já estão ok.${RESET}"
fi
