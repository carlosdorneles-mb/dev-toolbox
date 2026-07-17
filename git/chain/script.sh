#!/bin/bash

tree_mode=1
no_pr=0
text_mode=0
json_mode=0
target_arg=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help=1; continue ;;
    --no-color) NO_COLOR=1; continue ;;
    --inline) tree_mode=0; continue ;;
    --no-pr) no_pr=1; continue ;;
    --text) text_mode=1; continue ;;
    --json) json_mode=1; continue ;;
  esac

  if [[ "$arg" == -* ]]; then
    echo "erro: opcao desconhecida '$arg'" >&2
    exit 1
  fi
  if [[ -n "$target_arg" ]]; then
    echo "erro: passe so um branch ou numero de PR por vez ('$target_arg' e '$arg')" >&2
    exit 1
  fi
  target_arg="$arg"
done

if (( json_mode )) && ! command -v jq &>/dev/null; then
  echo "erro: --json exige 'jq' instalado" >&2
  exit 1
fi

if [[ -n "$show_help" ]]; then
  cat <<'EOF'
git chain - mostra a cadeia de branches (stack de PRs) da branch atual até main

Uso:
  git chain [<branch> | <numero-da-PR>] [--no-color] [--inline] [--no-pr] [--text | --json]

Descrição:
  Percorre a branch atual até a branch raiz (main/master, ou a default
  branch do remote), resolvendo o parent de cada branch pela base
  declarada da PR (gh pr view --json baseRefName). Sem PR aberta, cai no
  fallback: branch com merge-base mais recente que não seja a própria
  ponta da branch atual (evita confundir filho/irmão com parent real).

  Passando um nome de branch ou numero de PR como argumento, mostra a
  cadeia a partir dessa branch em vez da branch atual (nao precisa fazer
  checkout nela). Numero de PR exige "gh"+"jq" instalados - a branch e
  resolvida via "gh pr view <numero> --json headRefName". Marcadores que
  so fazem sentido pra branch realmente selecionada no worktree (working
  tree suja, rebase/merge/cherry-pick em andamento) so aparecem se a
  branch consultada for a mesma que esta com checkout feito.

  Para cada branch na cadeia mostra, quando aplicável:
    #NNN       número da PR, clicável em terminais com suporte a
               hyperlink OSC 8 (iTerm2, kitty, VSCode, gnome-terminal)
    ▲N         N commits locais não enviados pro remote (unpushed)
    ▼N         N commits no remote ainda não trazidos (não pulled)
    [X]        branch sem remote (nunca deu push)
    [só remoto]  branch só existe no remote, nunca teve checkout local
               (achada como parent via PR ou heurística, sem comparar
               ahead/behind por falta de referência local)
    [📄N +A/-D]             PR aberta ou fechada tem N arquivos alterados,
                          A linhas adicionadas (verde), D removidas
                          (vermelho)
    [draft]                PR ainda em draft, não pronta pra review
    [merged]               PR dessa branch já foi mergeada (state MERGED)
    [closed sem merge]    PR foi fechada sem merge (abandonada)
    [PR CONFLICTING]      PR aberta tem conflito de merge (mergeable)
    [👍N/M]                 PR aberta tem N approvals de M revisores
                          designados no total (quem ja revisou + quem foi
                          pedido e ainda nao revisou; so a revisao mais
                          recente de cada revisor conta). Com --no-color
                          (ou fora de terminal) vira [✓N/M] - emoji tem
                          cor propria, nao respeita NO_COLOR
    [💬N]                   PR aberta tem N comentarios (issue comments,
                          nao inclui review comments inline)
    [blocked]              PR aberta bloqueada pra merge (checks/aprovacao
                          faltando, branch protection etc)
    [REBASE|MERGE|CHERRY-PICK|BISECT IN PROGRESS]   branch atual com uma
                          dessas operações em andamento (não finalizada)
    [dirty working tree]  branch atual tem mudanças trackeadas não
                          commitadas (untracked não conta)

  PR fechada sem merge (CLOSED) não é usada como fonte do parent na
  cadeia - só PR aberta ou já mergeada são confiáveis pra isso; CLOSED
  cai no fallback heurístico (a branch pode ter seguido outro rumo).

  Roda "git fetch --all --quiet" antes de comparar ahead/behind, então os
  números refletem o estado real dos remotes no momento da execução.

  Repo com mais de um remote (ex: origin + upstream de um fork): cada
  branch usa seu upstream configurado (git branch --set-upstream), se
  houver; senão o script procura o nome da branch em cada remote,
  preferindo "origin" quando existir. A raiz da cadeia (main/master) usa
  o HEAD do primeiro remote resolvível, mesma ordem de preferência.
  Quando o remote de uma branch não é "origin", isso aparece no marcador
  ("via <remote>").

  Se a cadeia não conseguir chegar até a raiz (parent não resolvido nem
  por PR nem pela heurística), imprime um aviso em stderr e mostra a
  cadeia truncada até onde conseguiu.

  Saída colorida (bold no HEAD/main, cyan no #PR, amarelo ▲, vermelho
  ▼/[X]) quando rodado em terminal interativo; sem cor se a saída for
  redirecionada/pipada. O link OSC 8 do #PR só é emitido em terminal
  interativo (nunca em saída redirecionada/pipada, mesmo com cor).

Opções:
  <branch>     mostra a cadeia a partir dessa branch (local ou remota),
               sem precisar dar checkout nela
  <numero-da-PR>  mostra a cadeia a partir da branch dessa PR - resolvida
               via "gh pr view <numero> --json headRefName" (exige
               "gh"+"jq"). So um dos dois (branch ou numero) por vez
  -h           mostra esta ajuda
  --no-color   desabilita cores (mesmo efeito de NO_COLOR=1)
  --inline     mostra a cadeia em uma linha só (com setas →) em vez do
               modo árvore (padrão, raiz no topo)
  --no-pr      esconde tudo relacionado a PR (#NNN, draft, merged, closed,
               conflicting, approvals, blocked) - so a hierarquia de
               branches + ahead/behind/[X]. A cadeia continua usando o
               gh por baixo dos panos pra resolver o parent correto,
               so a exibicao fica mais limpa
  --text       so os nomes das branches, um por linha, raiz primeiro -
               sem cor, sem #PR, sem ahead/behind. Pra uso em scripts
               (ex: "git chain --text | while read -r b; do ...; done").
               Ignora --no-color/--inline/--no-pr/--json.
  --json       array JSON com detalhes de cada branch (raiz primeiro):
               name, is_current, is_root, pr (null se não houver: number,
               url, state, draft, mergeable, approvals, reviewers_total,
               merge_status),
               has_local, has_remote, remote (nome do remote onde a branch
               foi encontrada, null se has_remote for false), ahead,
               behind, local_conflict e dirty_worktree (os dois últimos só
               preenchidos na branch atual). Exige "jq" instalado. Combina
               com --no-pr (pr vira null em todas). Ignora
               --no-color/--inline/--text.

  Nota: "git chain --help" não funciona - o git intercepta "--help" para
  qualquer alias e imprime só a definição dele, sem executar. Use -h.

Exemplos:
  $ git chain
  main
  └─ branch-base #767
     └─ minha-branch #768 (▼6)

  # modo uma linha só (main primeiro, igual árvore)
  $ git chain --inline
  main (▼6) → branch-base #767 → minha-branch #768

  # cadeia de outra branch, sem dar checkout nela
  $ git chain minha-branch
  main
  └─ branch-base #767
     └─ minha-branch #768 (▼6)

  # cadeia a partir do numero da PR
  $ git chain 768

  # sem cores (--no-color equivale a NO_COLOR=1)
  $ git chain --no-color
  main
  └─ branch-base #767
     └─ minha-branch #768 (▼6)

  # só os nomes, raiz primeiro, um por linha
  $ git chain --text
  main
  branch-base
  minha-branch

  # detalhes em JSON
  $ git chain --json
  [
    {"name": "main", "is_current": false, "is_root": true, "pr": null, ...},
    {"name": "minha-branch", "is_current": true, "is_root": false,
     "pr": {"number": 768, "url": "...", "state": "OPEN", ...}, ...}
  ]
EOF
  exit 0
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "erro: nao esta dentro de um repositorio git" >&2
  exit 1
fi

real_current=$(git rev-parse --abbrev-ref HEAD)

if [[ -z "$target_arg" && "$real_current" == "HEAD" ]]; then
  echo "erro: HEAD destacado (detached) - va para uma branch antes de rodar git chain, ou passe um branch/PR como argumento" >&2
  exit 1
fi

# dispara o fetch em background ja - nao depende da cadeia resolvida, roda em
# paralelo com as chamadas gh que vem a seguir em vez de esperar elas acabarem.
# --all: repo pode ter mais de um remote (ex: origin + upstream de um fork)
git fetch --all --quiet 2>/dev/null &
_fetch_pid=$!

# remotes do repo, com "origin" primeiro se existir - ordem de preferencia
# usada sempre que uma branch existe em mais de um remote e precisamos
# escolher um so pra exibir/comparar
mapfile -t remotes_ordered < <(git remote)
if printf '%s\n' "${remotes_ordered[@]}" | grep -qx origin; then
  _others=()
  for _r in "${remotes_ordered[@]}"; do [[ "$_r" != "origin" ]] && _others+=("$_r"); done
  remotes_ordered=("origin" "${_others[@]}")
fi

# raiz da cadeia: default branch do primeiro remote que tiver HEAD resolvivel,
# com fallback pra main/master (nessa ordem, se existirem localmente)
root_branch=""
for _r in "${remotes_ordered[@]}"; do
  _rb=$(git symbolic-ref --short "refs/remotes/$_r/HEAD" 2>/dev/null)
  if [[ -n "$_rb" ]]; then
    root_branch="${_rb#"$_r"/}"
    break
  fi
done
if [[ -z "$root_branch" ]]; then
  if git show-ref --verify --quiet refs/heads/main; then
    root_branch="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    root_branch="master"
  else
    # nenhum remote com HEAD resolvivel (falta "git remote set-head") nem
    # main/master local - default "main" pode nao ser a raiz real do repo
    echo "aviso: nao foi possivel detectar a branch raiz (remote sem HEAD resolvivel, rode 'git remote set-head <remote> --auto') - assumindo 'main'" >&2
    root_branch="main"
  fi
fi

# checa "gh"+"jq" uma unica vez - sem qualquer um dos dois, pula todas as
# chamadas de PR direto (senao cada branch tentaria 1-2 chamadas gh + varios
# jq fadados a falhar, so desperdicio de processo)
_gh_available=0
command -v gh &>/dev/null && command -v jq &>/dev/null && _gh_available=1

# avisa 1x sobre o que falta pra ter dados de PR - so em stderr, so quando
# a exibicao de PR faz sentido (nao em --text, que ja ignora PR de proposito)
if (( ! no_pr )) && (( ! text_mode )); then
  if (( ! _gh_available )); then
    if ! command -v gh &>/dev/null; then
      echo "info: 'gh' (GitHub CLI) nao encontrado - instale e rode 'gh auth login' pra ver dados de PR (#numero, approvals, comentarios, diffstat etc)" >&2
    elif ! command -v jq &>/dev/null; then
      echo "info: 'jq' nao encontrado - instale pra ver dados de PR (#numero, approvals, comentarios, diffstat etc)" >&2
    fi
  elif ! gh auth status &>/dev/null; then
    echo "info: 'gh' instalado mas sem login - rode 'gh auth login' pra ver dados de PR (#numero, approvals, comentarios, diffstat etc)" >&2
  fi
fi

# cache dos dados de PR por branch: evita chamar "gh pr view" 2x pro mesmo branch
declare -A pr_base pr_number pr_url pr_mergeable pr_state pr_draft pr_approvals pr_reviewers_total pr_merge_status pr_comments pr_changed_files pr_additions pr_deletions

_fetch_pr_info() {
  local b="$1"
  [[ -n "${pr_number[$b]+x}" ]] && return  # ja consultado (mesmo sem PR)

  if (( ! _gh_available )); then
    pr_number["$b"]=""  # marca como "ja consultado, sem PR" pra nao tentar de novo
    return
  fi

  local fields="baseRefName,number,url,mergeable,isDraft,mergeStateStatus,latestReviews,reviewRequests,state,comments,changedFiles,additions,deletions"

  # uma chamada so (nao 2): busca todos os estados e prioriza a PR aberta via
  # jq, se existir mais de uma pro mesmo branch (ex: fechada antiga + atual)
  local json
  json=$(gh pr list --head "$b" --state all --json "$fields" --limit 10 \
    --jq 'if any(.[]; .state=="OPEN") then ([.[] | select(.state=="OPEN")])[0] else .[0] end' 2>/dev/null)

  pr_state["$b"]=$(jq -r '.state // empty' <<< "$json" 2>/dev/null)
  if [[ "${pr_state[$b]}" == "OPEN" ]]; then
    # aprovacoes: 1 por revisor, considerando so a revisao mais recente de cada um
    pr_approvals["$b"]=$(jq -r '[.latestReviews[]? | select(.state=="APPROVED")] | length' <<< "$json" 2>/dev/null)
    # total de revisores designados: quem ja revisou (latestReviews, 1 por pessoa)
    # + quem foi pedido mas ainda nao revisou (reviewRequests)
    pr_reviewers_total["$b"]=$(jq -r '((.latestReviews // []) | length) + ((.reviewRequests // []) | length)' <<< "$json" 2>/dev/null)
    pr_merge_status["$b"]=$(jq -r '.mergeStateStatus // empty' <<< "$json" 2>/dev/null)
    pr_comments["$b"]=$(jq -r '(.comments // []) | length' <<< "$json" 2>/dev/null)
  fi
  pr_base["$b"]=$(jq -r '.baseRefName // empty' <<< "$json" 2>/dev/null)
  pr_number["$b"]=$(jq -r '.number // empty' <<< "$json" 2>/dev/null)
  pr_url["$b"]=$(jq -r '.url // empty' <<< "$json" 2>/dev/null)
  pr_mergeable["$b"]=$(jq -r '.mergeable // empty' <<< "$json" 2>/dev/null)
  pr_changed_files["$b"]=$(jq -r '.changedFiles // 0' <<< "$json" 2>/dev/null)
  pr_additions["$b"]=$(jq -r '.additions // 0' <<< "$json" 2>/dev/null)
  pr_deletions["$b"]=$(jq -r '.deletions // 0' <<< "$json" 2>/dev/null)
  pr_draft["$b"]=$(jq -r '.isDraft // false' <<< "$json" 2>/dev/null)
}

# PR fechada sem merge (CLOSED) e considerada fonte pouco confiavel de parent:
# branch pode ter seguido vida propria com um parent real diferente depois disso
_pr_base_trusted() {
  local b="$1"
  [[ "${pr_state[$b]}" == "OPEN" || "${pr_state[$b]}" == "MERGED" ]] && echo "${pr_base[$b]}"
}

# estado local so faz sentido pra branch atual (HEAD) - working tree e rebase/merge/cherry-pick/bisect
# sao globais do repo, nao por branch
_git_dir=$(git rev-parse --git-dir 2>/dev/null)

_local_conflict_marker() {
  if [[ -d "$_git_dir/rebase-merge" || -d "$_git_dir/rebase-apply" ]]; then
    echo "REBASE"
  elif [[ -f "$_git_dir/MERGE_HEAD" ]]; then
    echo "MERGE"
  elif [[ -f "$_git_dir/CHERRY_PICK_HEAD" ]]; then
    echo "CHERRY-PICK"
  elif [[ -f "$_git_dir/BISECT_LOG" ]]; then
    echo "BISECT"
  fi
}

_dirty_worktree() {
  [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]]
}

# acha o remote+ref de uma branch, considerando todos os remotes do repo:
# 1) se a branch e local e tem upstream configurado (git branch --set-upstream),
#    usa esse - e a fonte mais confiavel de "qual remote e o dela"
# 2) senao, procura em cada remote (ordem de remotes_ordered) um branch de
#    mesmo nome
# saida: "<remote>\t<remote>/<nome>" (tab-separated) ou vazio se nao achou
_remote_ref_for() {
  local name="$1" upstream
  if git show-ref --verify --quiet "refs/heads/$name"; then
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "$name@{upstream}" 2>/dev/null)
    if [[ -n "$upstream" ]] && git show-ref --verify --quiet "refs/remotes/$upstream"; then
      printf '%s\t%s\n' "${upstream%%/*}" "$upstream"
      return
    fi
  fi

  local r
  for r in "${remotes_ordered[@]}"; do
    if git show-ref --verify --quiet "refs/remotes/$r/$name"; then
      printf '%s\t%s\n' "$r" "$r/$name"
      return
    fi
  done
}

# resolve o ref git usavel pra um nome de branch: prefere local, cai pro
# remoto (de qualquer remote do repo) se so existir la - cobre parent que
# nunca teve checkout local
_ref_for() {
  local name="$1"
  if git show-ref --verify --quiet "refs/heads/$name"; then
    echo "$name"
    return
  fi

  local info
  info="$(_remote_ref_for "$name")"
  [[ -n "$info" ]] && echo "${info#*$'\t'}"
}

# cache do "for-each-ref": local + remoto de TODOS os remotes (nome canonico
# sem prefixo de remote), evita rescanear todos os branches a cada iteracao
# e cobre parent so-remoto (inclusive so existente num remote nao-origin)
all_branches=$(
  {
    git for-each-ref --format='%(refname:short)' refs/heads/
    for _r in "${remotes_ordered[@]}"; do
      git for-each-ref --format='%(refname:short)' "refs/remotes/$_r/" | sed "s#^$_r/##" | grep -v '^HEAD$'
    done
  } | sort -u
)

# resolve o ponto de partida da cadeia: branch/PR passada por argumento, ou a
# branch atualmente com checkout feito (comportamento padrao)
if [[ -n "$target_arg" ]]; then
  if [[ "$target_arg" =~ ^[0-9]+$ ]]; then
    if (( ! _gh_available )); then
      echo "erro: buscar por numero de PR exige 'gh' e 'jq' instalados" >&2
      exit 1
    fi
    resolved_branch=$(gh pr view "$target_arg" --json headRefName --jq .headRefName 2>/dev/null)
    if [[ -z "$resolved_branch" ]]; then
      echo "erro: PR #$target_arg nao encontrada (ou sem permissao de acesso)" >&2
      exit 1
    fi
    current="$resolved_branch"
  else
    current="$target_arg"
    if [[ -z "$(_ref_for "$current")" ]]; then
      echo "erro: branch '$current' nao encontrada (nem local nem em nenhum remote)" >&2
      exit 1
    fi
  fi
else
  current="$real_current"
fi

chain=("$current")
declare -A visited=(["$current"]=1)

truncated=0
while [[ "$current" != "$root_branch" && "$current" != "main" && "$current" != "master" ]]; do
  _fetch_pr_info "$current"
  base="$(_pr_base_trusted "$current")"

  # base declarada na PR mas a branch ja nao existe (local nem remota) - ex: deletada pos-merge
  if [[ -n "$base" && -z "$(_ref_for "$base")" ]]; then
    echo "aviso: PR de '$current' aponta pra base '$base', que nao existe mais (local nem remota) - usando heuristica" >&2
    base=""
  fi

  # sem PR aberta/confiavel -> fallback: heuristica local por merge-base mais recente
  if [[ -z "$base" ]]; then
    best_branch=""
    best_date=0
    current_ref=$(_ref_for "$current")
    current_tip=$(git rev-parse "$current_ref" 2>/dev/null)

    for b in $all_branches; do
      [[ "$b" == "$current" ]] && continue
      [[ -n "${visited[$b]+x}" ]] && continue

      b_ref=$(_ref_for "$b")
      [[ -z "$b_ref" ]] && continue

      mb=$(git merge-base "$current_ref" "$b_ref" 2>/dev/null)
      [[ -z "$mb" ]] && continue

      # rejeita candidato se mb == tip do current (b e filho/irmao, nao ancestral real)
      [[ "$mb" == "$current_tip" ]] && continue

      date=$(git show -s --format=%ct "$mb" 2>/dev/null)
      if (( date > best_date )); then
        best_date=$date
        best_branch=$b
      fi
    done

    base="$best_branch"
  fi

  if [[ -z "$base" || -n "${visited[$base]+x}" ]]; then
    truncated=1
    break
  fi

  chain+=("$base")
  visited["$base"]=1
  current=$base
done

if (( truncated )); then
  echo "aviso: nao foi possivel resolver o parent de '$current' - cadeia truncada" >&2
fi

wait "$_fetch_pid" 2>/dev/null  # so espera o fetch em background aqui, na hora que o resultado importa

# --text: so os nomes, raiz primeiro, sem cor/PR/ahead-behind - sai direto,
# nao precisa dos dados que os outros modos calculam a seguir
if (( text_mode )); then
  for ((i=${#chain[@]}-1; i>=0; i--)); do
    echo "${chain[$i]}"
  done
  exit 0
fi

# cores ANSI (desligadas se saida nao for terminal ou se NO_COLOR estiver setado)
is_tty=0
[[ -t 1 ]] && is_tty=1

if (( is_tty )) && [[ -z "$NO_COLOR" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  CYAN=$'\e[36m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; GREEN=$'\e[32m'
  APPROVE_MARK="👍"
else
  BOLD=""; DIM=""; RESET=""; CYAN=""; YELLOW=""; RED=""; GREEN=""
  APPROVE_MARK="✓"  # emoji tem cor propria (nao respeita NO_COLOR) - sem cor usa so ascii
fi

# monta o label de cada branch (nome + #PR + ahead/behind), independente do modo de impressao
# (--json reaproveita os dados coletados aqui, sem chamadas git/gh extras)
labels=()
declare -A ahead_map behind_map has_local_map has_remote_map remote_name_map
current_conflict=""
current_dirty=0
for ((i=0; i<${#chain[@]}; i++)); do
  b="${chain[$i]}"
  label="$b"

  # ponta da cadeia (HEAD real, ou a branch/PR passada por argumento) e
  # main/master ficam em negrito
  if [[ "$i" -eq 0 || "$b" == "main" || "$b" == "master" ]]; then
    label="${BOLD}${label}${RESET}"
  fi

  (( ! no_pr )) && _fetch_pr_info "$b"
  if (( ! no_pr )) && [[ -n "${pr_number[$b]}" ]]; then
    pr_label="#${pr_number[$b]}"
    # link OSC 8 so em terminal interativo - nunca em saida redirecionada/pipada
    if (( is_tty )) && [[ -n "${pr_url[$b]}" ]]; then
      pr_label=$'\e]8;;'"${pr_url[$b]}"$'\e\\'"$pr_label"$'\e]8;;\e\\'
    fi
    label="$label ${CYAN}${pr_label}${RESET}"

    (( ${pr_changed_files[$b]:-0} > 0 )) && label="$label ${DIM}[📄${pr_changed_files[$b]} ${GREEN}+${pr_additions[$b]:-0}${RESET}${DIM}/${RED}-${pr_deletions[$b]:-0}${RESET}${DIM}]${RESET}"

    if [[ "${pr_draft[$b]}" == "true" ]]; then
      label="$label ${DIM}[draft]${RESET}"
    fi

    # state primeiro: PR merged/closed nunca deve ser mostrada como conflitante
    if [[ "${pr_state[$b]}" == "MERGED" ]]; then
      label="$label ${DIM}[merged]${RESET}"
    elif [[ "${pr_state[$b]}" == "CLOSED" ]]; then
      label="$label ${RED}[closed sem merge]${RESET}"
    elif [[ "${pr_mergeable[$b]}" == "CONFLICTING" ]]; then
      label="$label ${RED}${BOLD}[PR CONFLICTING]${RESET}"
    fi

    # approvals/reviewers e status de merge so fazem sentido pra PR ainda aberta
    if [[ "${pr_state[$b]}" == "OPEN" ]]; then
      (( ${pr_reviewers_total[$b]:-0} > 0 )) && label="$label ${DIM}[${APPROVE_MARK}${pr_approvals[$b]:-0}/${pr_reviewers_total[$b]}]${RESET}"

      (( ${pr_comments[$b]:-0} > 0 )) && label="$label ${DIM}[💬${pr_comments[$b]}]${RESET}"

      [[ "${pr_merge_status[$b]}" == "BLOCKED" ]] && label="$label ${RED}${BOLD}[blocked]${RESET}"
    fi
  fi

  # estado local (working tree, rebase/merge em andamento) so se aplica a
  # branch com checkout de fato feito - se "b" e uma branch consultada por
  # argumento (nao a real HEAD), esses marcadores nao fazem sentido pra ela
  if [[ "$b" == "$real_current" ]]; then
    conflict=$(_local_conflict_marker)
    current_conflict="$conflict"
    [[ -n "$conflict" ]] && label="$label ${RED}${BOLD}[$conflict IN PROGRESS]${RESET}"

    if _dirty_worktree; then
      current_dirty=1
      label="$label ${YELLOW}[dirty working tree]${RESET}"
    fi
  fi

  has_local=0
  git show-ref --verify --quiet "refs/heads/$b" && has_local=1

  remote_info="$(_remote_ref_for "$b")"
  remote_name=""
  remote_ref=""
  [[ -n "$remote_info" ]] && IFS=$'\t' read -r remote_name remote_ref <<< "$remote_info"
  has_remote=0
  [[ -n "$remote_ref" ]] && has_remote=1
  has_local_map["$b"]=$has_local
  has_remote_map["$b"]=$has_remote
  remote_name_map["$b"]="$remote_name"

  # so anota o nome do remote quando nao for "origin" - caso comum (1 remote
  # so, ou origin) fica limpo igual antes; multi-remote fica explicito
  remote_suffix=""
  [[ -n "$remote_name" && "$remote_name" != "origin" ]] && remote_suffix=" via ${remote_name}"

  ahead=""
  behind=""
  if (( has_local && has_remote )); then
    read -r behind ahead <<< "$(git rev-list --left-right --count "$remote_ref...$b" 2>/dev/null)"
    marks=""
    (( ahead > 0 )) && marks="${marks}${YELLOW}▲${ahead}${RESET} "
    (( behind > 0 )) && marks="${marks}${RED}▼${behind}${RESET} "
    if [[ -n "$marks" ]]; then
      label="$label (${marks% }${remote_suffix})"
    fi
  elif (( has_remote )); then
    # so existe no remote, nunca teve checkout local - nao da pra comparar ahead/behind
    label="$label ${DIM}[so remoto${remote_suffix}]${RESET}"
  else
    label="$label ${BOLD}${RED}[X]${RESET}"
  fi
  ahead_map["$b"]="$ahead"
  behind_map["$b"]="$behind"

  labels+=("$label")
done

if (( json_mode )); then
  json_items=()
  for ((i=${#chain[@]}-1; i>=0; i--)); do
    b="${chain[$i]}"
    is_current=$( [[ "$b" == "$real_current" ]] && echo true || echo false )
    is_root=$( [[ "$b" == "$root_branch" || "$b" == "main" || "$b" == "master" ]] && echo true || echo false )

    pr_json="null"
    if [[ -n "${pr_number[$b]:-}" ]]; then
      pr_json=$(jq -n \
        --argjson number "${pr_number[$b]}" \
        --arg url "${pr_url[$b]:-}" \
        --arg state "${pr_state[$b]:-}" \
        --argjson draft "$( [[ "${pr_draft[$b]:-}" == "true" ]] && echo true || echo false )" \
        --arg mergeable "${pr_mergeable[$b]:-}" \
        --argjson approvals "${pr_approvals[$b]:-0}" \
        --argjson reviewers_total "${pr_reviewers_total[$b]:-0}" \
        --arg merge_status "${pr_merge_status[$b]:-}" \
        --argjson comments "${pr_comments[$b]:-0}" \
        --argjson changed_files "${pr_changed_files[$b]:-0}" \
        --argjson additions "${pr_additions[$b]:-0}" \
        --argjson deletions "${pr_deletions[$b]:-0}" \
        '{number: $number, url: $url, state: $state, draft: $draft, mergeable: $mergeable, approvals: $approvals, reviewers_total: $reviewers_total, merge_status: $merge_status, comments: $comments, changed_files: $changed_files, additions: $additions, deletions: $deletions}')
    fi

    local_conflict_val="null"
    [[ "$b" == "$real_current" && -n "$current_conflict" ]] && local_conflict_val="\"$current_conflict\""
    dirty_val=$( [[ "$b" == "$real_current" && "$current_dirty" -eq 1 ]] && echo true || echo false )

    ahead_val="${ahead_map[$b]:-}"
    behind_val="${behind_map[$b]:-}"

    json_items+=("$(jq -n \
      --arg name "$b" \
      --argjson is_current "$is_current" \
      --argjson is_root "$is_root" \
      --argjson pr "$pr_json" \
      --argjson has_local "$( [[ "${has_local_map[$b]:-0}" -eq 1 ]] && echo true || echo false )" \
      --argjson has_remote "$( [[ "${has_remote_map[$b]:-0}" -eq 1 ]] && echo true || echo false )" \
      --arg remote "${remote_name_map[$b]:-}" \
      --argjson ahead "$( [[ -n "$ahead_val" ]] && echo "$ahead_val" || echo null )" \
      --argjson behind "$( [[ -n "$behind_val" ]] && echo "$behind_val" || echo null )" \
      --argjson local_conflict "$local_conflict_val" \
      --argjson dirty_worktree "$dirty_val" \
      '{name: $name, is_current: $is_current, is_root: $is_root, pr: $pr, has_local: $has_local, has_remote: $has_remote, remote: (if $remote == "" then null else $remote end), ahead: $ahead, behind: $behind, local_conflict: $local_conflict, dirty_worktree: $dirty_worktree}')")
  done

  printf '%s\n' "${json_items[@]}" | jq -s '.'
  exit 0
fi

if (( tree_mode )); then
  # chain[0]=atual ... chain[last]=raiz; arvore imprime raiz no topo, entao percorre ao contrario
  depth=0
  for ((i=${#chain[@]}-1; i>=0; i--)); do
    if (( i == ${#chain[@]}-1 )); then
      echo "${labels[$i]}"
    else
      printf '%*s└─ %s\n' "$(((depth-1)*3))" '' "${labels[$i]}"
    fi
    ((depth++))
  done
else
  # imprime main -> ... -> branch atual, marcando ahead/behind do remoto
  # chain[0]=atual ... chain[last]=raiz; percorre ao contrario pra raiz ficar primeiro
  result=""
  for ((i=${#chain[@]}-1; i>=0; i--)); do
    if [[ -z "$result" ]]; then
      result="${labels[$i]}"
    else
      result="$result ${DIM}→${RESET} ${labels[$i]}"
    fi
  done
  echo "$result"
fi
