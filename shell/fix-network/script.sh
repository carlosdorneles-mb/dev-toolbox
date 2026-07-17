# Comando "fix_network": ajustes de rede pra resolver instabilidade de
# conexão - desativa IPv6 (opcional), limpa cache de DNS (opcional), reinicia
# NetworkManager e o agente Netskope (stagentd), se presente. Cross-platform
# Ubuntu/Debian + macOS via uname; passos 3 e 4 (restart de rede/Netskope)
# não têm equivalente confiável no macOS e são pulados lá.
#
# Uso: fix_network
# Uso: fix_network -h | --help
fix_network() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Uso: fix_network"
    echo ""
    echo "Ajusta a rede em caso de instabilidade de conexão:"
    echo "  1. Desativa IPv6 nas conexões de rede (opcional, pede confirmação)"
    echo "     - Linux: perfis salvos do NetworkManager (nmcli)"
    echo "     - macOS: serviços de rede (networksetup -setv6off)"
    echo "  2. Limpa o cache de DNS (opcional, pede confirmação)"
    echo "     - Linux: 'resolvectl flush-caches'"
    echo "     - macOS: 'dscacheutil -flushcache' + 'killall -HUP mDNSResponder'"
    echo "  3. Reinicia o NetworkManager (só Linux - sem equivalente confiável"
    echo "     no macOS, passo pulado lá)"
    echo "  4. Reinicia o Netskope/stagentd, se instalado/habilitado (só Linux"
    echo "     - sem nome de serviço launchd confiável no macOS, passo pulado"
    echo "     lá)"
    return 0
  fi

  local os
  case "$(uname -s)" in
    Darwin) os="macos" ;;
    *) os="linux" ;;
  esac

  sudo -v

  echo "Iniciando ajustes de rede..."

  # 1. Desativação de IPv6
  echo -e "\033[1;36m> Configuração IPv6\033[0m"
  echo -en "\033[1m-> Deseja desativar IPv6 nas conexões de rede? (y/N): \033[0m"
  read -r confirm_ipv6
  if [[ "$confirm_ipv6" == [yY] ]]; then
    if [[ "$os" == "macos" ]]; then
      echo "  > Desativando IPv6 nos serviços de rede (networksetup)..."
      networksetup -listallnetworkservices | tail -n +2 | while IFS= read -r service; do
        sudo networksetup -setv6off "$service" &>/dev/null
      done
    else
      echo "  > Desativando IPv6 nos perfis de conexão salvos (nmcli)..."
      nmcli -t -f NAME connection show | while IFS=$'\n' read -r connection; do
        sudo nmcli connection modify "$connection" ipv6.method ignore &>/dev/null
      done
    fi
    echo "IPv6 desativado nas conexões de rede."
  else
    echo -e "\033[1;90mPulando configuração de IPv6.\033[0m"
  fi

  # 2. Limpeza do cache de DNS
  echo -e "\033[1;36m> Configuração de cache DNS\033[0m"
  echo -en "\033[1m-> Deseja limpar o cache de DNS? (y/N): \033[0m"
  read -r confirm_dns
  if [[ "$confirm_dns" == [yY] ]]; then
    echo "  > Limpando cache de DNS..."
    if [[ "$os" == "macos" ]]; then
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
    else
      sudo resolvectl flush-caches
    fi
    echo "Cache de DNS limpo."
  else
    echo -e "\033[1;90mPulando limpeza de cache DNS.\033[0m"
  fi

  # 3. Reinício de serviços essenciais (NetworkManager - Linux only, sem
  # equivalente direto no macOS)
  if [[ "$os" == "linux" ]]; then
    echo "  > Reiniciando NetworkManager..."
    sudo systemctl restart NetworkManager

    # 4. Reinício do Netskope (stagentd - Linux only, sem nome de serviço
    # launchd confiável no macOS)
    echo "  > Aguardando estabilização da rede (5s) e reiniciando Netskope..."
    sleep 5
    if systemctl is-active --quiet stagentd.service || systemctl is-enabled --quiet stagentd.service; then
      sudo systemctl restart stagentd
    fi
  else
    echo -e "\033[1;90mPulando restart de NetworkManager/Netskope (sem equivalente no macOS).\033[0m"
  fi

  echo ""
  echo -e "\033[1mAjustes concluídos com sucesso!\033[0m"
}
