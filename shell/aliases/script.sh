# Comando "aliases": lista todos os aliases (shell + git) numa tabela,
# indicando de onde cada um vem (dev-toolbox ou outra fonte).
#
# Uso: aliases
#
# git aliases: origem exata via "git config --show-origin" - sem heuristica.
# shell aliases: "alias" (builtin) nao guarda origem, entao a fonte e melhor
# esforco - procura a definicao so no aliases.local.sh do dev-toolbox, no
# ~/.bashrc e no ~/.zshrc; alias que nao aparece em nenhum dos tres (plugin
# de framework, oh-my-zsh, etc) fica de fora da tabela - o objetivo aqui e
# mostrar o que foi configurado nesses arquivos, nao todo alias ativo na
# sessao.
aliases() {
  local dtb_root="{{ROOT}}"
  local dtb_shell_file="$dtb_root/shell/aliases.local.sh"

  local bold="" reset=""
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    bold=$'\e[1m'; reset=$'\e[0m'
  fi

  {
    printf 'TIPO\tNOME\tFONTE\tCOMANDO\n'

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
