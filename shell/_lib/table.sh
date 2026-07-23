# Biblioteca compartilhada de tabela alinhada pra scripts bash do dev-toolbox
# (git/check-local-branches, git/check-remote-branches etc). NÃO é item instalável (fora do
# catalog.json) - sourced via {{ROOT}} pelos scripts que precisam.
#
# Recebe linhas TSV via stdin (1a linha = header) e imprime alinhado por
# coluna, largura calculada ignorando códigos ANSI e hyperlinks OSC 8
# (senão colorir/linkar uma coluna desalinha as outras). Header sai em
# negrito, sem cor própria - mesma convenção do script "aliases".
#
# Uso:
#   { printf 'COL1\tCOL2\n'; printf 'a\tb\n'; } | dtb_print_table "$bold" "$reset"
if [[ -z "${_DTB_TABLE_LOADED:-}" ]]; then
  _DTB_TABLE_LOADED=1

  dtb_print_table() {
    local bold="$1" reset="$2"
    awk -F'\t' -v bold="$bold" -v reset="$reset" '
      function strip(s) {
        gsub(/\033\[[0-9;]*m/, "", s)
        gsub(/\033\]8;;[^\033]*\033\\/, "", s)
        return s
      }
      {
        raw[NR] = $0
        n = split($0, f, "\t")
        if (n > maxn) maxn = n
        for (i = 1; i <= n; i++) {
          plain = strip(f[i])
          if (length(plain) > w[i]) w[i] = length(plain)
        }
        nrows = NR
      }
      END {
        for (r = 1; r <= nrows; r++) {
          n = split(raw[r], f, "\t")
          line = ""
          for (i = 1; i <= n; i++) {
            plain = strip(f[i])
            pad = ""
            if (i < n) {
              padlen = w[i] - length(plain)
              if (padlen > 0) pad = sprintf("%*s", padlen, "")
            }
            line = line (i > 1 ? "  " : "") f[i] pad
          }
          if (r == 1) print bold line reset; else print line
        }
      }'
  }
fi
