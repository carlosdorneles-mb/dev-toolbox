# Biblioteca compartilhada de "dica" aleatoria no final de scripts bash do
# dev-toolbox (git/chain, git/check-local-branches, git/check-remote-branches
# etc). NAO e item instalavel (fora do catalog.json) - sourced via
# {{ROOT}}/caminho relativo pelos scripts que precisam.
#
# Uso:
#   dtb_hints_flags=("--json" "--no-fetch")
#   dtb_hints_descs=("saida em JSON pra script/pipe" "pula o git fetch antes de comparar")
#   dtb_print_random_hint "git check-local-branches" "$DIM" "$RESET"
#
# Sorteia 1 dica entre as pares flags/descs (mesmo indice) e imprime em
# stderr, alinhada. Chamador decide quando chamar (normalmente só em
# terminal interativo, fora de --json/--text).
if [[ -z "${_DTB_HINTS_LOADED:-}" ]]; then
  _DTB_HINTS_LOADED=1

  dtb_print_random_hint() {
    local cmd="$1" dim="$2" reset="$3"
    local -n _dtb_flags=dtb_hints_flags
    local -n _dtb_descs=dtb_hints_descs

    (( ${#_dtb_flags[@]} == 0 )) && return

    local width=0 f
    for f in "${_dtb_flags[@]}"; do (( ${#f} > width )) && width=${#f}; done

    local i=$(( RANDOM % ${#_dtb_flags[@]} ))

    echo >&2
    printf -- "%sdica: %s %-${width}s %s%s\n" \
      "$dim" "$cmd" "${_dtb_flags[$i]}" "${_dtb_descs[$i]}" "$reset" >&2
  }
fi
