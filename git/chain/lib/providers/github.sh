#!/bin/bash
# provider: GitHub, via "gh" CLI + "jq". Implementa a interface esperada por
# lib/provider.sh (funções prefixadas "github_"). Pra suportar outro host de
# PR (ex: GitLab), crie lib/providers/<nome>.sh com a mesma interface e
# registre em PR_PROVIDER_NAME_LABEL/case do lib/provider.sh.

github_name_label="GitHub CLI"
github_cli_bin="gh"

github_available() {
  command -v gh &>/dev/null && command -v jq &>/dev/null
}

# mensagem de diagnostico (stderr) sobre o que falta pra ter dados de PR -
# cli ausente, jq ausente, ou cli sem login
github_deps_hint() {
  if ! command -v gh &>/dev/null; then
    echo "info: 'gh' (GitHub CLI) nao encontrado - instale e rode 'gh auth login' pra ver dados de PR (#numero, approvals, comentarios, diffstat etc)" >&2
  elif ! command -v jq &>/dev/null; then
    echo "info: 'jq' nao encontrado - instale pra ver dados de PR (#numero, approvals, comentarios, diffstat etc)" >&2
  elif ! gh auth status &>/dev/null; then
    echo "info: 'gh' instalado mas sem login - rode 'gh auth login' pra ver dados de PR (#numero, approvals, comentarios, diffstat etc)" >&2
  fi
}

# popula as arrays associativas pr_* (declaradas no script principal) pra
# branch "$1" - uma chamada de rede por branch, cacheada por pr_number[$b]
github_fetch_pr_info() {
  local b="$1"
  [[ -n "${pr_number[$b]+x}" ]] && return  # ja consultado (mesmo sem PR)

  if ! github_available; then
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

# resolve numero de PR -> nome da branch (headRefName). Echo vazio se nao achou
github_resolve_pr_branch() {
  local number="$1"
  gh pr view "$number" --json headRefName --jq .headRefName 2>/dev/null
}
