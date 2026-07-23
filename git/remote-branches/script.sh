#!/bin/bash

no_color_flag=0
delete_mode=0
yes_mode=0
json_mode=0
only_merged=0
only_stale=0
stale_days=90
repo_arg=""
show_help=0

_dtb_help_remote_branches() {
  cat <<'EOF'
git remote-branches - lista branches remotas de um repo GitHub (via API, sem clone/fetch local), com status de merge/PR/idade, e permite apagar as encontradas

Uso:
  git remote-branches [org/repo|URL] [--delete [--yes]] [--stale-days N] [--only-merged] [--only-stale] [--json] [--no-color]

Descricao:
  Pra cada branch remota do repo (exceto a branch default), resolve:

    - status de merge: existe PR com state=MERGED apontando essa branch?
    - PR aberta: existe PR com state=OPEN apontando essa branch?
    - autoria/idade: primeiro commit unico da branch (vs a default) = quem
      criou/quando (aproximado); ultimo commit = quem atualizou por
      ultimo/quando
    - stale: ultimo commit mais antigo que --stale-days (default: 90)

  Resolucao do repo (nessa ordem): argumento posicional (org/repo ou URL);
  senao, detecta pelo diretorio atual (se for um repo git com remote
  GitHub); senao, pergunta interativamente.

  100% via API remota (gh) - nunca faz fetch/clone/leitura de objetos git
  locais.

Opcoes:
  --delete         apaga (com confirmacao) as branches candidatas encontradas
  --yes, -y        junto com --delete, nao pede confirmacao por branch
  --stale-days N   idade em dias do ultimo commit acima da qual marca "stale" (default: 90)
  --only-merged    mostra/considera so branches mergeadas
  --only-stale     mostra/considera so branches stale
  --no-color       desabilita cores
  --json           array JSON por branch (exige jq)
  -h               mostra esta ajuda
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help=1 ;;
    --no-color) no_color_flag=1 ;;
    --delete) delete_mode=1 ;;
    --yes|-y) yes_mode=1 ;;
    --json) json_mode=1 ;;
    --only-merged) only_merged=1 ;;
    --only-stale) only_stale=1 ;;
    --stale-days)
      shift
      stale_days="$1"
      ;;
    -*)
      echo "erro: opcao desconhecida '$1'" >&2
      exit 1
      ;;
    *)
      if [[ -n "$repo_arg" ]]; then
        echo "erro: argumento inesperado '$1'" >&2
        exit 1
      fi
      repo_arg="$1"
      ;;
  esac
  shift
done

if (( show_help )); then
  _dtb_help_remote_branches
  exit 0
fi

if ! command -v gh &>/dev/null; then
  echo "erro: 'gh' (GitHub CLI) nao encontrado - instale e rode 'gh auth login'" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "erro: 'jq' nao encontrado - instale" >&2
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "erro: 'gh' sem login - rode 'gh auth login'" >&2
  exit 1
fi

if ! [[ "$stale_days" =~ ^[0-9]+$ ]]; then
  echo "erro: --stale-days precisa ser um numero inteiro, recebido '$stale_days'" >&2
  exit 1
fi

repo=""
default_branch=""

resolve_repo() {
  local arg="$1"
  local json=""

  if [[ -n "$arg" ]]; then
    json=$(gh repo view "$arg" --json nameWithOwner,defaultBranchRef 2>/dev/null)
    if [[ -z "$json" ]]; then
      echo "erro: nao foi possivel resolver o repo '$arg'" >&2
      exit 1
    fi
  else
    json=$(gh repo view --json nameWithOwner,defaultBranchRef 2>/dev/null)
    if [[ -z "$json" ]]; then
      if [[ -t 0 ]]; then
        read -r -p "repo GitHub (org/repo ou URL): " arg
      fi
      if [[ -z "$arg" ]]; then
        echo "erro: nenhum repo informado e nao foi possivel detectar pelo diretorio atual" >&2
        exit 1
      fi
      json=$(gh repo view "$arg" --json nameWithOwner,defaultBranchRef 2>/dev/null)
      if [[ -z "$json" ]]; then
        echo "erro: nao foi possivel resolver o repo '$arg'" >&2
        exit 1
      fi
    fi
  fi

  repo=$(jq -r '.nameWithOwner // empty' <<< "$json")
  default_branch=$(jq -r '.defaultBranchRef.name // empty' <<< "$json")

  if [[ -z "$repo" || -z "$default_branch" ]]; then
    echo "erro: resposta invalida do 'gh repo view' pro repo '$arg'" >&2
    exit 1
  fi
}

resolve_repo "$repo_arg"

is_tty=0
[[ -t 1 ]] && is_tty=1

if (( is_tty )) && (( ! no_color_flag )) && [[ -z "$NO_COLOR" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  GREEN=$'\e[32m'; YELLOW=$'\e[33m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""
fi

branches_raw=$(gh api "repos/$repo/branches" --paginate 2>/dev/null)
if [[ -z "$branches_raw" ]]; then
  echo "erro: nao foi possivel listar as branches de '$repo'" >&2
  exit 1
fi

mapfile -t branch_names < <(jq -r --arg default "$default_branch" \
  '.[] | select(.name != $default) | .name' <<< "$branches_raw")

declare -A branch_protected
while IFS=$'\t' read -r name protected; do
  [[ -z "$name" ]] && continue
  branch_protected["$name"]="$protected"
done < <(jq -r --arg default "$default_branch" \
  '.[] | select(.name != $default) | [.name, (.protected|tostring)] | @tsv' <<< "$branches_raw")

declare -A pr_number pr_url pr_state

fetch_pr_info() {
  local b="$1"
  local json
  json=$(gh pr list --repo "$repo" --head "$b" --state all \
    --json number,url,state,author --limit 10 \
    --jq 'if any(.[]; .state=="OPEN") then ([.[] | select(.state=="OPEN")])[0]
          elif any(.[]; .state=="MERGED") then ([.[] | select(.state=="MERGED")])[0]
          else empty end' 2>/dev/null)

  pr_number["$b"]=$(jq -r '.number // empty' <<< "$json" 2>/dev/null)
  pr_url["$b"]=$(jq -r '.url // empty' <<< "$json" 2>/dev/null)
  pr_state["$b"]=$(jq -r '.state // empty' <<< "$json" 2>/dev/null)
}

_branch_merged() {
  [[ "${pr_state[$1]}" == "MERGED" ]]
}

_branch_matches_filters() {
  local b="$1"
  if (( only_merged )) && ! _branch_merged "$b"; then
    return 1
  fi
  if (( only_stale )) && [[ "${is_stale[$b]}" != "1" ]]; then
    return 1
  fi
  return 0
}

declare -A created_by created_at updated_by updated_at age_days is_stale

_iso_to_epoch() {
  local iso="$1"
  local epoch
  epoch=$(date -d "$iso" +%s 2>/dev/null)
  if [[ -z "$epoch" ]]; then
    epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null)
  fi
  echo "$epoch"
}

fetch_compare_info() {
  local b="$1"
  local json
  json=$(gh api "repos/$repo/compare/$default_branch...$b" \
    --jq '{first: (.commits[0] // empty), last: (.commits[-1] // empty)}' 2>/dev/null)

  created_by["$b"]=$(jq -r '.first.commit.author.name // empty' <<< "$json" 2>/dev/null)
  created_at["$b"]=$(jq -r '.first.commit.author.date // empty' <<< "$json" 2>/dev/null)
  updated_by["$b"]=$(jq -r '.last.commit.author.name // empty' <<< "$json" 2>/dev/null)
  updated_at["$b"]=$(jq -r '.last.commit.author.date // empty' <<< "$json" 2>/dev/null)

  local epoch now
  epoch=$(_iso_to_epoch "${updated_at[$b]}")
  if [[ -n "$epoch" ]]; then
    now=$(date +%s)
    age_days["$b"]=$(( (now - epoch) / 86400 ))
  else
    age_days["$b"]=""
  fi

  is_stale["$b"]=0
  if [[ -n "${age_days[$b]}" ]] && (( age_days[$b] > stale_days )); then
    is_stale["$b"]=1
  fi
}

for b in "${branch_names[@]}"; do
  fetch_pr_info "$b"
  fetch_compare_info "$b"
done

if (( json_mode )); then
  json_items=()
  for b in "${branch_names[@]}"; do
    _branch_matches_filters "$b" || continue
    json_items+=("$(jq -n \
      --arg name "$b" \
      --argjson protected "$( [[ "${branch_protected[$b]}" == "true" ]] && echo true || echo false )" \
      --argjson merged "$( _branch_merged "$b" && echo true || echo false )" \
      --arg pr_number "${pr_number[$b]}" \
      --arg pr_url "${pr_url[$b]}" \
      --arg pr_state "${pr_state[$b]}" \
      --arg created_by "${created_by[$b]}" \
      --arg created_at "${created_at[$b]}" \
      --arg updated_by "${updated_by[$b]}" \
      --arg updated_at "${updated_at[$b]}" \
      --argjson stale "$( [[ "${is_stale[$b]}" == "1" ]] && echo true || echo false )" \
      '{name: $name, protected: $protected, merged: $merged,
        pr_number: ($pr_number | if . == "" then null else (. | tonumber) end),
        pr_url: ($pr_url | if . == "" then null else . end),
        pr_state: ($pr_state | if . == "" then null else . end),
        created_by: ($created_by | if . == "" then null else . end),
        created_at: ($created_at | if . == "" then null else . end),
        updated_by: ($updated_by | if . == "" then null else . end),
        updated_at: ($updated_at | if . == "" then null else . end),
        stale: $stale}')")
  done
  printf '%s\n' "${json_items[@]}" | jq -s '.'
  exit 0
fi

any_shown=0
for b in "${branch_names[@]}"; do
  _branch_matches_filters "$b" || continue
  any_shown=1

  if _branch_merged "$b"; then
    status="${GREEN}${BOLD}MERGED${RESET}   [PR #${pr_number[$b]}]"
  elif [[ "${pr_state[$b]}" == "OPEN" ]]; then
    status="${DIM}-        [PR aberta #${pr_number[$b]}]${RESET}"
  else
    status="${DIM}-        [sem PR]${RESET}"
  fi

  protected_tag=""
  [[ "${branch_protected[$b]}" == "true" ]] && protected_tag=" [protected]"

  stale_tag=""
  [[ "${is_stale[$b]}" == "1" ]] && stale_tag=" ${YELLOW}⚠ stale${RESET}"

  age_label="idade desconhecida"
  [[ -n "${age_days[$b]}" ]] && age_label="${age_days[$b]} dias atras"

  printf -- "%s %-30s %s -> %s, %s%s%s\n" \
    "$status" "$b" "${created_by[$b]:-?}" "${updated_by[$b]:-?}" "$age_label" "$stale_tag" "$protected_tag"
done

if (( ! any_shown )); then
  echo "nenhuma branch encontrada com os filtros atuais (repo: $repo)" >&2
  exit 0
fi

if (( delete_mode )); then
  echo

  candidates=()
  for b in "${branch_names[@]}"; do
    _branch_matches_filters "$b" || continue
    [[ "${branch_protected[$b]}" == "true" ]] && continue
    if (( only_stale )); then
      [[ "${is_stale[$b]}" == "1" ]] || continue
      [[ "${pr_state[$b]}" == "OPEN" ]] && continue
    else
      _branch_merged "$b" || continue
    fi
    tag="[sem PR]"
    _branch_merged "$b" && tag="[PR #${pr_number[$b]}]"
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
      --header=$'branches candidatas - digite p/ filtrar\nTAB marca p/ apagar, ENTER confirma' \
      --prompt='filtrar> ' \
      --marker='✓ ' --pointer='▸')
    for s in "${selected[@]}"; do to_delete+=("${s%%$'\t'*}"); done
  else
    for c in "${candidates[@]}"; do
      b="${c%%$'\t'*}"
      read -r -p "apagar '$b' no remote '$repo'? [y/N] " confirm
      [[ "$confirm" == "y" || "$confirm" == "Y" ]] && to_delete+=("$b")
    done
  fi

  for b in "${to_delete[@]}"; do
    if gh api -X DELETE "repos/$repo/git/refs/heads/$b" &>/dev/null; then
      echo "Deleted branch $b (remote: $repo)."
    else
      echo "erro: falha ao apagar '$b' no remote '$repo'" >&2
    fi
  done
fi
