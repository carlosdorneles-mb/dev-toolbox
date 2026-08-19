#!/bin/bash

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_chain_lib_dir="$_script_dir/../chain/lib"
source "$_chain_lib_dir/provider.sh"
source "$_chain_lib_dir/git.sh"
source "$_script_dir/../../shell/_lib/table.sh"
source "$_script_dir/../../shell/_lib/hints.sh"

no_color_flag=0
no_fetch=0
delete_mode=0
yes_mode=0
json_mode=0
only_merged=0
only_stale=0
stale_days=90

_dtb_help_check_local_branches() {
  if command -v glow >/dev/null 2>&1; then
    glow -w 0 "$_script_dir/README.md"
  else
    cat "$_script_dir/README.md"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help=1 ;;
    --no-color) no_color_flag=1 ;;
    --no-fetch) no_fetch=1 ;;
    --delete) delete_mode=1 ;;
    --yes|-y) yes_mode=1 ;;
    --json) json_mode=1 ;;
    --only-merged) only_merged=1 ;;
    --only-stale) only_stale=1 ;;
    --stale-days)
      shift
      stale_days="$1"
      ;;
    *)
      echo "erro: opcao desconhecida '$1'" >&2
      exit 1
      ;;
  esac
  shift
done

if (( json_mode )) && ! command -v jq &>/dev/null; then
  echo "erro: --json exige 'jq' instalado" >&2
  exit 1
fi

if ! [[ "$stale_days" =~ ^[0-9]+$ ]]; then
  echo "erro: --stale-days precisa ser um número inteiro, recebido '$stale_days'" >&2
  exit 1
fi

if [[ -n "$show_help" ]]; then
  _dtb_help_check_local_branches
  exit 0
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "erro: nao esta dentro de um repositorio git" >&2
  exit 1
fi

is_tty=0
[[ -t 1 ]] && is_tty=1

# gum só é usado no spinner de carregamento (terminal + fora de --json) e no
# picker do --delete interativo - nesses dois casos, sem gum, não tem
# fallback. --json/pipe e --delete --yes nunca chegam a precisar dele.
if (( is_tty )) && (( ! json_mode )) && ! command -v gum &>/dev/null; then
  echo "erro: 'gum' não encontrado - instale de novo via: curl -fsSL https://raw.githubusercontent.com/carlosdorneles-mb/dev-toolbox/main/bootstrap.sh | bash" >&2
  exit 1
fi

if (( is_tty )) && (( ! no_color_flag )) && [[ -z "$NO_COLOR" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  GREEN=$'\e[32m'; YELLOW=$'\e[33m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""
fi

if (( ! no_fetch )); then
  git fetch --all --quiet --prune 2>/dev/null
fi

resolve_remotes_ordered
resolve_root_branch
root_ref="$(_ref_for "$root_branch")"

if [[ -z "$root_ref" ]]; then
  if (( is_tty )) && command -v gum &>/dev/null; then
    gum log -l error "não foi possível resolver a branch raiz ('$root_branch')"
  else
    echo "erro: nao foi possivel resolver a branch raiz ('$root_branch')" >&2
  fi
  exit 1
fi

if (( ! no_fetch )) && ! pr_provider_available; then
  pr_provider_deps_hint
fi

real_current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

mapfile -t local_branches < <(git for-each-ref --sort=committerdate --format='%(refname:short)' refs/heads/)

# branches checked out em OUTRO worktree (git branch -D falha nelas,
# "used by worktree") - o --porcelain lista o proprio worktree atual
# tambem (sempre o primeiro bloco), entao pula o bloco cujo path bate com
# o toplevel de onde o comando esta rodando; senao a branch atual (que
# nunca esta "em outro worktree", so no checkout normal daqui mesmo) seria
# marcada como worktree por engano
own_toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
declare -A worktree_branches
cur_wt_path=""
while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    cur_wt_path="${line#worktree }"
  elif [[ "$line" == branch\ refs/heads/* ]] && [[ "$cur_wt_path" != "$own_toplevel" ]]; then
    worktree_branches["${line#branch refs/heads/}"]=1
  fi
done < <(git worktree list --porcelain 2>/dev/null)

results_name=()
for b in "${local_branches[@]}"; do
  [[ "$b" == "$root_branch" ]] && continue
  results_name+=("$b")
done

if (( ${#results_name[@]} == 0 )); then
  if (( json_mode )); then
    echo '[]'
  elif (( is_tty )) && command -v gum &>/dev/null; then
    gum log -l info "nenhuma branch local encontrada (além da raiz '$root_branch')"
  else
    echo "nenhuma branch local encontrada (além da raiz '$root_branch')" >&2
  fi
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# roda em processo separado (gum spin exige um comando pra "vigiar") - por
# isso escreve o resultado de cada branch em arquivo em "$tmp_dir", igual
# check-remote-branches faz com o fetch de PR/compare.
cat > "$tmp_dir/_check.sh" <<'CHILD_SCRIPT'
#!/bin/bash
_chain_lib_dir="$1"; root_ref="$2"; no_fetch="$3"; out_dir="$4"
shift 4
branches=("$@")

source "$_chain_lib_dir/provider.sh"
source "$_chain_lib_dir/git.sh"

_dtb_check_one() {
  local b="$1" out="$2"
  local reasons=() cherry_out gone=0 upstream_status merged=0 reasons_str

  if git merge-base --is-ancestor "$b" "$root_ref" 2>/dev/null; then
    reasons+=("ancestor")
  fi

  if [[ -n "$(git rev-list "$root_ref..$b" 2>/dev/null)" ]]; then
    cherry_out="$(git cherry "$root_ref" "$b" 2>/dev/null)"
    if [[ -n "$cherry_out" ]] && ! grep -q '^+' <<< "$cherry_out"; then
      reasons+=("sem diff local")
    fi
  fi

  if (( ! no_fetch )); then
    fetch_pr_info "$b"
    [[ "${pr_state[$b]}" == "MERGED" ]] && reasons+=("PR merged")
  fi

  upstream_status=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$b" 2>/dev/null)
  [[ "$upstream_status" == *"gone"* ]] && gone=1

  (( ${#reasons[@]} > 0 )) && merged=1
  reasons_str="$(IFS=,; echo "${reasons[*]}")"

  printf '%s\t%s\t%s\n' "$merged" "$reasons_str" "$gone" > "$out"
}

max_parallel=8
running=0
for i in "${!branches[@]}"; do
  _dtb_check_one "${branches[$i]}" "$out_dir/$i.tsv" &
  (( ++running >= max_parallel )) && { wait -n; (( running-- )); }
done
wait
CHILD_SCRIPT

if (( is_tty )) && (( ! json_mode )); then
  gum spin --spinner dot --title "verificando branches locais..." -- \
    bash "$tmp_dir/_check.sh" "$_chain_lib_dir" "$root_ref" "$no_fetch" "$tmp_dir" "${results_name[@]}"
else
  bash "$tmp_dir/_check.sh" "$_chain_lib_dir" "$root_ref" "$no_fetch" "$tmp_dir" "${results_name[@]}"
fi

results_merged=()
results_reasons=()
results_gone=()
for i in "${!results_name[@]}"; do
  IFS=$'\t' read -r merged reasons gone < "$tmp_dir/$i.tsv"
  results_merged+=("$merged")
  results_reasons+=("$reasons")
  results_gone+=("$gone")
done

rm -rf "$tmp_dir"
trap - EXIT

now=$(date +%s)
results_age_days=()
results_stale=()
for i in "${!results_name[@]}"; do
  b="${results_name[$i]}"
  epoch="$(git log -1 --format=%ct "$b" 2>/dev/null)"
  if [[ -n "$epoch" ]]; then
    age="$(( (now - epoch) / 86400 ))"
  else
    age=""
  fi
  results_age_days+=("$age")
  stale=0
  [[ -n "$age" ]] && (( age > stale_days )) && stale=1
  results_stale+=("$stale")
done

results_worktree=()
for i in "${!results_name[@]}"; do
  b="${results_name[$i]}"
  wt=0
  [[ -n "${worktree_branches[$b]:-}" ]] && wt=1
  results_worktree+=("$wt")
done

(( checking_msg )) && printf -- "\r\033[2K" >&2

if (( json_mode )); then
  json_items=()
  for i in "${!results_name[@]}"; do
    (( only_merged )) && (( ! results_merged[i] )) && continue
    (( only_stale )) && (( ! results_stale[i] )) && continue
    reasons_json="[]"
    [[ -n "${results_reasons[$i]}" ]] && reasons_json=$(jq -R 'split(",")' <<< "${results_reasons[$i]}")
    json_items+=("$(jq -n \
      --arg name "${results_name[$i]}" \
      --argjson merged "$( (( results_merged[i] )) && echo true || echo false )" \
      --argjson reasons "$reasons_json" \
      --argjson gone "$( (( results_gone[i] )) && echo true || echo false )" \
      --arg age_days "${results_age_days[$i]}" \
      --argjson stale "$( (( results_stale[i] )) && echo true || echo false )" \
      --argjson worktree "$( (( results_worktree[i] )) && echo true || echo false )" \
      '{name: $name, merged: $merged, reasons: $reasons, gone: $gone,
        age_days: ($age_days | if . == "" then null else (. | tonumber) end),
        stale: $stale, worktree: $worktree}')")
  done
  printf '%s\n' "${json_items[@]}" | jq -s '.'
  exit 0
fi

any_deletable=0
matched_count=0
table_rows="$(printf 'STATUS\tBRANCH\tMOTIVO\tÚLTIMO COMMIT\tDEFASAGEM\tNOTA\n')"
for i in "${!results_name[@]}"; do
  (( only_merged )) && (( ! results_merged[i] )) && continue
  (( only_stale )) && (( ! results_stale[i] )) && continue
  matched_count=$(( matched_count + 1 ))
  b="${results_name[$i]}"
  [[ "$b" != "$real_current" ]] && (( ! results_worktree[i] )) && any_deletable=1

  last_commit="$(git log -1 --format=%cr "$b" 2>/dev/null)"
  [[ -z "$last_commit" ]] && last_commit="desconhecido"

  behind="$(git rev-list --count "$b..$root_ref" 2>/dev/null)"
  if [[ -z "$behind" ]]; then
    defasagem="?"
  elif (( behind == 0 )); then
    defasagem="em dia"
  else
    defasagem="$behind commit$([[ "$behind" != 1 ]] && echo s) atrás"
  fi

  nota=""
  (( results_stale[i] )) && nota="🟡 stale"
  (( results_gone[i] )) && nota="${nota:+$nota, }🟡 upstream sumiu"
  (( results_worktree[i] )) && nota="${nota:+$nota, }🌳 worktree"
  [[ "$b" == "$real_current" ]] && nota="${nota:+$nota, }branch atual"

  if (( results_merged[i] )); then
    motivo="[${results_reasons[$i]}]"
    table_rows+="$(printf '\n%s\t%s\t%s\t%s\t%s\t%s' \
      "${GREEN}${BOLD}MERGED${RESET}" "$b" "${DIM}${motivo}${RESET}" "${DIM}${last_commit}${RESET}" "${DIM}${defasagem}${RESET}" "${YELLOW}${nota}${RESET}")"
  else
    table_rows+="$(printf '\n%s\t%s\t%s\t%s\t%s\t%s' \
      "${DIM}-${RESET}" "$b" "${DIM}-${RESET}" "${DIM}${last_commit}${RESET}" "${DIM}${defasagem}${RESET}" "${YELLOW}${nota}${RESET}")"
  fi
done
if (( matched_count == 0 )); then
  motivo_vazio="nenhuma branch"
  (( only_merged && only_stale )) && motivo_vazio="nenhuma branch mergeada/stale encontrada"
  (( only_merged && ! only_stale )) && motivo_vazio="nenhuma branch mergeada encontrada"
  (( only_stale && ! only_merged )) && motivo_vazio="nenhuma branch stale encontrada (limite: ${stale_days} dias)"
  echo "${DIM}${motivo_vazio}${RESET}"
  exit 0
fi

printf '%s\n' "$table_rows" | dtb_print_table "$BOLD" "$RESET"

if (( ! delete_mode )) && (( is_tty )); then
  dtb_hints_flags=("--json" "--no-fetch" "--only-merged" "--only-stale" "--stale-days N")
  dtb_hints_descs=(
    "saída em JSON pra script/pipe"
    "pula o git fetch antes de comparar"
    "mostra só as branches mergeadas"
    "mostra só as branches stale"
    "muda o limite de dias pra marcar stale (default: 90)"
  )
  if (( any_deletable )); then
    dtb_hints_flags+=("--delete")
    dtb_hints_descs+=("escolhe quais apagar (--yes apaga mergeadas, +stale com --only-stale)")
    dtb_hints_flags+=("--only-merged --delete")
    dtb_hints_descs+=("remove todas as branches já mergeadas (+ --yes pra automático)")
    dtb_hints_flags+=("--only-stale --stale-days 90 --delete")
    dtb_hints_descs+=("apaga branches criadas há mais de 90 dias (+ --yes pra automático)")
  fi
  dtb_print_random_hint "git check-local-branches" "$DIM" "$RESET"
fi

if (( delete_mode )); then
  echo

  # candidatos = toda branch local exceto raiz (ja fora de results_name) e a
  # atual (protegida). --yes so apaga as mergeadas por padrao (sem revisao
  # humana, fica restrito ao criterio seguro); com --only-stale, stale
  # tambem vira criterio seguro (pedido explicito de quem chamou o script).
  # o picker interativo mostra todas - a decisao de apagar qualquer outra
  # fica por conta de quem escolhe.
  candidates=()
  safe_candidates=()
  for i in "${!results_name[@]}"; do
    (( only_merged )) && (( ! results_merged[i] )) && continue
    (( only_stale )) && (( ! results_stale[i] )) && continue
    b="${results_name[$i]}"
    if [[ "$b" == "$real_current" ]]; then
      if (( is_tty )) && command -v gum &>/dev/null; then
        gum log -l warn "pulando '$b': é a branch atual, de checkout"
      else
        echo "${YELLOW}pulando '$b': e a branch atual, de checkout${RESET}" >&2
      fi
      continue
    fi
    if (( results_worktree[i] )); then
      if (( is_tty )) && command -v gum &>/dev/null; then
        gum log -l warn "pulando '$b': checked out em outro worktree"
      else
        echo "${YELLOW}pulando '$b': checked out em outro worktree${RESET}" >&2
      fi
      continue
    fi

    is_safe=0
    (( results_merged[i] )) && is_safe=1
    (( only_stale )) && (( results_stale[i] )) && is_safe=1

    if (( results_merged[i] )); then
      tag="[${results_reasons[$i]}]"
    elif (( results_stale[i] )); then
      tag="[stale]"
    else
      tag="[não mergeada]"
    fi
    (( results_gone[i] )) && tag="$tag (upstream sumiu)"

    (( is_safe )) && safe_candidates+=("$b"$'\t'"$tag")
    candidates+=("$b"$'\t'"$tag")
  done

  to_delete=()
  if (( ${#candidates[@]} == 0 )); then
    if (( is_tty )) && command -v gum &>/dev/null; then
      gum log -l info "nenhuma branch pra apagar"
    else
      echo "nenhuma branch pra apagar" >&2
    fi
  elif (( yes_mode )); then
    if (( ${#safe_candidates[@]} == 0 )); then
      safe_desc="mergeadas"
      (( only_stale )) && safe_desc="mergeadas ou stale"
      if (( is_tty )) && command -v gum &>/dev/null; then
        gum log -l info "nenhuma branch $safe_desc pra apagar (--yes só apaga $safe_desc)"
      else
        echo "nenhuma branch $safe_desc pra apagar (--yes só apaga $safe_desc)" >&2
      fi
    fi
    for c in "${safe_candidates[@]}"; do to_delete+=("${c%%$'\t'*}"); done
  elif (( ! is_tty )); then
    echo "erro: --delete sem --yes precisa de terminal interativo pra selecionar as branches (via gum)" >&2
    exit 1
  else
    items=()
    for c in "${candidates[@]}"; do
      b="${c%%$'\t'*}"
      tag="${c#*$'\t'}"
      items+=("$b $tag")
    done
    mapfile -t selected < <(printf '%s\n' "${items[@]}" | gum choose --no-limit \
      --header="branches locais - selecione para remover")
    for s in "${selected[@]}"; do to_delete+=("${s%% *}"); done

    if (( ${#to_delete[@]} > 0 )); then
      echo
      echo "Selecionadas pra apagar:"
      for b in "${to_delete[@]}"; do echo "  - $b"; done
      echo
      gum confirm "apagar ${#to_delete[@]} branch(es) local(is)?" || to_delete=()
    fi
  fi

  for b in "${to_delete[@]}"; do
    git branch -D "$b"
  done
fi
