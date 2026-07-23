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

_dtb_help_check_local_branches() {
  cat <<'EOF'
git check-local-branches - lista branches locais já mergeadas no remote (origin por padrão)

Uso:
  git check-local-branches [--delete [--yes]] [--no-fetch] [--no-color] [--json]

Descrição:
  Pra cada branch local (exceto a raiz main/master), verifica se o
  conteúdo dela já foi integrado na branch raiz do remote, por 3 métodos
  (qualquer um confirma merge):

    1. ancestor       - branch é ancestral direto da raiz (merge normal,
                        merge --ff-only, ou merge commit preservando
                        histórico)
    2. sem diff local - "git cherry" mostra que todo commit da branch já
                        tem equivalente (mesmo patch-id) na raiz - cobre
                        merge via rebase que reaplica commit a commit
    3. PR merged      - PR da branch (via "gh") está com state=MERGED -
                        único jeito confiável de detectar squash merge
                        (1 commit novo na raiz, sem ancestral nem patch-id
                        batendo com nenhum commit da branch)

  Sem "gh"/"jq" instalados (ou sem login), o método 3 é pulado - branch
  squash-mergeada pode aparecer como "não mergeada" nesse caso (avisa 1x
  em stderr).

  Branch com upstream remoto sumido ("git branch -vv" mostra "[gone]") é
  sinal extra, mostrado mas não usado sozinho pra decidir - só reforça o
  resultado dos 3 métodos acima.

  --delete remove (git branch -D) as branches identificadas como
  mergeadas. Sem --yes, a seleção usa "gum choose --no-limit" (espaço
  marca, enter confirma) seguido de "gum confirm" - exige terminal
  interativo e "gum" instalado, sem fallback. --yes pula seleção e
  confirmação, apaga todas de uma vez (não precisa de "gum"). Nunca
  deleta a branch raiz nem a branch com checkout no momento (protegida
  pelo próprio git).

Opções:
  --delete     apaga (com confirmação) as branches mergeadas encontradas
  --yes, -y    junto com --delete, não pede confirmação por branch
  --no-fetch   pula o "git fetch" antes de comparar (usa o que já está
               local - mais rápido, pode estar desatualizado)
  --no-color   desabilita cores
  --json       array JSON com {name, merged, reasons, gone} por branch
               (exige "jq")
  -h           mostra esta ajuda

Exemplos:
  $ git check-local-branches
  STATUS  BRANCH                                       MOTIVO       ÚLTIMO COMMIT  DEFASAGEM        NOTA
  MERGED  fix/promotions-mail-push-campaign-exclusion  [PR merged]  3 weeks ago    em dia           upstream sumiu
  MERGED  chore/bump-deps                              [ancestor]   2 months ago   em dia
  -       feat/promotions-autonomous-process            -            2 days ago     12 commits atrás  branch atual

  $ git check-local-branches --delete
  MERGED   fix/promotions-mail-push-campaign-exclusion   [PR merged]
  # abre gum choose - espaço marca, ENTER confirma, depois gum confirm
  Deleted branch fix/promotions-mail-push-campaign-exclusion (was 621e441).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help=1 ;;
    --no-color) no_color_flag=1 ;;
    --no-fetch) no_fetch=1 ;;
    --delete) delete_mode=1 ;;
    --yes|-y) yes_mode=1 ;;
    --json) json_mode=1 ;;
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

results_name=()
for b in "${local_branches[@]}"; do
  [[ "$b" == "$root_branch" ]] && continue
  results_name+=("$b")
done

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

(( checking_msg )) && printf -- "\r\033[2K" >&2

if (( json_mode )); then
  json_items=()
  for i in "${!results_name[@]}"; do
    reasons_json="[]"
    [[ -n "${results_reasons[$i]}" ]] && reasons_json=$(jq -R 'split(",")' <<< "${results_reasons[$i]}")
    json_items+=("$(jq -n \
      --arg name "${results_name[$i]}" \
      --argjson merged "$( (( results_merged[i] )) && echo true || echo false )" \
      --argjson reasons "$reasons_json" \
      --argjson gone "$( (( results_gone[i] )) && echo true || echo false )" \
      '{name: $name, merged: $merged, reasons: $reasons, gone: $gone}')")
  done
  printf '%s\n' "${json_items[@]}" | jq -s '.'
  exit 0
fi

any_merged=0
table_rows="$(printf 'STATUS\tBRANCH\tMOTIVO\tÚLTIMO COMMIT\tDEFASAGEM\tNOTA\n')"
for i in "${!results_name[@]}"; do
  b="${results_name[$i]}"

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
  (( results_gone[i] )) && nota="⚠ upstream sumiu"
  [[ "$b" == "$real_current" ]] && nota="${nota:+$nota, }branch atual"

  if (( results_merged[i] )); then
    any_merged=1
    motivo="[${results_reasons[$i]}]"
    table_rows+="$(printf '\n%s\t%s\t%s\t%s\t%s\t%s' \
      "${GREEN}${BOLD}MERGED${RESET}" "$b" "${DIM}${motivo}${RESET}" "${DIM}${last_commit}${RESET}" "${DIM}${defasagem}${RESET}" "${YELLOW}${nota}${RESET}")"
  else
    table_rows+="$(printf '\n%s\t%s\t%s\t%s\t%s\t%s' \
      "${DIM}-${RESET}" "$b" "${DIM}-${RESET}" "${DIM}${last_commit}${RESET}" "${DIM}${defasagem}${RESET}" "${YELLOW}${nota}${RESET}")"
  fi
done
printf '%s\n' "$table_rows" | dtb_print_table "$BOLD" "$RESET"

if (( ! delete_mode )) && (( is_tty )); then
  dtb_hints_flags=("--json" "--no-fetch")
  dtb_hints_descs=(
    "saída em JSON pra script/pipe"
    "pula o git fetch antes de comparar"
  )
  if (( any_merged )); then
    dtb_hints_flags+=("--delete")
    dtb_hints_descs+=("apaga as mergeadas (--yes pula confirmação)")
  fi
  dtb_print_random_hint "git check-local-branches" "$DIM" "$RESET"
fi

if (( delete_mode )); then
  echo

  candidates=()
  for i in "${!results_name[@]}"; do
    (( ! results_merged[i] )) && continue
    b="${results_name[$i]}"
    if [[ "$b" == "$real_current" ]]; then
      if (( is_tty )) && command -v gum &>/dev/null; then
        gum log -l warn "pulando '$b': é a branch atual, de checkout"
      else
        echo "${YELLOW}pulando '$b': e a branch atual, de checkout${RESET}" >&2
      fi
      continue
    fi
    tag="[${results_reasons[$i]}]"
    (( results_gone[i] )) && tag="$tag (upstream sumiu)"
    candidates+=("$b"$'\t'"$tag")
  done

  to_delete=()
  if (( ${#candidates[@]} == 0 )); then
    if (( is_tty )) && command -v gum &>/dev/null; then
      gum log -l info "nenhuma branch mergeada pra apagar"
    else
      echo "nenhuma branch mergeada pra apagar" >&2
    fi
  elif (( yes_mode )); then
    for c in "${candidates[@]}"; do to_delete+=("${c%%$'\t'*}"); done
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
      --header="branches mergeadas - espaço marca, enter confirma")
    for s in "${selected[@]}"; do to_delete+=("${s%% *}"); done

    if (( ${#to_delete[@]} > 0 )) && ! gum confirm "apagar ${#to_delete[@]} branch(es) local(is)?"; then
      to_delete=()
    fi
  fi

  for b in "${to_delete[@]}"; do
    git branch -D "$b"
  done
fi
