#!/bin/bash

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_script_dir/../../shell/_lib/table.sh"

no_color_flag=0
delete_mode=0
yes_mode=0
json_mode=0
only_merged=0
only_stale=0
stale_days=90
repo_arg=""
show_help=0

_dtb_help_check_remote_branches() {
  cat <<'EOF'
git check-remote-branches - lista branches remotas de um repo GitHub (via API, sem clone/fetch local), com status de merge/PR/idade, e permite apagar as encontradas

Uso:
  git check-remote-branches [org/repo|URL] [--delete [--yes]] [--stale-days N] [--only-merged] [--only-stale] [--json] [--no-color]

Descrição:
  Pra cada branch remota do repo (exceto a branch default), resolve:

    - status de merge: existe PR com state=MERGED apontando essa branch?
    - PR aberta: existe PR com state=OPEN apontando essa branch?
    - autoria/idade: primeiro commit único da branch (vs a default) = quem
      criou/quando (aproximado); último commit = quem atualizou por
      último/quando
    - stale: último commit mais antigo que --stale-days (default: 90)

  Resolução do repo (nessa ordem): argumento posicional (org/repo ou URL);
  senão, detecta pelo diretório atual (se for um repo git com remote
  GitHub); senão, pergunta interativamente.

  100% via API remota (gh) - nunca faz fetch/clone/leitura de objetos git
  locais.

Opções:
  --delete         apaga (com confirmação) as branches candidatas encontradas
  --yes, -y        junto com --delete, não pede confirmação por branch
  --stale-days N   idade em dias do último commit acima da qual marca "stale" (default: 90)
  --only-merged    mostra/considera só branches mergeadas
  --only-stale     mostra/considera só branches stale
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
      echo "erro: opção desconhecida '$1'" >&2
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
  _dtb_help_check_remote_branches
  exit 0
fi

if ! command -v gh &>/dev/null; then
  echo "erro: 'gh' (GitHub CLI) não encontrado - instale e rode 'gh auth login'" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "erro: 'jq' não encontrado - instale" >&2
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "erro: 'gh' sem login - rode 'gh auth login'" >&2
  exit 1
fi

if ! [[ "$stale_days" =~ ^[0-9]+$ ]]; then
  echo "erro: --stale-days precisa ser um número inteiro, recebido '$stale_days'" >&2
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
      echo "erro: não foi possível resolver o repo '$arg'" >&2
      exit 1
    fi
  else
    json=$(gh repo view --json nameWithOwner,defaultBranchRef 2>/dev/null)
    if [[ -z "$json" ]]; then
      if [[ -t 0 ]]; then
        read -r -p "repo GitHub (org/repo ou URL): " arg
      fi
      if [[ -z "$arg" ]]; then
        echo "erro: nenhum repo informado e não foi possível detectar pelo diretório atual" >&2
        exit 1
      fi
      json=$(gh repo view "$arg" --json nameWithOwner,defaultBranchRef 2>/dev/null)
      if [[ -z "$json" ]]; then
        echo "erro: não foi possível resolver o repo '$arg'" >&2
        exit 1
      fi
    fi
  fi

  repo=$(jq -r '.nameWithOwner // empty' <<< "$json")
  default_branch=$(jq -r '.defaultBranchRef.name // empty' <<< "$json")

  if [[ -z "$repo" || -z "$default_branch" ]]; then
    echo "erro: resposta inválida do 'gh repo view' pro repo '$arg'" >&2
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

# hyperlink OSC 8 - terminal sem suporte (ou saida via pipe/redirect) so
# ignora a sequencia e mostra o texto puro, sem quebrar nada
use_links=0
(( is_tty )) && use_links=1

_dtb_link() {
  local url="$1" text="$2"
  if (( use_links )) && [[ -n "$url" ]]; then
    printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$url" "$text"
  else
    printf '%s' "$text"
  fi
}

checking_msg=0
if (( is_tty )) && (( ! json_mode )); then
  printf -- "${DIM}verificando branches remotas...${RESET}" >&2
  checking_msg=1
fi

branches_raw=$(gh api "repos/$repo/branches" --paginate 2>/dev/null)
if [[ -z "$branches_raw" ]]; then
  (( checking_msg )) && printf -- "\r\033[2K" >&2
  echo "erro: não foi possível listar as branches de '$repo'" >&2
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

declare -A created_by created_at updated_by updated_at age_days is_stale commit_epoch

_iso_to_epoch() {
  local iso="$1"
  local epoch
  epoch=$(date -d "$iso" +%s 2>/dev/null)
  if [[ -z "$epoch" ]]; then
    epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null)
  fi
  echo "$epoch"
}

# busca PR + compare de uma branch e grava num arquivo (roda em paralelo,
# sem escrever direto nos arrays associativos - subshell nao compartilha
# memoria com o processo pai)
_fetch_branch_data() {
  local b="$1" out="$2"
  local pr_json compare_json pr_arg="null" compare_arg="null"

  pr_json=$(gh pr list --repo "$repo" --head "$b" --state all \
    --json number,url,state,author --limit 10 \
    --jq 'if any(.[]; .state=="OPEN") then ([.[] | select(.state=="OPEN")])[0]
          elif any(.[]; .state=="MERGED") then ([.[] | select(.state=="MERGED")])[0]
          else empty end' 2>/dev/null)
  [[ -n "$pr_json" ]] && pr_arg="$pr_json"

  compare_json=$(gh api "repos/$repo/compare/$default_branch...$b" \
    --jq '{first: (.commits[0] // empty), last: (.commits[-1] // empty)}' 2>/dev/null)
  [[ -n "$compare_json" ]] && compare_arg="$compare_json"

  jq -n --argjson pr "$pr_arg" --argjson compare "$compare_arg" \
    '{pr: $pr, compare: $compare}' > "$out" 2>/dev/null
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

max_parallel=8
running=0
for i in "${!branch_names[@]}"; do
  _fetch_branch_data "${branch_names[$i]}" "$tmp_dir/$i.json" &
  (( ++running >= max_parallel )) && { wait -n; (( running-- )); }
done
wait

now=$(date +%s)
for i in "${!branch_names[@]}"; do
  b="${branch_names[$i]}"
  data="$(cat "$tmp_dir/$i.json" 2>/dev/null)"

  pr_number["$b"]=$(jq -r '.pr.number // empty' <<< "$data" 2>/dev/null)
  pr_url["$b"]=$(jq -r '.pr.url // empty' <<< "$data" 2>/dev/null)
  pr_state["$b"]=$(jq -r '.pr.state // empty' <<< "$data" 2>/dev/null)

  created_by["$b"]=$(jq -r '.compare.first.commit.author.name // empty' <<< "$data" 2>/dev/null)
  created_at["$b"]=$(jq -r '.compare.first.commit.author.date // empty' <<< "$data" 2>/dev/null)
  updated_by["$b"]=$(jq -r '.compare.last.commit.author.name // empty' <<< "$data" 2>/dev/null)
  updated_at["$b"]=$(jq -r '.compare.last.commit.author.date // empty' <<< "$data" 2>/dev/null)

  epoch=$(_iso_to_epoch "${updated_at[$b]}")
  commit_epoch["$b"]="$epoch"
  if [[ -n "$epoch" ]]; then
    age_days["$b"]=$(( (now - epoch) / 86400 ))
  else
    age_days["$b"]=""
  fi

  is_stale["$b"]=0
  if [[ -n "${age_days[$b]}" ]] && (( age_days[$b] > stale_days )); then
    is_stale["$b"]=1
  fi
done

rm -rf "$tmp_dir"
trap - EXIT

# ordena por commit mais antigo primeiro (idade desconhecida vai pro fim)
mapfile -t branch_names < <(
  for b in "${branch_names[@]}"; do
    printf '%s\t%s\n' "${commit_epoch[$b]:-9999999999}" "$b"
  done | sort -t $'\t' -k1,1n | cut -f2-
)

(( checking_msg )) && printf -- "\r\033[2K" >&2

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
table_rows="$(printf 'STATUS\tBRANCH\tCRIADA POR\tATUALIZADA POR\tIDADE\tFLAGS\n')"
for b in "${branch_names[@]}"; do
  _branch_matches_filters "$b" || continue
  any_shown=1

  if _branch_merged "$b"; then
    status="${GREEN}${BOLD}MERGED${RESET} [$(_dtb_link "${pr_url[$b]}" "PR #${pr_number[$b]}")]"
  elif [[ "${pr_state[$b]}" == "OPEN" ]]; then
    status="${DIM}-${RESET} [$(_dtb_link "${pr_url[$b]}" "PR aberta #${pr_number[$b]}")]"
  else
    status="${DIM}-${RESET} [sem PR]"
  fi

  flags=""
  [[ "${is_stale[$b]}" == "1" ]] && flags="${YELLOW}⚠ stale${RESET}"
  if [[ "${branch_protected[$b]}" == "true" ]]; then
    flags="${flags:+$flags }[protected]"
  fi

  age_label="idade desconhecida"
  [[ -n "${age_days[$b]}" ]] && age_label="${age_days[$b]} dias atrás"

  branch_cell="$(_dtb_link "https://github.com/$repo/tree/$b" "$b")"

  table_rows+="$(printf '\n%s\t%s\t%s\t%s\t%s\t%s' \
    "$status" "$branch_cell" "${DIM}${created_by[$b]:-?}${RESET}" "${DIM}${updated_by[$b]:-?}${RESET}" "${DIM}${age_label}${RESET}" "$flags")"
done
printf '%s\n' "$table_rows" | dtb_print_table "$BOLD" "$RESET"

if (( ! any_shown )); then
  echo "nenhuma branch encontrada com os filtros atuais (repo: $repo)" >&2
  exit 0
fi

if (( ! delete_mode )) && (( is_tty )); then
  echo >&2
  printf -- "${DIM}dica: git check-remote-branches %-14s apaga as candidatas (--yes pula confirmação)${RESET}\n" "--delete" >&2
  printf -- "${DIM}dica: git check-remote-branches %-14s mostra só as branches stale${RESET}\n" "--only-stale" >&2
  printf -- "${DIM}dica: git check-remote-branches %-14s saída em JSON pra script/pipe${RESET}\n" "--json" >&2
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
