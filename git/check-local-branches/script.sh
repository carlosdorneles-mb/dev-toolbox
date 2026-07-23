#!/bin/bash

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_chain_lib_dir="$_script_dir/../chain/lib"
source "$_chain_lib_dir/provider.sh"
source "$_chain_lib_dir/git.sh"
source "$_script_dir/../../shell/_lib/table.sh"

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
  mergeadas. Com "fzf" instalado (e terminal interativo), abre seleção
  múltipla (TAB marca, ENTER confirma) pra escolher quais apagar. Sem
  "fzf", cai pra confirmação y/N por branch. --yes pula qualquer seleção
  e apaga todas de uma vez. Nunca deleta a branch raiz nem a branch com
  checkout no momento (protegida pelo próprio git).

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
  STATUS  BRANCH                                       MOTIVO       ÚLTIMO COMMIT  NOTA
  MERGED  fix/promotions-mail-push-campaign-exclusion  [PR merged]  3 weeks ago    upstream sumiu
  MERGED  chore/bump-deps                              [ancestor]   2 months ago
  -       feat/promotions-autonomous-process            -            2 days ago     branch atual

  $ git check-local-branches --delete
  MERGED   fix/promotions-mail-push-campaign-exclusion   [PR merged]
  apagar 'fix/promotions-mail-push-campaign-exclusion'? [y/N] y
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

if (( is_tty )) && (( ! no_color_flag )) && [[ -z "$NO_COLOR" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  GREEN=$'\e[32m'; YELLOW=$'\e[33m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""
fi

checking_msg=0
if (( is_tty )) && (( ! json_mode )); then
  printf -- "${DIM}verificando branches locais...${RESET}" >&2
  checking_msg=1
fi

if (( ! no_fetch )); then
  git fetch --all --quiet --prune 2>/dev/null
fi

resolve_remotes_ordered
resolve_root_branch
root_ref="$(_ref_for "$root_branch")"

if [[ -z "$root_ref" ]]; then
  (( checking_msg )) && printf -- "\r\033[2K" >&2
  echo "erro: nao foi possivel resolver a branch raiz ('$root_branch')" >&2
  exit 1
fi

if (( ! no_fetch )) && ! pr_provider_available; then
  (( checking_msg )) && printf -- "\r\033[2K" >&2 && checking_msg=0
  pr_provider_deps_hint
fi

real_current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

results_name=()
results_merged=()
results_reasons=()
results_gone=()

mapfile -t local_branches < <(git for-each-ref --format='%(refname:short)' refs/heads/)

for b in "${local_branches[@]}"; do
  [[ "$b" == "$root_branch" ]] && continue

  reasons=()

  if git merge-base --is-ancestor "$b" "$root_ref" 2>/dev/null; then
    reasons+=("ancestor")
  fi

  if [[ -n "$(git rev-list "$root_ref..$b" 2>/dev/null)" ]]; then
    cherry_out="$(git cherry "$root_ref" "$b" 2>/dev/null)"
    if [[ -n "$cherry_out" ]] && ! grep -q '^+' <<< "$cherry_out"; then
      reasons+=("sem diff local")
    fi
  fi

  fetch_pr_info "$b"
  [[ "${pr_state[$b]}" == "MERGED" ]] && reasons+=("PR merged")

  gone=0
  upstream_status=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$b" 2>/dev/null)
  [[ "$upstream_status" == *"gone"* ]] && gone=1

  merged=0
  (( ${#reasons[@]} > 0 )) && merged=1

  results_name+=("$b")
  results_merged+=("$merged")
  results_reasons+=("$(IFS=,; echo "${reasons[*]}")")
  results_gone+=("$gone")
done

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
table_rows="$(printf 'STATUS\tBRANCH\tMOTIVO\tÚLTIMO COMMIT\tNOTA\n')"
for i in "${!results_name[@]}"; do
  b="${results_name[$i]}"

  last_commit="$(git log -1 --format=%cr "$b" 2>/dev/null)"
  [[ -z "$last_commit" ]] && last_commit="desconhecido"

  nota=""
  (( results_gone[i] )) && nota="⚠ upstream sumiu"
  [[ "$b" == "$real_current" ]] && nota="${nota:+$nota, }branch atual"

  if (( results_merged[i] )); then
    any_merged=1
    motivo="[${results_reasons[$i]}]"
    table_rows+="$(printf '\n%s\t%s\t%s\t%s\t%s' \
      "${GREEN}${BOLD}MERGED${RESET}" "$b" "${DIM}${motivo}${RESET}" "${DIM}${last_commit}${RESET}" "${YELLOW}${nota}${RESET}")"
  else
    table_rows+="$(printf '\n%s\t%s\t%s\t%s\t%s' \
      "${DIM}-${RESET}" "$b" "${DIM}-${RESET}" "${DIM}${last_commit}${RESET}" "${YELLOW}${nota}${RESET}")"
  fi
done
printf '%s\n' "$table_rows" | dtb_print_table "$BOLD" "$RESET"

if (( ! any_merged )); then
  echo "nenhuma branch local mergeada encontrada (raiz: $root_branch)" >&2
  exit 0
fi

if (( delete_mode )); then
  echo

  candidates=()
  for i in "${!results_name[@]}"; do
    (( ! results_merged[i] )) && continue
    b="${results_name[$i]}"
    if [[ "$b" == "$real_current" ]]; then
      echo "${YELLOW}pulando '$b': e a branch atual, de checkout${RESET}" >&2
      continue
    fi
    tag="[${results_reasons[$i]}]"
    (( results_gone[i] )) && tag="$tag (upstream sumiu)"
    candidates+=("$b"$'\t'"$tag")
  done

  to_delete=()
  if (( ${#candidates[@]} == 0 )); then
    : # nada a apagar
  elif (( yes_mode )); then
    for c in "${candidates[@]}"; do to_delete+=("${c%%$'\t'*}"); done
  elif (( is_tty )) && command -v fzf &>/dev/null; then
    mapfile -t selected < <(printf '%s\n' "${candidates[@]}" | fzf -m \
      --delimiter=$'\t' --with-nth=1,2 \
      --header=$'branches mergeadas - digite p/ filtrar\nTAB marca p/ apagar, ENTER confirma' \
      --prompt='filtrar> ' \
      --marker='✓ ' --pointer='▸')
    for s in "${selected[@]}"; do to_delete+=("${s%%$'\t'*}"); done
  else
    for c in "${candidates[@]}"; do
      b="${c%%$'\t'*}"
      read -r -p "apagar '$b'? [y/N] " confirm
      [[ "$confirm" == "y" || "$confirm" == "Y" ]] && to_delete+=("$b")
    done
  fi

  for b in "${to_delete[@]}"; do
    git branch -D "$b"
  done
fi
