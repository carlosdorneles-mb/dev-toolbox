# Comando "update": atualiza pacotes do sistema e ferramentas de dev
# instaladas, uma por uma, pulando qualquer uma que nao esteja presente na
# maquina.
#
# Uso: update
# Uso: update -h | --help
update() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Uso: update"
    echo ""
    echo "Atualiza pacotes do sistema (apt/brew) e ferramentas de dev"
    echo "instaladas (uv, poetry, mise, flatpak, snap, aqua, gcloud, rustup,"
    echo "pipx, cursor, vscode, sublime, podman, gh+extensions, docker"
    echo "desktop, mas), pulando qualquer uma nao presente na maquina."
    echo "Blocos especificos de apt/dpkg/systemctl so rodam no linux;"
    echo "'mas' (Mac App Store) so no macOS."
    return 0
  fi

  source "{{ROOT}}/shell/_lib/log.sh"

  sudo -v

  local os
  case "$(uname -s)" in
    Darwin) os="macos" ;;
    *) os="linux" ;;
  esac

  dtb_log_banner "Iniciando atualização do sistema..."
  echo ""

  # APT (Ubuntu/Debian - inexistente no macOS, onde o Homebrew abaixo cobre
  # tanto formulas quanto casks, incluindo os apps GUI checados mais abaixo)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null; then
    dtb_log_step "Atualizando pacotes APT..."
    sudo apt update -y && sudo apt upgrade -y
  fi

  # Homebrew
  if command -v brew &>/dev/null; then
    dtb_log_step "Atualizando Homebrew..."
    brew update && brew upgrade
  fi

  # UV
  if command -v uv &>/dev/null; then
    dtb_log_step "Atualizando UV..."
    uv self update
  fi

  # Poetry
  if command -v poetry &>/dev/null; then
    dtb_log_step "Atualizando Poetry..."
    poetry self update
  fi

  # Mise
  if command -v mise &>/dev/null; then
    dtb_log_step "Atualizando Mise..."
    mise self-update -y
  fi

  # Flatpak
  if command -v flatpak &>/dev/null; then
    dtb_log_step "Atualizando pacotes Flatpak..."
    flatpak update -y
  fi

  # Snap
  if command -v snap &>/dev/null; then
    dtb_log_step "Atualizando pacotes Snap..."
    snap refresh
  fi

  # Aqua
  if command -v aqua &>/dev/null; then
    dtb_log_step "Atualizando Aqua..."
    aqua upa
  fi

  # Google Cloud SDK
  if command -v gcloud &>/dev/null; then
    dtb_log_step "Atualizando Google Cloud SDK..."
    gcloud components update --quiet
  fi

  # Rustup
  if command -v rustup &>/dev/null; then
    dtb_log_step "Atualizando Rustup..."
    rustup update
  fi

  # Pipx
  if command -v pipx &>/dev/null; then
    dtb_log_step "Atualizando pacotes Pipx..."
    pipx upgrade-all
  fi

  # Cursor (deb direto da API do Cursor - só faz sentido no linux; no
  # macOS, se instalado via brew cask, ja foi coberto pelo bloco Homebrew
  # acima)
  if [[ "$os" == "linux" ]] && command -v cursor &>/dev/null; then
    dtb_log_step "Verificando atualizações do Cursor..."
    local cursor_url="https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/latest"
    local cursor_etag_cache="/tmp/.dev-toolbox-cursor-etag"
    local cursor_remote_etag
    cursor_remote_etag="$(curl -fsSI "$cursor_url" | grep -i '^etag:' | tr -d '\r' | awk '{print $2}')"

    if [[ -n "$cursor_remote_etag" ]] && [[ "$cursor_remote_etag" == "$(cat "$cursor_etag_cache" 2>/dev/null)" ]]; then
      dtb_log_ok "Cursor já está atualizado."
    else
      local cursor_deb="/tmp/cursor.deb"
      curl -fsSL "$cursor_url" -o "$cursor_deb" && sudo dpkg -i "$cursor_deb" && rm -f "$cursor_deb"
      [[ -n "$cursor_remote_etag" ]] && echo "$cursor_remote_etag" > "$cursor_etag_cache"
    fi
  fi

  # VS Code (pacote apt - no macOS, se instalado via brew cask, já foi
  # coberto pelo bloco Homebrew acima)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null && command -v code &>/dev/null; then
    dtb_log_step "Atualizando VS Code..."
    sudo apt install --only-upgrade code
  fi

  # Sublime Text (idem VS Code)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null && command -v subl &>/dev/null; then
    dtb_log_step "Atualizando Sublime Text..."
    sudo apt install --only-upgrade sublime-text
  fi

  # Podman (idem VS Code)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null && command -v podman &>/dev/null; then
    dtb_log_step "Atualizando Podman..."
    sudo apt install --only-upgrade podman
  fi

  # GitHub CLI - binário via apt só no linux; extensões (`gh extension`) são
  # multiplataforma, então rodam em qualquer OS onde `gh` existir
  if command -v gh &>/dev/null; then
    if [[ "$os" == "linux" ]] && command -v apt &>/dev/null; then
      dtb_log_step "Atualizando GitHub CLI..."
      sudo apt install --only-upgrade gh
    fi
    dtb_log_step "Atualizando extensões do GitHub CLI..."
    gh extension upgrade --all
  fi

  # Docker Desktop (baixa/instala .deb + systemctl - mecanismo exclusivo do
  # linux; no macOS, se instalado via brew cask, já foi coberto pelo bloco
  # Homebrew acima)
  if [[ "$os" == "linux" ]] && command -v docker &>/dev/null; then
    dtb_log_step "Verificando atualizações do Docker Desktop..."
    if docker desktop update -k 2>&1 | grep -q "is already the latest version"; then
      dtb_log_ok "Docker Desktop já está atualizado."
    else
      dtb_log_warn "Atualização do Docker Desktop disponível. Baixando e instalando..."
      local temp_deb="/tmp/docker-desktop-amd64.deb"
      wget -q --show-progress -O "$temp_deb" "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb?utm_source=docker&utm_medium=webreferral&utm_campaign=docs-driven-download-linux-amd64"

      if [ -f "$temp_deb" ]; then
        systemctl --user stop docker-desktop
        sudo dpkg -i "$temp_deb" && rm "$temp_deb"
        systemctl --user start docker-desktop
        dtb_log_ok "Docker Desktop atualizado com sucesso."
      else
        dtb_log_err "Falha ao baixar o Docker Desktop."
      fi
    fi
  fi

  # Mac App Store (via `mas` - https://github.com/mas-cli/mas)
  if [[ "$os" == "macos" ]] && command -v mas &>/dev/null; then
    dtb_log_step "Atualizando apps da Mac App Store..."
    mas upgrade
  fi

  # Limpeza (apt - inexistente no macOS)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null; then
    dtb_log_step "Limpando pacotes órfãos (autoremove/autoclean)..."
    sudo apt autoremove -y && sudo apt autoclean
  fi

  echo ""
  dtb_log_banner "Atualização do sistema concluída com sucesso!"
}
