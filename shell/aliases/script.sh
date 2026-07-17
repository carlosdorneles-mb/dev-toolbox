# Coleta bruta (sem header, sem formatação) dos aliases de shell + git numa
# tabela TIPO\tNOME\tFONTE\tCOMANDO. Usada tanto pelo "aliases" (listagem)
# quanto pelo "aliases -r/--run" (menu fzf executável).
#
# git aliases: origem exata via "git config --show-origin" - sem heuristica.
# shell aliases: "alias" (builtin) nao guarda origem, entao a fonte e melhor
# esforco - procura a definicao so no aliases.local.sh do dev-toolbox, no
# ~/.bashrc e no ~/.zshrc; alias que nao aparece em nenhum dos tres (plugin
# de framework, oh-my-zsh, etc) fica de fora da tabela - o objetivo aqui e
# mostrar o que foi configurado nesses arquivos, nao todo alias ativo na
# sessao.
# shell "aliases" do proprio dev-toolbox (aliases/update/kinfo/fix_network)
# nao sao "alias" builtin, sao funcoes - por isso entram num loop separado,
# lendo os nomes de funcao direto do aliases.local.sh gerado.
_dtb_aliases_collect() {
  local dtb_root="{{ROOT}}"
  local dtb_shell_file="$dtb_root/shell/aliases.local.sh"

  # --- aliases de shell (bash/zsh) ---
  local line name value src rc
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line="${line#alias }"          # bash prefixa "alias "; zsh nao
    name="${line%%=*}"
    value="${line#*=}"
    value="${value#\'}"; value="${value%\'}"   # tira aspas simples
    value="${value#\"}"; value="${value%\"}"   # tira aspas duplas

    src=""
    for rc in "$dtb_shell_file" "$HOME/.dev-toolbox/shell/aliases.local.sh" \
              "$HOME/.bashrc" "$HOME/.zshrc"; do
      [[ -f "$rc" ]] || continue
      if grep -qE "(^|[^[:alnum:]_-])alias[[:space:]]+${name}=" "$rc" 2>/dev/null; then
        if [[ "$rc" == */shell/aliases.local.sh ]]; then
          src="dev-toolbox"
        else
          src="$rc"
        fi
        break
      fi
    done
    # nao achou em bashrc/zshrc/dev-toolbox -> nao foi configurado por eles
    # (ex: alias de plugin/framework tipo oh-my-zsh) - fora da tabela
    [[ -z "$src" ]] && continue

    printf 'shell\t%s\t%s\t%s\n' "$name" "$src" "$value"
  done < <(alias 2>/dev/null)

  # --- funcoes de shell do proprio dev-toolbox (nao sao "alias" builtin) ---
  local dtb_func_file="$dtb_shell_file"
  [[ -f "$dtb_func_file" ]] || dtb_func_file="$HOME/.dev-toolbox/shell/aliases.local.sh"
  if [[ -f "$dtb_func_file" ]]; then
    local fname
    while IFS= read -r fname; do
      [[ -z "$fname" ]] && continue
      printf 'shell\t%s\t%s\t%s\n' "$fname" "dev-toolbox" "$fname"
    done < <(grep -oE '^[A-Za-z][A-Za-z0-9_]*\(\)' "$dtb_func_file" 2>/dev/null | sed 's/()$//')
  fi

  # --- aliases de git ---
  if command -v git &>/dev/null; then
    local origin keyvalue
    while IFS=$'\t' read -r origin keyvalue; do
      [[ -z "$keyvalue" ]] && continue
      name="${keyvalue#alias.}"
      name="${name%% *}"
      value="${keyvalue#* }"
      origin="${origin#file:}"

      if [[ "$origin" == */git/aliases.local.gitconfig ]]; then
        src="dev-toolbox"
      else
        src="$origin"
      fi

      printf 'git\t%s\t%s\t%s\n' "$name" "$src" "$value"
    done < <(git config --show-origin --get-regexp '^alias\.' 2>/dev/null)
  fi
}

# Comando "aliases": lista todos os aliases (shell + git) numa tabela,
# indicando de onde cada um vem (dev-toolbox ou outra fonte). Com
# -r/--run, abre um menu fzf pra escolher e executar um deles na hora.
#
# Uso: aliases [-r|--run] [--only-dev-toolbox]
# Uso: aliases -h | --help
aliases() {
  local run=0 only_dtb=0 arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        echo "Uso: aliases [-r|--run] [--only-dev-toolbox]"
        echo ""
        echo "Lista todos os aliases de shell e git numa tabela (TIPO, NOME,"
        echo "FONTE, COMANDO), indicando se vieram do dev-toolbox ou de outra"
        echo "fonte (~/.bashrc, ~/.zshrc, ~/.gitconfig etc)."
        echo ""
        echo "  -r, --run             abre um menu fzf (NOME + COMANDO) pra"
        echo "                        escolher um alias e executá-lo na hora"
        echo "  --only-dev-toolbox    mostra só os aliases com FONTE=dev-toolbox"
        echo "                        (combina com -r/--run)"
        return 0
        ;;
      -r|--run) run=1 ;;
      --only-dev-toolbox) only_dtb=1 ;;
    esac
  done

  # Cores (desligadas se stdout não for terminal, ou com NO_COLOR setado -
  # mesma convenção do resto do dev-toolbox, ver shell/_lib/log.sh)
  source "{{ROOT}}/shell/_lib/log.sh"
  local bold="$_DTB_BOLD" reset="$_DTB_RESET" red="$_DTB_RED" yellow="$_DTB_YELLOW" green="$_DTB_GREEN"

  if (( run )); then
    if ! command -v fzf >/dev/null 2>&1; then
      echo -e "${red}--------------------------------------------------------"
      echo "AVISO: 'fzf' não encontrado - obrigatório pro menu executável."
      echo -e "--------------------------------------------------------${reset}"
      echo -e "Instale o ${green}fzf${reset}:"
      echo -e "  • ${yellow}macOS${reset}:  brew install fzf"
      echo -e "  • ${yellow}Ubuntu${reset}: sudo apt install fzf"
      return 1
    fi

    local raw
    raw="$(_dtb_aliases_collect)"
    (( only_dtb )) && raw="$(printf '%s\n' "$raw" | awk -F'\t' '$3 == "dev-toolbox"')"
    if [[ -z "$raw" ]]; then
      echo "Nenhum alias encontrado."
      return 0
    fi

    local picked tipo nome fonte comando
    picked="$(printf '%s\n' "$raw" \
      | fzf --delimiter='\t' --with-nth=2,4 \
            --prompt='executar alias> ' \
            --header='NOME  COMANDO   |  ENTER: executa  |  ESC: cancela' \
            --preview='printf "tipo:    %s\nnome:    %s\nfonte:   %s\ncomando: %s\n" {1} {2} {3} {4}' \
            --preview-window='down,4,wrap' \
            --height='~60%' --layout=reverse)"
    [[ -z "$picked" ]] && { echo "Operação cancelada."; return 0; }

    IFS=$'\t' read -r tipo nome fonte comando <<< "$picked"

    if [[ "$tipo" == "git" ]]; then
      echo -e "${bold}\$ git $nome${reset}"
      git "$nome"
    else
      echo -e "${bold}\$ $comando${reset}"
      eval "$comando"
    fi
    return
  fi

  {
    printf 'TIPO\tNOME\tFONTE\tCOMANDO\n'
    if (( only_dtb )); then
      _dtb_aliases_collect | awk -F'\t' '$3 == "dev-toolbox"'
    else
      _dtb_aliases_collect
    fi
  } | awk -F'\t' -v bold="$bold" -v reset="$reset" '
    {
      for (i=1;i<=4;i++) { if (length($i) > w[i]) w[i] = length($i) }
      rows[NR] = $0
      nrows = NR
    }
    END {
      for (r=1; r<=nrows; r++) {
        n = split(rows[r], f, "\t")
        line = ""
        for (i=1; i<=n; i++) {
          pad = f[i] sprintf("%*s", w[i]-length(f[i]), "")
          line = line (i>1 ? "  " : "") pad
        }
        if (r == 1) print bold line reset; else print line
      }
    }'
}
