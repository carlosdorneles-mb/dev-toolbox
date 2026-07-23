# git check-merged

Lista branches locais já mergeadas no remote (`origin` por padrão), com
opção de apagar as encontradas.

## Uso

```bash
git check-merged [--delete [--yes]] [--no-fetch] [--no-color] [--json]
```

## Descrição

Pra cada branch local (exceto a raiz `main`/`master`), verifica se o
conteúdo dela já foi integrado na branch raiz do remote, por 3 métodos
(qualquer um confirma merge):

1. **ancestor** - branch é ancestral direto da raiz (merge normal, merge
   `--ff-only`, ou merge commit preservando histórico).
2. **sem diff local** - `git cherry` mostra que todo commit da branch já
   tem equivalente (mesmo patch-id) na raiz - cobre merge via rebase que
   reaplica commit a commit.
3. **PR merged** - PR da branch (via `gh`) está com `state=MERGED` - único
   jeito confiável de detectar squash merge (1 commit novo na raiz, sem
   ancestral nem patch-id batendo com nenhum commit da branch).

Sem `gh`/`jq` instalados (ou sem login), o método 3 é pulado - branch
squash-mergeada pode aparecer como "não mergeada" nesse caso (avisa 1x em
stderr, mesmo aviso do `git chain`).

Branch com upstream remoto sumido (`git branch -vv` mostra `[gone]`) é
sinal extra, mostrado mas não usado sozinho pra decidir - só reforça o
resultado dos 3 métodos acima.

`--delete` remove (`git branch -D`) as branches identificadas como
mergeadas. Com `fzf` instalado (e terminal interativo), abre seleção
múltipla - digite p/ filtrar a lista, TAB marca as branches que quer
apagar, ENTER confirma. Sem `fzf`, cai pra confirmação y/N por branch.
`--yes`/`-y` pula qualquer seleção/confirmação e apaga todas de uma vez.
Nunca deleta a branch raiz nem a branch com checkout no momento
(protegida pelo próprio git contra deleção).

Enquanto verifica (fetch + consulta PR por branch), mostra
"verificando branches mergeadas..." em stderr, substituído pelo
resultado quando termina (só em terminal interativo, sem `--json`).

Roda `git fetch --all --quiet --prune` antes de comparar, a menos que
`--no-fetch` seja passado (usa o que já está local - mais rápido, pode
estar desatualizado).

## Opções

| Flag | Efeito |
|---|---|
| `--delete` | apaga as branches mergeadas encontradas (seleção via `fzf` se disponível, senão y/N por branch) |
| `--yes`, `-y` | junto com `--delete`, apaga todas sem seleção/confirmação |
| `--no-fetch` | pula o `git fetch` antes de comparar |
| `--no-color` | desabilita cores (mesmo efeito de `NO_COLOR=1`) |
| `--json` | array JSON com `{name, merged, reasons, gone}` por branch (exige `jq`) |
| `-h` | mostra a ajuda embutida |

## Exemplos

```bash
$ git check-merged
MERGED   fix/promotions-mail-push-campaign-exclusion   [PR merged, gone]
MERGED   chore/bump-deps                               [ancestor]
-        feat/promotions-autonomous-process            (branch atual)

$ git check-merged --delete
MERGED   fix/promotions-mail-push-campaign-exclusion   [PR merged, gone]
MERGED   chore/bump-deps                               [ancestor]
# abre fzf (com fzf instalado) - filtrar> TAB marca, ENTER confirma
Deleted branch fix/promotions-mail-push-campaign-exclusion (was 621e441).

$ git check-merged --delete --yes
MERGED   fix/promotions-mail-push-campaign-exclusion   [PR merged, gone]
# --yes apaga direto, sem seleção/confirmação
Deleted branch fix/promotions-mail-push-campaign-exclusion (was 621e441).

$ git check-merged --json
[
  {"name": "fix/promotions-mail-push-campaign-exclusion", "merged": true,
   "reasons": ["PR merged"], "gone": true},
  {"name": "feat/promotions-autonomous-process", "merged": false,
   "reasons": [], "gone": false}
]
```

## Dependências

Reaproveita `git/chain/lib/` (`provider.sh`, `git.sh`) pra resolver a
branch raiz e consultar PR via `gh`+`jq` - mesma dependência opcional do
`git chain` (funciona sem, só perde o método 3).

`fzf` é opcional - usado só na seleção do `--delete` interativo (funciona
sem, com fallback pra y/N por branch).
