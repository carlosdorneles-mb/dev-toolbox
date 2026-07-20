#!/bin/bash
# helpers de git puro (remotes, refs, estado local) + cache de dados de PR.
# Nao depende de qual provider de PR ta em uso - so consome as arrays pr_*
# preenchidas via lib/provider.sh.

# cache dos dados de PR por branch: evita chamar o provider 2x pro mesmo branch
declare -A pr_base pr_number pr_url pr_mergeable pr_state pr_draft pr_approvals pr_reviewers_total pr_merge_status pr_comments pr_changed_files pr_additions pr_deletions

# popula as arrays pr_* pra branch "$1" via o provider ativo (github hoje)
fetch_pr_info() {
  pr_provider_fetch_pr_info "$1"
}

# PR fechada sem merge (CLOSED) e considerada fonte pouco confiavel de parent:
# branch pode ter seguido vida propria com um parent real diferente depois disso
pr_base_trusted() {
  local b="$1"
  [[ "${pr_state[$b]}" == "OPEN" || "${pr_state[$b]}" == "MERGED" ]] && echo "${pr_base[$b]}"
}

# heuristica local: entre as branches conhecidas (array global all_branches,
# ja excluindo as visitadas no array associativo global visited), acha a que
# tem o merge-base mais recente com "$1" - candidata mais provavel a ser o
# parent real. Usada tanto como fallback (sem PR confiavel) quanto pra
# validar a base declarada de uma PR contra o historico local (ver
# _pr_base_matches_local em script.sh).
_local_heuristic_parent() {
  local current="$1"
  local current_ref current_tip
  current_ref=$(_ref_for "$current")
  current_tip=$(git rev-parse "$current_ref" 2>/dev/null)

  local best_branch="" best_date=0
  local b b_ref mb date
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

  echo "$best_branch"
}

# monta remotes_ordered (global) com "origin" primeiro se existir - ordem de
# preferencia usada sempre que uma branch existe em mais de um remote
resolve_remotes_ordered() {
  mapfile -t remotes_ordered < <(git remote)
  if printf '%s\n' "${remotes_ordered[@]}" | grep -qx origin; then
    local others=()
    local r
    for r in "${remotes_ordered[@]}"; do [[ "$r" != "origin" ]] && others+=("$r"); done
    remotes_ordered=("origin" "${others[@]}")
  fi
}

# resolve root_branch (global): default branch do primeiro remote com HEAD
# resolvivel, com fallback pra main/master locais
resolve_root_branch() {
  root_branch=""
  local r rb
  for r in "${remotes_ordered[@]}"; do
    rb=$(git symbolic-ref --short "refs/remotes/$r/HEAD" 2>/dev/null)
    if [[ -n "$rb" ]]; then
      root_branch="${rb#"$r"/}"
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
      _warn "nao foi possivel detectar a branch raiz (remote sem HEAD resolvivel, rode 'git remote set-head <remote> --auto') - assumindo 'main'"
      root_branch="main"
    fi
  fi
}

# estado local so faz sentido pra branch atual (HEAD) - working tree e
# rebase/merge/cherry-pick/bisect sao globais do repo, nao por branch
_local_conflict_marker() {
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  if [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
    echo "REBASE"
  elif [[ -f "$git_dir/MERGE_HEAD" ]]; then
    echo "MERGE"
  elif [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
    echo "CHERRY-PICK"
  elif [[ -f "$git_dir/BISECT_LOG" ]]; then
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

# cache do "for-each-ref" (global all_branches): local + remoto de TODOS os
# remotes (nome canonico sem prefixo de remote), evita rescanear todos os
# branches a cada iteracao e cobre parent so-remoto (inclusive num remote
# nao-origin)
resolve_all_branches() {
  all_branches=$(
    {
      git for-each-ref --format='%(refname:short)' refs/heads/
      local r
      for r in "${remotes_ordered[@]}"; do
        git for-each-ref --format='%(refname:short)' "refs/remotes/$r/" | sed "s#^$r/##" | grep -v '^HEAD$'
      done
    } | sort -u
  )
}
