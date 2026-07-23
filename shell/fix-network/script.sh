# Comando "fix-network": ajustes de rede pra resolver instabilidade de
# conexão - desativa IPv6, limpa cache de DNS, reinicia NetworkManager e o
# agente Netskope (stagentd), se presente. Ambos os steps 1 e 2 rodam por
# padrão sem confirmação; --skip-ipv6/--skip-dns pulam cada um. Cross-platform
# Ubuntu/Debian + macOS via uname; passos 3 e 4 (restart de rede/Netskope)
# não têm equivalente confiável no macOS e são pulados lá.
#
# Uso: fix-network [--skip-ipv6] [--skip-dns]
# Uso: fix-network -h | --help
_dtb_help_fix_network() {
  cat <<'EOF'
fix-network - ajusta a rede em caso de instabilidade de conexão

Uso:
  fix-network [--skip-ipv6] [--skip-dns]

Descrição:
  1. Desativa IPv6 nas conexões de rede (--skip-ipv6 pula)
     - Linux: perfis salvos do NetworkManager (nmcli)
     - macOS: serviços de rede (networksetup -setv6off)
  2. Limpa o cache de DNS (--skip-dns pula)
     - Linux: 'resolvectl flush-caches'
     - macOS: 'dscacheutil -flushcache' + 'killall -HUP mDNSResponder'
  3. Reinicia o NetworkManager (só Linux - sem equivalente confiável no
     macOS, passo pulado lá)
  4. Reinicia o Netskope/stagentd, se instalado/habilitado (só Linux -
     sem nome de serviço launchd confiável no macOS, passo pulado lá)

Opções:
  --skip-ipv6   pula o passo 1 (desativação de IPv6)
  --skip-dns    pula o passo 2 (limpeza de cache DNS)
  -h            mostra esta ajuda
EOF
}

fix-network() {
  local skip_ipv6=false
  local skip_dns=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) _dtb_help_fix_network; return 0 ;;
      --skip-ipv6) skip_ipv6=true ;;
      --skip-dns) skip_dns=true ;;
    esac
    shift
  done

  source "{{ROOT}}/shell/_lib/log.sh"

  if [[ -t 1 ]] && ! command -v gum &>/dev/null; then
    echo "erro: 'gum' não encontrado - instale de novo via: curl -fsSL https://raw.githubusercontent.com/carlosdorneles-mb/dev-toolbox/main/bootstrap.sh | bash" >&2
    return 1
  fi

  local os
  case "$(uname -s)" in
    Darwin) os="macos" ;;
    *) os="linux" ;;
  esac

  sudo -v

  dtb_log_banner "Iniciando ajustes de rede..."

  # 1. Desativação de IPv6
  if [[ "$skip_ipv6" == true ]]; then
    dtb_log_skip "Pulando configuração de IPv6 (--skip-ipv6)."
  else
    if [[ "$os" == "macos" ]]; then
      dtb_run_step "Desativando IPv6 nos serviços de rede (networksetup)..." bash -c '
        networksetup -listallnetworkservices | tail -n +2 | while IFS= read -r service; do
          sudo networksetup -setv6off "$service" &>/dev/null
        done
      '
    else
      dtb_run_step "Desativando IPv6 nos perfis de conexão salvos (nmcli)..." bash -c '
        nmcli -t -f NAME connection show | while IFS= read -r connection; do
          sudo nmcli connection modify "$connection" ipv6.method ignore &>/dev/null
        done
      '
    fi
  fi

  # 2. Limpeza do cache de DNS
  if [[ "$skip_dns" == true ]]; then
    dtb_log_skip "Pulando limpeza de cache DNS (--skip-dns)."
  else
    if [[ "$os" == "macos" ]]; then
      dtb_run_step "Limpando cache de DNS..." bash -c 'sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'
    else
      dtb_run_step "Limpando cache de DNS..." sudo resolvectl flush-caches
    fi
  fi

  # 3. Reinício de serviços essenciais (NetworkManager - Linux only, sem
  # equivalente direto no macOS)
  if [[ "$os" == "linux" ]]; then
    dtb_run_step "Reiniciando NetworkManager..." sudo systemctl restart NetworkManager

    # 4. Reinício do Netskope (stagentd - Linux only, sem nome de serviço
    # launchd confiável no macOS)
    dtb_run_step "Aguardando estabilização da rede (5s) e reiniciando Netskope..." bash -c '
      sleep 5
      if systemctl is-active --quiet stagentd.service || systemctl is-enabled --quiet stagentd.service; then
        sudo systemctl restart stagentd
      fi
    '
  else
    dtb_log_skip "Pulando restart de NetworkManager/Netskope (sem equivalente no macOS)."
  fi

  echo ""
  dtb_log_banner "Ajustes concluídos com sucesso!"
}
