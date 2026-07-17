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

  sudo -v

  local os
  case "$(uname -s)" in
    Darwin) os="macos" ;;
    *) os="linux" ;;
  esac

  echo -e "\033[1mIniciando atualização do sistema...\033[0m"
  echo ""

  # APT (Ubuntu/Debian - inexistente no macOS, onde o Homebrew abaixo cobre
  # tanto formulas quanto casks, incluindo os apps GUI checados mais abaixo)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null; then
    echo -e "\033[1;36m> Atualizando pacotes APT...\033[0m"
    sudo apt update -y && sudo apt upgrade -y
  fi

  # Homebrew
  if command -v brew &>/dev/null; then
    echo -e "\033[1;36m> Atualizando Homebrew...\033[0m"
    brew update && brew upgrade
  fi

  # UV
  if command -v uv &>/dev/null; then
    echo -e "\033[1;36m> Atualizando UV...\033[0m"
    uv self update
  fi

  # Poetry
  if command -v poetry &>/dev/null; then
    echo -e "\033[1;36m> Atualizando Poetry...\033[0m"
    poetry self update
  fi

  # Mise
  if command -v mise &>/dev/null; then
    echo -e "\033[1;36m> Atualizando Mise...\033[0m"
    mise self-update -y
  fi

  # Flatpak
  if command -v flatpak &>/dev/null; then
    echo -e "\033[1;36m> Atualizando pacotes Flatpak...\033[0m"
    flatpak update -y
  fi

  # Snap
  if command -v snap &>/dev/null; then
    echo -e "\033[1;36m> Atualizando pacotes Snap...\033[0m"
    snap refresh
  fi

  # Aqua
  if command -v aqua &>/dev/null; then
    echo -e "\033[1;36m> Atualizando Aqua...\033[0m"
    aqua upa
  fi

  # Google Cloud SDK
  if command -v gcloud &>/dev/null; then
    echo -e "\033[1;36m> Atualizando Google Cloud SDK...\033[0m"
    gcloud components update --quiet
  fi

  # Rustup
  if command -v rustup &>/dev/null; then
    echo -e "\033[1;36m> Atualizando Rustup...\033[0m"
    rustup update
  fi

  # Pipx
  if command -v pipx &>/dev/null; then
    echo -e "\033[1;36m> Atualizando pacotes Pipx...\033[0m"
    pipx upgrade-all
  fi

  # Cursor (deb direto da API do Cursor - só faz sentido no linux; no
  # macOS, se instalado via brew cask, ja foi coberto pelo bloco Homebrew
  # acima)
  if [[ "$os" == "linux" ]] && command -v cursor &>/dev/null; then
    echo -e "\033[1;36m> Verificando atualizações do Cursor...\033[0m"
    local cursor_url="https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/latest"
    local cursor_etag_cache="/tmp/.dev-toolbox-cursor-etag"
    local cursor_remote_etag
    cursor_remote_etag="$(curl -fsSI "$cursor_url" | grep -i '^etag:' | tr -d '\r' | awk '{print $2}')"

    if [[ -n "$cursor_remote_etag" ]] && [[ "$cursor_remote_etag" == "$(cat "$cursor_etag_cache" 2>/dev/null)" ]]; then
      echo -e "\033[1;32mCursor já está atualizado.\033[0m"
    else
      local cursor_deb="/tmp/cursor.deb"
      curl -fsSL "$cursor_url" -o "$cursor_deb" && sudo dpkg -i "$cursor_deb" && rm -f "$cursor_deb"
      [[ -n "$cursor_remote_etag" ]] && echo "$cursor_remote_etag" > "$cursor_etag_cache"
    fi
  fi

  # VS Code (pacote apt - no macOS, se instalado via brew cask, já foi
  # coberto pelo bloco Homebrew acima)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null && command -v code &>/dev/null; then
    echo -e "\033[1;36m> Atualizando VS Code...\033[0m"
    sudo apt install --only-upgrade code
  fi

  # Sublime Text (idem VS Code)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null && command -v subl &>/dev/null; then
    echo -e "\033[1;36m> Atualizando Sublime Text...\033[0m"
    sudo apt install --only-upgrade sublime-text
  fi

  # Podman (idem VS Code)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null && command -v podman &>/dev/null; then
    echo -e "\033[1;36m> Atualizando Podman...\033[0m"
    sudo apt install --only-upgrade podman
  fi

  # GitHub CLI - binário via apt só no linux; extensões (`gh extension`) são
  # multiplataforma, então rodam em qualquer OS onde `gh` existir
  if command -v gh &>/dev/null; then
    if [[ "$os" == "linux" ]] && command -v apt &>/dev/null; then
      echo -e "\033[1;36m> Atualizando GitHub CLI...\033[0m"
      sudo apt install --only-upgrade gh
    fi
    echo -e "\033[1;36m> Atualizando extensões do GitHub CLI...\033[0m"
    gh extension upgrade --all
  fi

  # Docker Desktop (baixa/instala .deb + systemctl - mecanismo exclusivo do
  # linux; no macOS, se instalado via brew cask, já foi coberto pelo bloco
  # Homebrew acima)
  if [[ "$os" == "linux" ]] && command -v docker &>/dev/null; then
    echo -e "\033[1;36m> Verificando atualizações do Docker Desktop...\033[0m"
    if docker desktop update -k 2>&1 | grep -q "is already the latest version"; then
      echo -e "\033[1;32mDocker Desktop já está atualizado.\033[0m"
    else
      echo -e "\033[1;33mAtualização do Docker Desktop disponível. Baixando e instalando...\033[0m"
      local temp_deb="/tmp/docker-desktop-amd64.deb"
      wget -q --show-progress -O "$temp_deb" "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb?utm_source=docker&utm_medium=webreferral&utm_campaign=docs-driven-download-linux-amd64"

      if [ -f "$temp_deb" ]; then
        systemctl --user stop docker-desktop
        sudo dpkg -i "$temp_deb" && rm "$temp_deb"
        systemctl --user start docker-desktop
        echo -e "\033[1;32mDocker Desktop atualizado com sucesso.\033[0m"
      else
        echo -e "\033[1;31mFalha ao baixar o Docker Desktop.\033[0m"
      fi
    fi
  fi

  # Mac App Store (via `mas` - https://github.com/mas-cli/mas)
  if [[ "$os" == "macos" ]] && command -v mas &>/dev/null; then
    echo -e "\033[1;36m> Atualizando apps da Mac App Store...\033[0m"
    mas upgrade
  fi

  # Limpeza (apt - inexistente no macOS)
  if [[ "$os" == "linux" ]] && command -v apt &>/dev/null; then
    echo -e "\033[1;36m> Limpando pacotes órfãos (autoremove/autoclean)...\033[0m"
    sudo apt autoremove -y && sudo apt autoclean
  fi

  echo ""
  echo -e "\033[1mAtualização do sistema concluída com sucesso!\033[0m"
}
